class S3Config {
  const S3Config({
    this.endpoint = '',
    this.bucket = '',
    this.region = 'us-east-1',
    this.accessKey = '',
    this.secretKey = '',
    this.prefix = 'diary',
    this.pathStyle = true,
  });

  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;
  final String prefix;
  final bool pathStyle;

  static bool validEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        (uri.path.isEmpty || uri.path == '/') &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static bool validBucket(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$').hasMatch(value) &&
      !value.contains('..') &&
      !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(value);

  bool get isConfigured =>
      validEndpoint(endpoint) &&
      validBucket(bucket.trim()) &&
      region.trim().isNotEmpty &&
      accessKey.trim().isNotEmpty &&
      secretKey.isNotEmpty;

  String get targetIdentity =>
      's3|${endpoint.trim().replaceAll(RegExp(r'/+$'), '')}|${bucket.trim()}|${prefix.replaceAll(RegExp(r'^/+|/+$'), '')}';

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'accessKey': accessKey,
    'prefix': prefix,
    'pathStyle': pathStyle,
  };

  factory S3Config.fromJson(
    Map<String, dynamic> json, {
    String secretKey = '',
  }) => S3Config(
    endpoint: json['endpoint'] as String? ?? '',
    bucket: json['bucket'] as String? ?? '',
    region: json['region'] as String? ?? 'us-east-1',
    accessKey: json['accessKey'] as String? ?? '',
    secretKey: secretKey,
    prefix: json['prefix'] as String? ?? 'diary',
    pathStyle: json['pathStyle'] as bool? ?? true,
  );
}
