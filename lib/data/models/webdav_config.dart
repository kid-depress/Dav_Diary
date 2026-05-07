enum ConflictStrategy { lastWriteWins, keepBoth }

class WebDavConfig {
  const WebDavConfig({
    this.serverUrl = '',
    this.username = '',
    this.password = '',
    this.remoteDir = '/diary',
    this.conflictStrategy = ConflictStrategy.lastWriteWins,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remoteDir;
  final ConflictStrategy conflictStrategy;

  bool get isConfigured =>
      serverUrl.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      password.trim().isNotEmpty;

  WebDavConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? remoteDir,
    ConflictStrategy? conflictStrategy,
  }) {
    return WebDavConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDir: remoteDir ?? this.remoteDir,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverUrl': serverUrl,
      'username': username,
      'remoteDir': remoteDir,
      'conflictStrategy': conflictStrategy.name,
    };
  }

  static WebDavConfig fromJson(
    Map<String, dynamic> json, {
    String password = '',
  }) {
    final strategyValue =
        (json['conflictStrategy'] ?? ConflictStrategy.lastWriteWins.name)
            as String;
    return WebDavConfig(
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
