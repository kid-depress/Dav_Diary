import 'dart:convert';
import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/services/storage_service.dart';
import 'package:diary/ui/editor/doodle_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({this.initialEntry, super.key});

  final DiaryEntry? initialEntry;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const _moodOptions = ['😀', '🙂', '😌', '😢', '😡', '🥰'];
  static const _weatherOptions = ['☀️', '⛅', '🌧️', '⛈️', '❄️', '🌫️'];

  final _titleController = TextEditingController();
  final _moodDescController = TextEditingController();
  final _weatherDescController = TextEditingController();
  final _locationController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  late QuillController _quillController;

  String _selectedMood = _moodOptions.first;
  String _selectedWeather = _weatherOptions.first;
  DateTime _eventAt = DateTime.now();
  bool _saving = false;
  bool _locating = false;
  List<DiaryAttachment> _attachments = const [];

  bool get _isEditing => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial == null) {
      _quillController = QuillController.basic();
      return;
    }

    _titleController.text = initial.title;
    _eventAt = initial.eventAt;
    _locationController.text = initial.location;
    _attachments = List<DiaryAttachment>.from(initial.attachments);

    final moodParsed = _splitMeta(initial.mood, _moodOptions.first);
    _selectedMood = moodParsed.$1;
    _moodDescController.text = moodParsed.$2;

    final weatherParsed = _splitMeta(initial.weather, _weatherOptions.first);
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
    _titleController.dispose();
    _moodDescController.dispose();
    _weatherDescController.dispose();
    _locationController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _quillController.dispose();
    super.dispose();
  }

  (String, String) _splitMeta(String value, String fallbackIcon) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return (fallbackIcon, '');
    }
    for (final icon in [..._moodOptions, ..._weatherOptions]) {
      if (trimmed.startsWith(icon)) {
        return (icon, trimmed.substring(icon.length).trim());
      }
    }
    return (fallbackIcon, trimmed);
  }

  String _joinMeta(String icon, String desc) {
    final text = desc.trim();
    return text.isEmpty ? icon : '$icon $text';
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
      final savedPath = await const StorageService().saveImage(file.path);
      setState(() {
        _attachments = [
          ..._attachments,
          DiaryAttachment(path: savedPath),
        ];
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加图片失败：$e')));
    }
  }

  Future<void> _addDoodle() async {
    final path = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (context) => const DoodlePage()));
    if (path == null || path.isEmpty) {
      return;
    }
    setState(() {
      _attachments = [..._attachments, DiaryAttachment(path: path, isDoodle: true)];
    });
  }

  Future<void> _editCaption(int index) async {
    final current = _attachments[index];
    final controller = TextEditingController(text: current.caption);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('附件说明'),
          content: TextField(
            controller: controller,
            maxLength: 120,
            decoration: const InputDecoration(hintText: '写一段简短说明'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) {
      return;
    }
    setState(() {
      final list = List<DiaryAttachment>.from(_attachments);
      list[index] = DiaryAttachment(
        path: current.path,
        isDoodle: current.isDoodle,
        caption: result,
      );
      _attachments = list;
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw '定位服务未开启';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw '定位权限未授予';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('位置已更新')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('定位失败：$e')));
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    final appState = context.read<DiaryAppState>();
    final plainText = _quillController.document.toPlainText().trim();
    if (plainText.isEmpty && _attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入内容或添加附件')),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final existing = widget.initialEntry;
    final entry = DiaryEntry(
      id: existing?.id ?? const Uuid().v4(),
      title: _titleController.text.trim(),
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
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日记已保存')));
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final existing = widget.initialEntry;
    if (existing == null) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认删除这篇日记？'),
          content: const Text('删除后会参与同步，且无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) {
      return;
    }
    await context.read<DiaryAppState>().deleteEntry(existing.id);
    if (!mounted) {
      return;
    }
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日记已删除')));
    Navigator.of(context).pop(true);
  }

  Widget _buildMetaPicker({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
    required TextEditingController descController,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in options)
              ChoiceChip(
                label: Text(item),
                selected: selected == item,
                onSelected: (_) => onSelected(item),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: descController,
          maxLength: 40,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentItem(int index) {
    final attachment = _attachments[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(attachment.path),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                cacheWidth: 240,
                errorBuilder: (context, _, _) => Container(
                  width: 72,
                  height: 72,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.isDoodle ? '涂鸦' : '图片',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    attachment.caption.isEmpty ? '暂无说明' : attachment.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '编辑说明',
              onPressed: () => _editCaption(index),
              icon: const Icon(Icons.edit_note_outlined),
            ),
            IconButton(
              tooltip: '移除',
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() {
                  final list = List<DiaryAttachment>.from(_attachments);
                  list.removeAt(index);
                  _attachments = list;
                });
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _saving;
    final hasEntry = _isEditing;

    return Scaffold(
      appBar: AppBar(
        title: Text(hasEntry ? '编辑日记' : '新建日记'),
        actions: [
          if (hasEntry)
            IconButton(
              onPressed: isSaving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            onPressed: isSaving ? null : _save,
            child: isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            QuillSimpleToolbar(
              controller: _quillController,
              config: const QuillSimpleToolbarConfig(
                showAlignmentButtons: true,
                showHeaderStyle: true,
                showListBullets: true,
                showListNumbers: true,
                showQuote: true,
                showSmallButton: true,
                showInlineCode: false,
                showCodeBlock: false,
                showClipboardCut: false,
                showClipboardCopy: false,
                showClipboardPaste: false,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: '标题',
                        hintText: '无标题',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      constraints: const BoxConstraints(minHeight: 240),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: QuillEditor.basic(
                        controller: _quillController,
                        focusNode: _focusNode,
                        scrollController: ScrollController(),
                        config: const QuillEditorConfig(
                          placeholder: '开始写作...',
                          padding: EdgeInsets.all(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('相册'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('拍照'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _addDoodle,
                          icon: const Icon(Icons.draw_outlined),
                          label: const Text('涂鸦'),
                        ),
                      ],
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '附件（${_attachments.length}）',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      for (var i = 0; i < _attachments.length; i++)
                        _buildAttachmentItem(i),
                    ],
                    const SizedBox(height: 14),
                    _buildMetaPicker(
                      title: '心情',
                      options: _moodOptions,
                      selected: _selectedMood,
                      onSelected: (value) => setState(() => _selectedMood = value),
                      descController: _moodDescController,
                      hint: '补充心情描述',
                    ),
                    const SizedBox(height: 10),
                    _buildMetaPicker(
                      title: '天气',
                      options: _weatherOptions,
                      selected: _selectedWeather,
                      onSelected: (value) => setState(() => _selectedWeather = value),
                      descController: _weatherDescController,
                      hint: '补充天气描述',
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('记录时间'),
                      subtitle: Text(_eventAt.toString()),
                      trailing: const Icon(Icons.schedule_outlined),
                      onTap: _pickEventAt,
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: '位置',
                        hintText: '自动定位或手动编辑',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: _locating ? null : _locate,
                          icon: _locating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
