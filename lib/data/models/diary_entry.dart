import 'dart:convert';
import 'package:path/path.dart' as p;

enum AttachmentType { image, gif, video, doodle, file }

class DiaryAttachment {
  const DiaryAttachment({
    required this.path,
    this.caption = '',
    this.type = AttachmentType.image,
    this.hash = '',
    this.remotePath = '',
    this.thumbnailPath = '',
    this.thumbnailRemotePath = '',
  });

  final String path;
  final String caption;
  final AttachmentType type;
  final String hash;
  final String remotePath;
  final String thumbnailPath;
  final String thumbnailRemotePath;

  bool get isDoodle => type == AttachmentType.doodle;
  bool get isVisualImage =>
      type == AttachmentType.image ||
      type == AttachmentType.gif ||
      type == AttachmentType.doodle;
  bool get isVideo => type == AttachmentType.video;

  DiaryAttachment copyWith({
    String? path,
    String? caption,
    AttachmentType? type,
    String? hash,
    String? remotePath,
    String? thumbnailPath,
    String? thumbnailRemotePath,
  }) {
    return DiaryAttachment(
      path: path ?? this.path,
      caption: caption ?? this.caption,
      type: type ?? this.type,
      hash: hash ?? this.hash,
      remotePath: remotePath ?? this.remotePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      thumbnailRemotePath: thumbnailRemotePath ?? this.thumbnailRemotePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'caption': caption,
    'type': type.name,
    if (hash.isNotEmpty) 'hash': hash,
    if (remotePath.isNotEmpty) 'remotePath': remotePath,
    if (thumbnailPath.isNotEmpty) 'thumbnailPath': thumbnailPath,
    if (thumbnailRemotePath.isNotEmpty)
      'thumbnailRemotePath': thumbnailRemotePath,
  };

  static DiaryAttachment fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '') as String;
    final isLegacyDoodle = (json['isDoodle'] ?? false) as bool;
    final attachmentPath = (json['path'] ?? '') as String;

    AttachmentType parsedType;
    if (isLegacyDoodle) {
      parsedType = AttachmentType.doodle;
    } else {
      parsedType = AttachmentType.values.firstWhere(
        (item) => item.name == rawType,
        orElse: () => inferTypeFromPath(attachmentPath),
      );
    }

    return DiaryAttachment(
      path: attachmentPath,
      caption: (json['caption'] ?? '') as String,
      type: parsedType,
      hash: (json['hash'] ?? '') as String,
      remotePath: (json['remotePath'] ?? '') as String,
      thumbnailPath: (json['thumbnailPath'] ?? '') as String,
      thumbnailRemotePath: (json['thumbnailRemotePath'] ?? '') as String,
    );
  }

  static AttachmentType inferTypeFromPath(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.gif') {
      return AttachmentType.gif;
    }
    if (const [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.bmp',
      '.heic',
    ].contains(ext)) {
      return AttachmentType.image;
    }
    if (const [
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.webm',
      '.3gp',
      '.m4v',
    ].contains(ext)) {
      return AttachmentType.video;
    }
    return AttachmentType.file;
  }
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.title,
    required this.deltaJson,
    required this.plainText,
    required this.createdAt,
    required this.updatedAt,
    required this.eventAt,
    required this.mood,
    required this.weather,
    required this.location,
    required this.attachments,
    this.isDeleted = false,
  });

  final String id;
  final String title;
  final String deltaJson;
  final String plainText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime eventAt;
  final String mood;
  final String weather;
  final String location;
  final List<DiaryAttachment> attachments;
  final bool isDeleted;

  DiaryEntry copyWith({
    String? id,
    String? title,
    String? deltaJson,
    String? plainText,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? eventAt,
    String? mood,
    String? weather,
    String? location,
    List<DiaryAttachment>? attachments,
    bool? isDeleted,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      deltaJson: deltaJson ?? this.deltaJson,
      plainText: plainText ?? this.plainText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      eventAt: eventAt ?? this.eventAt,
      mood: mood ?? this.mood,
      weather: weather ?? this.weather,
      location: location ?? this.location,
      attachments: attachments ?? this.attachments,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  String get summary {
    final text = plainText.replaceAll('\n', ' ').trim();
    if (text.length <= 90) {
      return text;
    }
    return '${text.substring(0, 90)}...';
  }

  String? get firstImagePath {
    for (final attachment in attachments) {
      if (attachment.isVisualImage) {
        if (attachment.path.isNotEmpty) {
          return attachment.path;
        }
        if (attachment.thumbnailPath.isNotEmpty) {
          return attachment.thumbnailPath;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'title': title,
      'delta_json': deltaJson,
      'plain_text': plainText,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'event_at': eventAt.millisecondsSinceEpoch,
      'mood': mood,
      'weather': weather,
      'location': location,
      'attachments_json': jsonEncode(
        attachments.map((e) => e.toJson()).toList(),
      ),
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'id': id,
      'title': title,
      'deltaJson': deltaJson,
      'plainText': plainText,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'eventAt': eventAt.toIso8601String(),
      'mood': mood,
      'weather': weather,
      'location': location,
      'attachments': attachments.map((e) => e.toJson()).toList(),
      'isDeleted': isDeleted,
    };
  }

  static DiaryEntry fromDbMap(Map<String, dynamic> map) {
    final list =
        (jsonDecode((map['attachments_json'] ?? '[]') as String)
                as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(DiaryAttachment.fromJson)
            .toList();

    return DiaryEntry(
      id: (map['id'] ?? '') as String,
      title: (map['title'] ?? '') as String,
      deltaJson: (map['delta_json'] ?? '') as String,
      plainText: (map['plain_text'] ?? '') as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] ?? 0) as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] ?? 0) as int,
      ),
      eventAt: DateTime.fromMillisecondsSinceEpoch(
        (map['event_at'] ?? 0) as int,
      ),
      mood: (map['mood'] ?? '') as String,
      weather: (map['weather'] ?? '') as String,
      location: (map['location'] ?? '') as String,
      attachments: list,
      isDeleted: (map['is_deleted'] ?? 0) == 1,
    );
  }

  static DiaryEntry fromSyncJson(Map<String, dynamic> json) {
    final attachmentsRaw =
        (json['attachments'] ?? <dynamic>[]) as List<dynamic>;
    return DiaryEntry(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      deltaJson: (json['deltaJson'] ?? '') as String,
      plainText: (json['plainText'] ?? '') as String,
      createdAt: DateTime.parse(
        (json['createdAt'] ?? DateTime.now().toIso8601String()) as String,
      ),
      updatedAt: DateTime.parse(
        (json['updatedAt'] ?? DateTime.now().toIso8601String()) as String,
      ),
      eventAt: DateTime.parse(
        (json['eventAt'] ?? DateTime.now().toIso8601String()) as String,
      ),
      mood: (json['mood'] ?? '') as String,
      weather: (json['weather'] ?? '') as String,
      location: (json['location'] ?? '') as String,
      attachments: attachmentsRaw
          .whereType<Map<String, dynamic>>()
          .map(DiaryAttachment.fromJson)
          .toList(),
      isDeleted: (json['isDeleted'] ?? false) as bool,
    );
  }
}
