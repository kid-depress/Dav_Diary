import 's3_config.dart';

enum SyncBackend { webdav, s3 }

enum ConflictStrategy { lastWriteWins, keepBoth }

class WebDavConfig {
  const WebDavConfig({
    this.backend = SyncBackend.webdav,
    this.s3 = const S3Config(),
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDir = '/diary',
    this.conflictStrategy = ConflictStrategy.lastWriteWins,
  });

  final SyncBackend backend;
  final S3Config s3;
  final String serverUrl;
  final String username;
  final String password;
  final String remoteDir;
  final ConflictStrategy conflictStrategy;

  String get activeRemoteDir =>
      backend == SyncBackend.s3 ? s3.prefix : remoteDir;

  String get targetIdentity => backend == SyncBackend.s3
      ? s3.targetIdentity
      : "webdav|${serverUrl.trim().replaceAll(RegExp(r'/+$'), '')}|${username.trim()}|${remoteDir.replaceAll(RegExp(r'^/+|/+$'), '')}";

  bool get isConfigured => backend == SyncBackend.s3
      ? s3.isConfigured
      : serverUrl.trim().isNotEmpty &&
            username.trim().isNotEmpty &&
            password.trim().isNotEmpty;

  WebDavConfig copyWith({
    SyncBackend? backend,
    S3Config? s3,
    String? serverUrl,
    String? username,
    String? password,
    String? remoteDir,
    ConflictStrategy? conflictStrategy,
  }) {
    return WebDavConfig(
      backend: backend ?? this.backend,
      s3: s3 ?? this.s3,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDir: remoteDir ?? this.remoteDir,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'backend': backend.name,
      's3': s3.toJson(),
      'serverUrl': serverUrl,
      'username': username,
      'remoteDir': remoteDir,
      'conflictStrategy': conflictStrategy.name,
    };
  }

  static WebDavConfig fromJson(
    Map<String, dynamic> json, {
    String password = '',
    String s3SecretKey = '',
  }) {
    final strategyValue =
        (json['conflictStrategy'] ?? ConflictStrategy.lastWriteWins.name)
            as String;
    return WebDavConfig(
      backend: json['backend'] == 's3' ? SyncBackend.s3 : SyncBackend.webdav,
      s3: S3Config.fromJson(
        (json['s3'] as Map<String, dynamic>?) ?? {},
        secretKey: s3SecretKey,
      ),
      serverUrl: (json['serverUrl'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      password: password.isNotEmpty
          ? password
          : (json['password'] ?? '') as String,
      remoteDir: (json['remoteDir'] ?? '/diary') as String,
      conflictStrategy: ConflictStrategy.values.firstWhere(
        (item) => item.name == strategyValue,
        orElse: () => ConflictStrategy.lastWriteWins,
      ),
    );
  }
}
