import 'dart:typed_data';

import 'package:diary/data/models/webdav_config.dart';
import 'package:minio/minio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

class RemoteStoreException implements Exception {
  const RemoteStoreException(this.code, {this.isNotFound = false});
  final String code;
  final bool isNotFound;
  @override
  String toString() => 'S3: $code';
}

class RemoteFile {
  const RemoteFile({this.path, this.name, this.isDir, this.mTime});
  final String? path;
  final String? name;
  final bool? isDir;
  final DateTime? mTime;
}

abstract class SyncRemoteStore {
  factory SyncRemoteStore(WebDavConfig config) =>
      config.backend == SyncBackend.s3
      ? S3RemoteStore(config)
      : WebDavRemoteStore(config);

  Future<void> ping();
  Future<void> mkdirAll(String path);
  Future<List<int>> read(String path);
  Future<void> write(String path, Uint8List bytes);
  Future<void> remove(String path);
  Future<List<RemoteFile>> readDir(String path);
}

class WebDavRemoteStore implements SyncRemoteStore {
  WebDavRemoteStore(WebDavConfig config)
    : _client = webdav.newClient(
        config.serverUrl.trim(),
        user: config.username.trim(),
        password: config.password,
        debug: false,
      ) {
    _client.setConnectTimeout(5000);
    _client.setSendTimeout(30000);
    _client.setReceiveTimeout(30000);
    _client.setHeaders({'accept-charset': 'utf-8'});
  }
  final webdav.Client _client;
  @override
  Future<void> ping() => _client.ping();
  @override
  Future<void> mkdirAll(String path) => _client.mkdirAll(path);
  @override
  Future<List<int>> read(String path) => _client.read(path);
  @override
  Future<void> write(String path, Uint8List bytes) =>
      _client.write(path, bytes);
  @override
  Future<void> remove(String path) => _client.remove(path);
  @override
  Future<List<RemoteFile>> readDir(String path) async => [
    for (final file in await _client.readDir(path))
      RemoteFile(
        path: file.path,
        name: file.name,
        isDir: file.isDir,
        mTime: file.mTime,
      ),
  ];
}

/// Keeps the sync engine's slash-prefixed paths while S3 uses object keys.
class S3RemoteStore implements SyncRemoteStore {
  S3RemoteStore(WebDavConfig config) : _config = config {
    final s3 = config.s3;
    if (!s3.isConfigured) throw ArgumentError('Invalid S3 configuration');
    final endpoint = Uri.parse(s3.endpoint.trim());
    _client = Minio(
      endPoint: endpoint.host,
      port: endpoint.port,
      useSSL: endpoint.scheme == 'https',
      accessKey: s3.accessKey.trim(),
      secretKey: s3.secretKey,
      region: s3.region.trim(),
      pathStyle: s3.pathStyle,
    );
  }

  final WebDavConfig _config;
  late final Minio _client;
  Future<T> _request<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on MinioS3Error catch (e) {
      final code = e.error?.code ?? 'HTTP ${e.response?.statusCode ?? "error"}';
      throw RemoteStoreException(
        code,
        isNotFound:
            code == 'NoSuchKey' ||
            code == 'NotFound' ||
            e.response?.statusCode == 404,
      );
    } catch (_) {
      throw const RemoteStoreException(
        'Request failed; check endpoint, region and connection',
      );
    }
  }

  String get _bucket => _config.s3.bucket.trim();
  static String objectKey(String path) => path.replaceFirst(RegExp(r'^/+'), '');

  @override
  Future<void> ping() => _request(() async {
    // List only the configured prefix, allowing prefix-scoped bucket policies.
    final root = objectKey(_config.s3.prefix).replaceFirst(RegExp(r'/+$'), '');
    await _client.listObjectsV2Query(
      _bucket,
      root.isEmpty ? '' : '$root/',
      null,
      '/',
      1,
      null,
    );
  });

  @override
  Future<void> mkdirAll(String path) async {} // S3 prefixes are implicit.

  @override
  Future<List<int>> read(String path) => _request(() async {
    final stream = await _client.getObject(_bucket, objectKey(path));
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  });

  @override
  Future<void> write(String path, Uint8List bytes) => _request(() async {
    await _client.putObject(
      _bucket,
      objectKey(path),
      Stream.value(bytes),
      size: bytes.length,
    );
  });

  @override
  Future<void> remove(String path) =>
      _request(() => _client.removeObject(_bucket, objectKey(path)));

  @override
  Future<List<RemoteFile>> readDir(String path) => _request(() async {
    final root = objectKey(path).replaceFirst(RegExp(r'/+$'), '');
    final files = <RemoteFile>[];
    // Consume every page, including buckets with more than 1,000 objects.
    await for (final page in _client.listObjectsV2(
      _bucket,
      prefix: root.isEmpty ? '' : '$root/',
    )) {
      for (final object in page.objects) {
        final key = object.key;
        if (key == null) continue;
        files.add(
          RemoteFile(
            path: '/$key',
            name: key.split('/').last,
            isDir: false,
            mTime: object.lastModified,
          ),
        );
      }
      for (final prefix in page.prefixes) {
        files.add(RemoteFile(path: '/$prefix', name: prefix, isDir: true));
      }
    }
    return files;
  });
}
