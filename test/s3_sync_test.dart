import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diary/data/credential_store.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/sync_service.dart';
import 'package:diary/data/models/s3_config.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/services/sync_remote_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'legacy configuration stays WebDAV; S3 secrets are excluded from JSON',
    () {
      final legacy = WebDavConfig.fromJson({
        'serverUrl': 'https://dav.example.com',
        'username': 'user',
        'password': 'pass',
      });
      expect(legacy.backend, SyncBackend.webdav);
      expect(legacy.isConfigured, isTrue);
      const config = WebDavConfig(
        backend: SyncBackend.s3,
        s3: S3Config(
          endpoint: 'https://s3.example.com',
          bucket: 'my-diary',
          accessKey: 'test-access',
          secretKey: 'test-secret',
        ),
      );
      expect(config.isConfigured, isTrue);
      expect(jsonEncode(config.toJson()), isNot(contains('test-secret')));
      final restored = WebDavConfig.fromJson(
        config.toJson(),
        s3SecretKey: 'test-secret',
      );
      expect(restored.isConfigured, isTrue);
      expect(restored.targetIdentity, config.targetIdentity);
      expect(restored.activeRemoteDir, 'diary');
    },
  );

  test('endpoint validation rejects paths and embedded credentials', () {
    expect(S3Config.validEndpoint('http://127.0.0.1:9000'), isTrue);
    for (final value in [
      's3.example.com',
      'https://s3.example.com/bucket',
      'https://user:secret@s3.example.com',
      'https://s3.example.com?key=secret',
    ]) {
      expect(S3Config.validEndpoint(value), isFalse);
    }
  });

  test('WebDAV and S3 credentials persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    await CredentialStore.savePassword('webdav-pass');
    await CredentialStore.savePassword('s3-secret', key: 's3_secret_key');
    expect(await CredentialStore.loadPassword(), 'webdav-pass');
    expect(
      await CredentialStore.loadPassword(key: 's3_secret_key'),
      's3-secret',
    );
    await CredentialStore.clear(key: 's3_secret_key');
    expect(await CredentialStore.loadPassword(), 'webdav-pass');
  });

  test(
    'changing destinations resets baseline and keeps pending deletions separate',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = _StoredSettings();
      const webdav = WebDavConfig(
        serverUrl: 'https://dav.example.com',
        username: 'user',
        password: 'pass',
      );
      const s3 = WebDavConfig(
        backend: SyncBackend.s3,
        s3: S3Config(
          endpoint: 'https://s3.example.com',
          bucket: 'my-diary',
          accessKey: 'key',
          secretKey: 'secret',
        ),
      );
      await settings.saveWebDavConfig(webdav);
      settings.states = {
        'old': {'lastSyncedRevision': 'old'},
      };
      settings.pending = [
        {'id': 'deleted-on-webdav'},
      ];
      await settings.saveLastSyncAt(DateTime.now());
      await settings.saveWebDavConfig(s3);
      expect(settings.states, isEmpty);
      expect(settings.pending, isEmpty);
      expect(await settings.loadLastSyncAt(), isNull);
      expect((await settings.loadWebDavConfig()).s3.secretKey, 'secret');
      settings.pending = [
        {'id': 'deleted-on-s3'},
      ];
      await settings.saveWebDavConfig(webdav);
      expect(settings.pending.single['id'], 'deleted-on-webdav');
      await settings.saveWebDavConfig(s3);
      expect(settings.pending.single['id'], 'deleted-on-s3');
    },
  );

  group('S3 HTTP transport', () {
    late HttpServer server;
    late S3RemoteStore store;
    late Map<String, List<int>> objects;
    late List<Uri> listings;
    late List<String> signatures;
    var deny = false;
    var denyManifest = false;
    var realListing = false;
    late WebDavConfig config;

    setUp(() async {
      objects = {};
      listings = [];
      signatures = [];
      deny = false;
      denyManifest = false;
      realListing = false;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        signatures.add(request.headers.value('authorization') ?? '');
        final response = request.response;
        if (deny ||
            (denyManifest && request.uri.path.endsWith('/manifest.json'))) {
          response.statusCode = 403;
          response.headers.contentType = ContentType('application', 'xml');
          response.write(
            '<Error><Code>AccessDenied</Code><Message>Denied</Message></Error>',
          );
        } else if (request.uri.queryParameters['list-type'] == '2') {
          listings.add(request.uri);
          if (realListing) {
            final prefix = request.uri.queryParameters['prefix'] ?? '';
            response.headers.contentType = ContentType('application', 'xml');
            response.write(
              '<ListBucketResult><IsTruncated>false</IsTruncated>',
            );
            for (final key in objects.keys) {
              final object = key.substring('/my-diary/'.length);
              if (object.startsWith(prefix)) {
                response.write(
                  '<Contents><Key>$object</Key>'
                  '<LastModified>2026-09-10T00:00:00.000Z</LastModified><Size>1</Size></Contents>',
                );
              }
            }
            response.write('</ListBucketResult>');
            await response.close();
            return;
          }
          final second =
              request.uri.queryParameters['continuation-token'] == 'page-two';
          response.headers.contentType = ContentType('application', 'xml');
          response.write(
            '''<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Name>my-diary</Name><Prefix>diary/entries/</Prefix><KeyCount>1</KeyCount><MaxKeys>1000</MaxKeys>
            <IsTruncated>${!second}</IsTruncated>
            ${second ? '' : '<NextContinuationToken>page-two</NextContinuationToken>'}
            <Contents><Key>diary/entries/${second ? 'second' : 'first'}.json.gz</Key>
            <LastModified>2026-09-10T00:00:00.000Z</LastModified><ETag>"test"</ETag><Size>3</Size><StorageClass>STANDARD</StorageClass></Contents>
            </ListBucketResult>''',
          );
        } else {
          final key = Uri.decodeComponent(request.uri.path);
          switch (request.method) {
            case 'PUT':
              objects[key] = await request.fold<List<int>>(
                [],
                (bytes, chunk) => bytes..addAll(chunk),
              );
              response.headers.set('etag', '"test-etag"');
            case 'GET':
              if (objects.containsKey(key)) {
                response.add(objects[key]!);
              } else {
                response.statusCode = 404;
                response.headers.contentType = ContentType(
                  'application',
                  'xml',
                );
                response.write(
                  '<Error><Code>NoSuchKey</Code><Message>Missing</Message></Error>',
                );
              }
            case 'DELETE':
              objects.remove(key);
              response.statusCode = 204;
          }
        }
        await response.close();
      });
      config = WebDavConfig(
        backend: SyncBackend.s3,
        s3: S3Config(
          endpoint: 'http://127.0.0.1:${server.port}',
          bucket: 'my-diary',
          accessKey: 'test-access',
          secretKey: 'test-secret',
        ),
      );
      store = S3RemoteStore(config);
    });
    tearDown(() async => server.close(force: true));

    test(
      'sync uploads, downloads on a second device, and propagates deletion',
      () async {
        SharedPreferences.setMockInitialValues({});
        realListing = true;
        final first = _MemoryDiary();
        final date = DateTime.utc(2026, 9, 1);
        first.entries['entry-1'] = DiaryEntry(
          id: 'entry-1',
          title: '测试日记',
          deltaJson: '[{"insert":"正文\\n"}]',
          plainText: '正文',
          createdAt: date,
          updatedAt: date,
          eventAt: date,
          mood: '',
          weather: '',
          location: '',
          attachments: [],
        );
        final settings = _MemorySettings(config);
        final service = SyncService(first, settings);
        final uploaded = await service.syncNow();
        expect(uploaded.success, isTrue, reason: uploaded.message);
        expect(uploaded.uploaded, 1);
        expect(objects.keys, contains('/my-diary/diary/manifest.json'));
        final unchanged = await service.syncNow();
        expect(unchanged.uploaded, 0);
        expect(unchanged.downloaded, 0);
        final second = _MemoryDiary();
        final secondService = SyncService(second, _MemorySettings(config));
        final downloaded = await secondService.syncNow();
        expect(downloaded.success, isTrue, reason: downloaded.message);
        expect(downloaded.downloaded, 1);
        expect(second.entries['entry-1']!.title, '测试日记');
        await service.markEntryHardDeleted('entry-1');
        first.entries.clear();
        final deletion = await service.syncNow();
        expect(deletion.success, isTrue, reason: deletion.message);
        expect((await secondService.syncNow()).success, isTrue);
        expect(second.entries, isEmpty);
      },
    );

    test(
      'unreadable manifest fails sync without overwriting remote data',
      () async {
        SharedPreferences.setMockInitialValues({});
        realListing = true;
        denyManifest = true;
        final result = await SyncService(
          _MemoryDiary(),
          _MemorySettings(config),
        ).syncNow();
        expect(result.success, isFalse);
        expect(result.message, contains('AccessDenied'));
        expect(objects, isEmpty);
      },
    );

    test(
      'signed upload, download and delete preserve Unicode keys and bytes',
      () async {
        const path = '/diary/attachments/日记 + photo.bin';
        final bytes = Uint8List.fromList([0, 1, 127, 255]);
        await store.write(path, bytes);
        expect(await store.read(path), bytes);
        expect(objects.keys.single, '/my-diary$path');
        await store.remove(path);
        expect(objects, isEmpty);
        await expectLater(
          store.read(path),
          throwsA(
            isA<RemoteStoreException>().having(
              (e) => e.isNotFound,
              'missing object',
              isTrue,
            ),
          ),
        );
        expect(signatures, everyElement(startsWith('AWS4-HMAC-SHA256 ')));
        expect(signatures.join(), isNot(contains('test-secret')));
      },
    );

    test(
      'listing follows continuation tokens and preserves sync paths',
      () async {
        final files = await store.readDir('/diary/entries');
        expect(files.map((f) => f.path), [
          '/diary/entries/first.json.gz',
          '/diary/entries/second.json.gz',
        ]);
        expect(listings.length, 2);
        expect(listings.first.queryParameters['prefix'], 'diary/entries/');
        expect(files.first.mTime, DateTime.utc(2026, 9, 10));
      },
    );

    test(
      'connection check is prefix-scoped and permissions are not missing data',
      () async {
        await store.ping();
        expect(listings.single.queryParameters['prefix'], 'diary/');
        expect(listings.single.queryParameters['max-keys'], '1');
        deny = true;
        await expectLater(
          store.read('/diary/manifest.json'),
          throwsA(
            isA<RemoteStoreException>()
                .having((e) => e.isNotFound, 'not missing', isFalse)
                .having((e) => e.code, 'error code', 'AccessDenied'),
          ),
        );
      },
    );
  });
}

class _MemoryDiary implements DiaryRepository {
  final entries = <String, DiaryEntry>{};
  @override
  Future<List<DiaryEntry>> listAll() async => entries.values.toList();
  @override
  Future<List<DiaryEntry>> listUpdatedAfter(DateTime time) async =>
      entries.values.where((e) => e.updatedAt.isAfter(time)).toList();
  @override
  Future<Map<String, DateTime>> listSyncHeads() async =>
      entries.map((id, entry) => MapEntry(id, entry.updatedAt));
  @override
  Future<DiaryEntry?> getById(String id) async => entries[id];
  @override
  Future<void> upsert(DiaryEntry entry) async {
    entries[entry.id] = entry;
  }

  @override
  Future<void> deleteForever(String id) async {
    entries.remove(id);
  }

  @override
  Future<bool> updateSyncedAttachments(
    DiaryEntry source,
    List<DiaryAttachment> attachments,
  ) async {
    entries[source.id] = source.copyWith(attachments: attachments);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemorySettings extends SettingsRepository {
  _MemorySettings(this.config);
  final WebDavConfig config;
  Map<String, dynamic> states = {};
  List<Map<String, dynamic>> pending = [];
  DateTime? lastSync;
  @override
  Future<WebDavConfig> loadWebDavConfig() async => config;
  @override
  Future<Map<String, dynamic>> loadEntrySyncStates() async => Map.of(states);
  @override
  Future<void> saveEntrySyncStates(Map<String, dynamic> value) async {
    states = value;
  }

  @override
  Future<List<Map<String, dynamic>>> loadPendingHardDeleteRecords() async =>
      pending;
  @override
  Future<void> savePendingHardDeleteRecords(
    List<Map<String, dynamic>> value,
  ) async {
    pending = value;
  }

  @override
  Future<DateTime?> loadLastSyncAt() async => lastSync;
  @override
  Future<void> saveLastSyncAt(DateTime value) async {
    lastSync = value;
  }
}

class _StoredSettings extends SettingsRepository {
  Map<String, dynamic> states = {};
  List<Map<String, dynamic>> pending = [];
  @override
  Future<Map<String, dynamic>> loadEntrySyncStates() async => states;
  @override
  Future<void> saveEntrySyncStates(Map<String, dynamic> value) async {
    states = value;
  }

  @override
  Future<List<Map<String, dynamic>>> loadPendingHardDeleteRecords() async =>
      pending;
  @override
  Future<void> savePendingHardDeleteRecords(
    List<Map<String, dynamic>> value,
  ) async {
    pending = value;
  }
}
