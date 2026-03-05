import 'dart:convert';

class DiaryAttachment {
  const DiaryAttachment({
    required this.path,
    this.caption = '',
    this.isDoodle = false,
  });

  final String path;
  final String caption;
  final bool isDoodle;

  Map<String, dynamic> toJson() => {
    'path': path,
    'caption': caption,
    'isDoodle': isDoodle,
  };

  static DiaryAttachment fromJson(Map<String, dynamic> json) {
    return DiaryAttachment(
      path: (json['path'] ?? '') as String,
      caption: (json['caption'] ?? '') as String,
      isDoodle: (json['isDoodle'] ?? false) as bool,
    );
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
      if (!attachment.isDoodle) {
        return attachment.path;
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
