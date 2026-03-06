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
import 'package:intl/intl.dart';
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

  final _moodDescController = TextEditingController();
  final _weatherDescController = TextEditingController();
  final _locationController = TextEditingController();
  final _editorScrollController = ScrollController();
  final _editorFocusNode = FocusNode();

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
    _moodDescController.dispose();
    _weatherDescController.dispose();
    _locationController.dispose();
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
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

  Future<void> _pickEventAt({StateSetter? modalSetState}) async {
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
    modalSetState?.call(() {});
  }

  Future<void> _pickImage(ImageSource source, {StateSetter? modalSetState}) async {
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
        _attachments = [..._attachments, DiaryAttachment(path: savedPath)];
      });
      modalSetState?.call(() {});
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加图片失败：$e')));
    }
  }

  Future<void> _addDoodle({StateSetter? modalSetState}) async {
    final path = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (context) => const DoodlePage()));
    if (path == null || path.isEmpty) {
      return;
    }
    setState(() {
      _attachments = [..._attachments, DiaryAttachment(path: path, type: AttachmentType.doodle)];
    });
    modalSetState?.call(() {});
  }

  Future<void> _editCaption(int index, {StateSetter? modalSetState}) async {
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
      list[index] = current.copyWith(caption: result);
      _attachments = list;
    });
    modalSetState?.call(() {});
  }

  Future<void> _locate({StateSetter? modalSetState}) async {
    setState(() => _locating = true);
    modalSetState?.call(() {});
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
        modalSetState?.call(() {});
      }
    }
  }

  bool _isAttributeEnabled(Attribute attribute) {
    final attr = _quillController.getSelectionStyle().attributes[attribute.key];
    return attr?.value == attribute.value;
  }

  void _toggleAttribute(Attribute attribute) {
    final enabled = _isAttributeEnabled(attribute);
    _quillController.formatSelection(
      enabled ? Attribute.clone(attribute, null) : attribute,
    );
    setState(() {});
  }

  void _setHeader(Attribute<int?> header) {
    _quillController.formatSelection(header);
    setState(() {});
  }

  void _setAlign(Attribute<String?> alignment) {
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
        const SnackBar(content: Text('请先输入内容或添加附件')),
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

  Widget _formatButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active ? Theme.of(context).colorScheme.primary : null;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: color),
    );
  }

  Widget _buildAttachmentItem(int index, {StateSetter? modalSetState}) {
    final attachment = _attachments[index];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(attachment.path),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          cacheWidth: 180,
          errorBuilder: (context, _, _) => Container(
            width: 52,
            height: 52,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
      title: Text(attachment.isDoodle ? '涂鸦' : '图片'),
      subtitle: Text(
        attachment.caption.isEmpty ? '暂无说明' : attachment.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            onPressed: () => _editCaption(index, modalSetState: modalSetState),
            icon: const Icon(Icons.edit_note_outlined),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                final list = List<DiaryAttachment>.from(_attachments);
                list.removeAt(index);
                _attachments = list;
              });
              modalSetState?.call(() {});
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Future<void> _openMoodSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('心情', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final mood in _moodOptions)
                          ChoiceChip(
                            label: Text(mood),
                            selected: _selectedMood == mood,
                            onSelected: (_) {
                              setState(() => _selectedMood = mood);
                              modalSetState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _moodDescController,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '补充心情描述',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openWeatherSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('天气', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final weather in _weatherOptions)
                          ChoiceChip(
                            label: Text(weather),
                            selected: _selectedWeather == weather,
                            onSelected: (_) {
                              setState(() => _selectedWeather = weather);
                              modalSetState(() {});
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _weatherDescController,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '补充天气描述',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openLocationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('位置', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        labelText: '位置',
                        hintText: '自动定位或手动编辑',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: _locating
                              ? null
                              : () => _locate(modalSetState: modalSetState),
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
            );
          },
        );
      },
    );
  }

  Future<void> _openAttachmentSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('附件', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _pickImage(ImageSource.gallery, modalSetState: modalSetState),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('相册'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _pickImage(ImageSource.camera, modalSetState: modalSetState),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('拍照'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _addDoodle(modalSetState: modalSetState),
                            icon: const Icon(Icons.draw_outlined),
                            label: const Text('涂鸦'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_attachments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('暂无附件'),
                        )
                      else
                        for (var i = 0; i < _attachments.length; i++)
                          _buildAttachmentItem(i, modalSetState: modalSetState),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openMetadataMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined),
                title: const Text('心情'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openMoodSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('天气'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openWeatherSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('时间'),
                subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(_eventAt)),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _pickEventAt();
                },
              ),
              ListTile(
                leading: const Icon(Icons.my_location_outlined),
                title: const Text('位置'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openLocationSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('附件'),
                subtitle: Text('共 ${_attachments.length} 个'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openAttachmentSheet();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _saving;
    final hasEntry = _isEditing;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = keyboardInset > 0;

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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: QuillEditor.basic(
            controller: _quillController,
            focusNode: _editorFocusNode,
            scrollController: _editorScrollController,
            config: const QuillEditorConfig(
              placeholder: '开始写作...',
              padding: EdgeInsets.all(8),
            ),
          ),
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardVisible ? keyboardInset : 0),
        child: SafeArea(
          top: false,
          bottom: !keyboardVisible,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 10,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    _formatButton(
                      icon: Icons.dataset_outlined,
                      tooltip: '元数据',
                      onTap: _openMetadataMenu,
                    ),
                    _formatButton(
                      icon: Icons.format_bold,
                      tooltip: '加粗',
                      onTap: () => _toggleAttribute(Attribute.bold),
                      active: _isAttributeEnabled(Attribute.bold),
                    ),
                    _formatButton(
                      icon: Icons.format_italic,
                      tooltip: '斜体',
                      onTap: () => _toggleAttribute(Attribute.italic),
                      active: _isAttributeEnabled(Attribute.italic),
                    ),
                    _formatButton(
                      icon: Icons.format_underline,
                      tooltip: '下划线',
                      onTap: () => _toggleAttribute(Attribute.underline),
                      active: _isAttributeEnabled(Attribute.underline),
                    ),
                    _formatButton(
                      icon: Icons.strikethrough_s,
                      tooltip: '删除线',
                      onTap: () => _toggleAttribute(Attribute.strikeThrough),
                      active: _isAttributeEnabled(Attribute.strikeThrough),
                    ),
                    _formatButton(
                      icon: Icons.text_fields,
                      tooltip: '小字号',
                      onTap: () => _toggleAttribute(Attribute.small),
                      active: _isAttributeEnabled(Attribute.small),
                    ),
                    _formatButton(
                      icon: Icons.format_list_bulleted,
                      tooltip: '无序列表',
                      onTap: () => _toggleAttribute(Attribute.ul),
                      active: _isAttributeEnabled(Attribute.ul),
                    ),
                    _formatButton(
                      icon: Icons.format_list_numbered,
                      tooltip: '有序列表',
                      onTap: () => _toggleAttribute(Attribute.ol),
                      active: _isAttributeEnabled(Attribute.ol),
                    ),
                    _formatButton(
                      icon: Icons.format_quote,
                      tooltip: '引用',
                      onTap: () => _toggleAttribute(Attribute.blockQuote),
                      active: _isAttributeEnabled(Attribute.blockQuote),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多格式',
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
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'h1', child: Text('标题 1')),
                        PopupMenuItem(value: 'h2', child: Text('标题 2')),
                        PopupMenuItem(value: 'h3', child: Text('标题 3')),
                        PopupMenuItem(value: 'p', child: Text('正文')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'left', child: Text('左对齐')),
                        PopupMenuItem(value: 'center', child: Text('居中')),
                        PopupMenuItem(value: 'right', child: Text('右对齐')),
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
}


