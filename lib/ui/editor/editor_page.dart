import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/services/storage_service.dart';
import 'package:diary/ui/editor/doodle_page.dart';
import 'package:diary/ui/motion/motion_dialog.dart';
import 'package:diary/ui/motion/motion_route.dart';
import 'package:diary/ui/motion/motion_spec.dart';
import 'package:diary/ui/motion/pressable_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({this.initialEntry, super.key});

  final DiaryEntry? initialEntry;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const _moodOptions = ['🙂', '😀', '🥰', '🤩', '😐', '☹️'];
  static const _weatherOptions = ['☀️', '🌤️', '☁️', '🌧️', '❄️', '🌫️'];
  static const _moodIconMap = <String, IconData>{
    '🙂': LucideIcons.smile,
    '😀': LucideIcons.laugh,
    '🥰': LucideIcons.heart,
    '🤩': LucideIcons.sparkles,
    '😐': LucideIcons.meh,
    '☹️': LucideIcons.frown,
  };
  static const _weatherIconMap = <String, IconData>{
    '☀️': LucideIcons.sun,
    '🌤️': LucideIcons.cloudSun,
    '☁️': LucideIcons.cloudy,
    '🌧️': LucideIcons.cloudRain,
    '❄️': LucideIcons.cloudSnow,
    '🌫️': LucideIcons.cloudFog,
  };

  final _moodDescController = TextEditingController();
  final _weatherDescController = TextEditingController();
  final _locationController = TextEditingController();
  final _editorScrollController = ScrollController();
  final _editorFocusNode = FocusNode();

  late QuillController _quillController;

  String _selectedMood = '';
  String _selectedWeather = '';
  DateTime _eventAt = DateTime.now();
  bool _saving = false;
  bool _locating = false;
  List<DiaryAttachment> _attachments = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial == null) {
      _quillController = QuillController.basic();
      return;
    }

    _eventAt = initial.eventAt;
    _locationController.text = initial.location;
    _attachments = List<DiaryAttachment>.from(initial.attachments);

    final moodParsed = _splitMeta(initial.mood, _moodOptions);
    _selectedMood = moodParsed.$1;
    _moodDescController.text = moodParsed.$2;

    final weatherParsed = _splitMeta(initial.weather, _weatherOptions);
    _selectedWeather = weatherParsed.$1;
    _weatherDescController.text = weatherParsed.$2;

    try {
      final raw = jsonDecode(initial.deltaJson) as List<dynamic>;
      _quillController = QuillController(
        document: Document.fromJson(raw),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      _quillController = QuillController.basic();
      _quillController.document.insert(0, initial.plainText);
    }
  }

  @override
  void dispose() {
    _moodDescController.dispose();
    _weatherDescController.dispose();
    _locationController.dispose();
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
    _quillController.dispose();
    super.dispose();
  }

  (String, String) _splitMeta(String value, List<String> options) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return ('', '');
    }
    for (final icon in options) {
      if (trimmed.startsWith(icon)) {
        return (icon, trimmed.substring(icon.length).trim());
      }
    }
    return ('', trimmed);
  }

  IconData _moodIcon(String value) => _moodIconMap[value] ?? LucideIcons.smile;

  IconData _weatherIcon(String value) =>
      _weatherIconMap[value] ?? LucideIcons.cloud;

  String _joinMeta(String icon, String desc) {
    final symbol = icon.trim();
    final text = desc.trim();
    if (symbol.isEmpty && text.isEmpty) {
      return '';
    }
    if (symbol.isEmpty) {
      return text;
    }
    if (text.isEmpty) {
      return symbol;
    }
    return '$symbol $text';
  }

  Future<void> _pickEventAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _eventAt,
      firstDate: DateTime(2010, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eventAt),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _eventAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (file == null) {
        return;
      }
      final saved = await const StorageService().saveImageAttachment(file.path);
      setState(() {
        _attachments = [
          ..._attachments,
          DiaryAttachment(
            path: saved.path,
            hash: saved.hash,
            thumbnailPath: saved.thumbnailPath,
          ),
        ];
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, zh: '添加图片失败: $e', en: 'Failed to add image: $e'),
          ),
        ),
      );
    }
  }

  Future<void> _addDoodle() async {
    final attachment = await Navigator.of(
      context,
    ).push<DiaryAttachment>(buildPageTransitionRoute(const DoodlePage()));
    if (attachment == null) {
      return;
    }
    setState(() {
      _attachments = [..._attachments, attachment];
    });
  }

  Future<void> _editCaption(int index) async {
    final current = _attachments[index];
    final controller = TextEditingController(text: current.caption);
    final result = await showMotionDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '附件说明', en: 'Attachment Caption')),
        content: TextField(
          controller: controller,
          maxLength: 120,
          decoration: InputDecoration(
            hintText: tr(context, zh: '写一句简短说明', en: 'Add a short note'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(tr(context, zh: '保存', en: 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) {
      return;
    }
    setState(() {
      final list = List<DiaryAttachment>.from(_attachments);
      list[index] = current.copyWith(caption: result);
      _attachments = list;
    });
  }

  Future<void> _openAttachmentActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr(context, zh: '从相册添加', en: 'Add from gallery')),
              onTap: () async {
                Navigator.of(context).pop();
                await _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr(context, zh: '拍照添加', en: 'Take a photo')),
              onTap: () async {
                Navigator.of(context).pop();
                await _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: Text(tr(context, zh: '新建涂鸦', en: 'New doodle')),
              onTap: () async {
                Navigator.of(context).pop();
                await _addDoodle();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeAttachment(int index) async {
    final confirm = await showMotionDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '移除附件？', en: 'Remove attachment?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(context, zh: '移除', en: 'Remove')),
          ),
        ],
      ),
    );
    if (confirm != true) {
      return;
    }
    setState(() {
      final list = List<DiaryAttachment>.from(_attachments);
      list.removeAt(index);
      _attachments = list;
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final serviceDisabledText = tr(
      context,
      zh: '定位服务未开启',
      en: 'Location service is disabled',
    );
    final permissionDeniedText = tr(
      context,
      zh: '未授予定位权限',
      en: 'Location permission denied',
    );
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw serviceDisabledText;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw permissionDeniedText;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      final place = placemarks.isEmpty ? null : placemarks.first;
      final formatted = place == null
          ? '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'
          : [
                  place.country,
                  place.administrativeArea,
                  place.locality,
                  place.subLocality,
                  place.street,
                ]
                .whereType<String>()
                .map((part) => part.trim())
                .where((part) => part.isNotEmpty)
                .join(' ');
      _locationController.text = formatted;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, zh: '位置已更新', en: 'Location updated')),
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, zh: '定位失败', en: 'Location failed')}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  bool _isAttributeEnabled(Attribute attribute) {
    final attr = _quillController.getSelectionStyle().attributes[attribute.key];
    return attr?.value == attribute.value;
  }

  void _toggleAttribute(Attribute attribute) {
    unawaited(HapticFeedback.lightImpact());
    final enabled = _isAttributeEnabled(attribute);
    _quillController.formatSelection(
      enabled ? Attribute.clone(attribute, null) : attribute,
    );
    setState(() {});
  }

  void _setHeader(Attribute<int?> header) {
    unawaited(HapticFeedback.lightImpact());
    _quillController.formatSelection(header);
    setState(() {});
  }

  void _setAlign(Attribute<String?> alignment) {
    unawaited(HapticFeedback.lightImpact());
    _quillController.formatSelection(alignment);
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    final appState = context.read<DiaryAppState>();
    final plainText = _quillController.document.toPlainText().trim();
    if (plainText.isEmpty && _attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, zh: '请先输入内容或添加附件', en: 'Add text or attachment first'),
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.initialEntry;
    final entry = DiaryEntry(
      id: existing?.id ?? const Uuid().v4(),
      title: '',
      deltaJson: jsonEncode(_quillController.document.toDelta().toJson()),
      plainText: plainText,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      eventAt: _eventAt,
      mood: _joinMeta(_selectedMood, _moodDescController.text),
      weather: _joinMeta(_selectedWeather, _weatherDescController.text),
      location: _locationController.text.trim(),
      attachments: _attachments,
      isDeleted: false,
    );

    await appState.saveEntry(entry);
    if (!mounted) {
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '日记已保存', en: 'Saved')),
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _openMoodSheet() async {
    var selectedMood = _selectedMood;
    final descController = TextEditingController(
      text: _moodDescController.text,
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, zh: '心情', en: 'Mood'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mood in _moodOptions)
                      ChoiceChip(
                        label: Icon(_moodIcon(mood), size: 18),
                        selected: selectedMood == mood,
                        onSelected: (_) =>
                            modalSetState(() => selectedMood = mood),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  maxLength: 40,
                  decoration: InputDecoration(
                    hintText: tr(context, zh: '补充心情描述', en: 'Mood notes'),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(tr(context, zh: '取消', en: 'Cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(tr(context, zh: '确定', en: 'Done')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _selectedMood = selectedMood;
        _moodDescController.text = descController.text.trim();
      });
    }
    descController.dispose();
  }

  Future<void> _openWeatherSheet() async {
    var selectedWeather = _selectedWeather;
    final descController = TextEditingController(
      text: _weatherDescController.text,
    );
    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, zh: '天气', en: 'Weather'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final weather in _weatherOptions)
                      ChoiceChip(
                        label: Icon(_weatherIcon(weather), size: 18),
                        selected: selectedWeather == weather,
                        onSelected: (_) =>
                            modalSetState(() => selectedWeather = weather),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descController,
                  maxLength: 40,
                  decoration: InputDecoration(
                    hintText: tr(context, zh: '补充天气描述', en: 'Weather notes'),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(tr(context, zh: '取消', en: 'Cancel')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(tr(context, zh: '确定', en: 'Done')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _selectedWeather = selectedWeather;
        _weatherDescController.text = descController.text.trim();
      });
    }
    descController.dispose();
  }

  Widget _formatButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active ? Theme.of(context).colorScheme.primary : null;
    return PressableScale(
      child: IconButton(
        tooltip: tooltip,
        onPressed: () {
          unawaited(HapticFeedback.lightImpact());
          onTap();
        },
        icon: Icon(icon, color: color),
      ),
    );
  }

  Widget _buildStatusBar() {
    final dateText = DateFormat('MM-dd HH:mm').format(_eventAt);
    final locationText = _locationController.text.trim().isEmpty
        ? tr(context, zh: '设置位置', en: 'Set location')
        : _locationController.text.trim();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                _selectedMood.isEmpty
                    ? LucideIcons.smile
                    : _moodIcon(_selectedMood),
                size: 18,
              ),
              label: Text(
                _moodDescController.text.trim().isEmpty
                    ? tr(context, zh: '心情', en: 'Mood')
                    : _moodDescController.text.trim(),
              ),
              showCheckmark: false,
              selected: true,
              onSelected: (_) => _openMoodSheet(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: Icon(
                _selectedWeather.isEmpty
                    ? LucideIcons.cloudSun
                    : _weatherIcon(_selectedWeather),
                size: 18,
              ),
              label: Text(
                _weatherDescController.text.trim().isEmpty
                    ? tr(context, zh: '天气', en: 'Weather')
                    : _weatherDescController.text.trim(),
              ),
              showCheckmark: false,
              selected: true,
              onSelected: (_) => _openWeatherSheet(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: const Icon(Icons.schedule_outlined, size: 18),
              label: Text(dateText),
              showCheckmark: false,
              selected: true,
              onSelected: (_) => _pickEventAt(),
            ),
          ),
          FilterChip(
            avatar: _locating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_outlined, size: 18),
            label: Text(locationText, overflow: TextOverflow.ellipsis),
            showCheckmark: false,
            selected: true,
            onSelected: (_) => _locate(),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsStrip() {
    final colors = Theme.of(context).colorScheme;
    final hasItems = _attachments.isNotEmpty;
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hasItems ? _attachments.length + 1 : 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return InkWell(
              onTap: _openAttachmentActions,
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                width: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: colors.surfaceContainerHigh,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_outlined),
                    const SizedBox(height: 4),
                    Text(tr(context, zh: '附件', en: 'Attach')),
                  ],
                ),
              ),
            );
          }
          final attachment = _attachments[index - 1];
          return _AttachmentThumb(
            attachment: attachment,
            onTap: () => _editCaption(index - 1),
            onRemove: () => _removeAttachment(index - 1),
          );
        },
      ),
    );
  }

  Widget _buildFloatingToolbar(double keyboardInset) {
    final bottomInset = keyboardInset > 0 ? 8.0 : 12.0;
    final colors = Theme.of(context).colorScheme;
    return AnimatedPositioned(
      duration: MotionSpec.popupDuration,
      curve: MotionSpec.popupCurve,
      left: 10,
      right: 10,
      bottom: bottomInset,
      child: SafeArea(
        top: false,
        bottom: keyboardInset <= 0,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              elevation: 0,
              color: colors.surface.withValues(alpha: 0.88),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    _formatButton(
                      icon: Icons.format_bold,
                      tooltip: tr(context, zh: '加粗', en: 'Bold'),
                      onTap: () => _toggleAttribute(Attribute.bold),
                      active: _isAttributeEnabled(Attribute.bold),
                    ),
                    _formatButton(
                      icon: Icons.format_italic,
                      tooltip: tr(context, zh: '斜体', en: 'Italic'),
                      onTap: () => _toggleAttribute(Attribute.italic),
                      active: _isAttributeEnabled(Attribute.italic),
                    ),
                    _formatButton(
                      icon: Icons.format_underline,
                      tooltip: tr(context, zh: '下划线', en: 'Underline'),
                      onTap: () => _toggleAttribute(Attribute.underline),
                      active: _isAttributeEnabled(Attribute.underline),
                    ),
                    _formatButton(
                      icon: Icons.strikethrough_s,
                      tooltip: tr(context, zh: '删除线', en: 'Strike'),
                      onTap: () => _toggleAttribute(Attribute.strikeThrough),
                      active: _isAttributeEnabled(Attribute.strikeThrough),
                    ),
                    _formatButton(
                      icon: Icons.format_list_bulleted,
                      tooltip: tr(context, zh: '无序列表', en: 'Bullet List'),
                      onTap: () => _toggleAttribute(Attribute.ul),
                      active: _isAttributeEnabled(Attribute.ul),
                    ),
                    _formatButton(
                      icon: Icons.format_list_numbered,
                      tooltip: tr(context, zh: '有序列表', en: 'Numbered List'),
                      onTap: () => _toggleAttribute(Attribute.ol),
                      active: _isAttributeEnabled(Attribute.ol),
                    ),
                    _formatButton(
                      icon: Icons.format_quote,
                      tooltip: tr(context, zh: '引用', en: 'Quote'),
                      onTap: () => _toggleAttribute(Attribute.blockQuote),
                      active: _isAttributeEnabled(Attribute.blockQuote),
                    ),
                    PopupMenuButton<String>(
                      tooltip: tr(context, zh: '更多格式', en: 'More'),
                      onSelected: (value) {
                        switch (value) {
                          case 'h1':
                            _setHeader(Attribute.h1);
                            break;
                          case 'h2':
                            _setHeader(Attribute.h2);
                            break;
                          case 'h3':
                            _setHeader(Attribute.h3);
                            break;
                          case 'p':
                            _quillController.formatSelection(
                              Attribute.clone(Attribute.h1, null),
                            );
                            setState(() {});
                            break;
                          case 'left':
                            _setAlign(Attribute.leftAlignment);
                            break;
                          case 'center':
                            _setAlign(Attribute.centerAlignment);
                            break;
                          case 'right':
                            _setAlign(Attribute.rightAlignment);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'h1',
                          child: Text(tr(context, zh: '标题 1', en: 'Heading 1')),
                        ),
                        PopupMenuItem(
                          value: 'h2',
                          child: Text(tr(context, zh: '标题 2', en: 'Heading 2')),
                        ),
                        PopupMenuItem(
                          value: 'h3',
                          child: Text(tr(context, zh: '标题 3', en: 'Heading 3')),
                        ),
                        PopupMenuItem(
                          value: 'p',
                          child: Text(tr(context, zh: '正文', en: 'Body')),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'left',
                          child: Text(tr(context, zh: '左对齐', en: 'Align Left')),
                        ),
                        PopupMenuItem(
                          value: 'center',
                          child: Text(
                            tr(context, zh: '居中', en: 'Align Center'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'right',
                          child: Text(
                            tr(context, zh: '右对齐', en: 'Align Right'),
                          ),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.tune),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _saving;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: '编辑日记', en: 'Edit Entry')),
        actions: [
          TextButton(
            onPressed: isSaving ? null : _save,
            child: isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr(context, zh: '保存', en: 'Save')),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusBar(),
                      const SizedBox(height: 10),
                      _buildAttachmentsStrip(),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                    child: Material(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      child: QuillEditor.basic(
                        controller: _quillController,
                        focusNode: _editorFocusNode,
                        scrollController: _editorScrollController,
                        config: QuillEditorConfig(
                          placeholder: tr(
                            context,
                            zh: '开始写下这一刻...',
                            en: 'Start writing this moment...',
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 104,
              child: IgnorePointer(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        colors.surface.withValues(alpha: 0.95),
                        colors.surface.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildFloatingToolbar(keyboardInset),
          ],
        ),
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.attachment,
    required this.onTap,
    required this.onRemove,
  });

  final DiaryAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imagePath = attachment.thumbnailPath.isNotEmpty
        ? attachment.thumbnailPath
        : attachment.path;

    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: colors.surfaceContainerHigh,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imagePath.isNotEmpty)
                    Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                      cacheWidth: 400,
                      errorBuilder: (context, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    )
                  else
                    const Icon(Icons.image_not_supported_outlined),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.48),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          attachment.caption.trim().isEmpty
                              ? tr(context, zh: '点击添加说明', en: 'Add caption')
                              : attachment.caption.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: IconButton.filledTonal(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 14),
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}
