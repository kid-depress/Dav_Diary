import 'dart:convert';
import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/services/storage_service.dart';
import 'package:diary/ui/editor/editor_page.dart';
import 'package:diary/ui/motion/motion_dialog.dart';
import 'package:diary/ui/motion/motion_route.dart';
import 'package:diary/ui/preview/attachment_preview_page.dart';
import 'package:diary/ui/widgets/entry_meta_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class EntryPreviewPage extends StatefulWidget {
  const EntryPreviewPage({required this.entry, super.key});

  final DiaryEntry entry;

  @override
  State<EntryPreviewPage> createState() => _EntryPreviewPageState();
}

class _EntryPreviewPageState extends State<EntryPreviewPage> {
  late DiaryEntry _entry;
  late QuillController _previewController;
  final _previewScrollController = ScrollController();
  final _previewFocusNode = FocusNode();
  final StorageService _storageService = const StorageService();
  final Map<String, Future<String?>> _resolvedPathCache = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _previewController = _buildPreviewController(_entry);
  }

  QuillController _buildPreviewController(DiaryEntry entry) {
    try {
      final raw = jsonDecode(entry.deltaJson) as List<dynamic>;
      final controller = QuillController(
        document: Document.fromJson(raw),
        selection: const TextSelection.collapsed(offset: 0),
      );
      controller.readOnly = true;
      return controller;
    } catch (_) {
      final controller = QuillController.basic();
      controller.document.insert(0, entry.plainText);
      controller.readOnly = true;
      return controller;
    }
  }

  Future<void> _editEntry() async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(buildPageTransitionRoute(EditorPage(initialEntry: _entry)));
    if (changed != true || !mounted) {
      return;
    }
    final list = context.read<DiaryAppState>().entries;
    final matches = list.where((item) => item.id == _entry.id).toList();
    if (matches.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }

    final nextEntry = matches.first;
    final nextController = _buildPreviewController(nextEntry);
    setState(() {
      _entry = nextEntry;
      _previewController.dispose();
      _previewController = nextController;
    });
  }

  Future<void> _deleteEntry() async {
    if (_deleting) {
      return;
    }
    final confirm = await showMotionDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '确认删除这篇日记？', en: 'Delete this entry?')),
        content: Text(
          tr(
            context,
            zh: '删除后将进入回收站。',
            en: 'The entry will be moved to trash.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, zh: '鍙栨秷', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(context, zh: '鍒犻櫎', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _deleting = true);
    await context.read<DiaryAppState>().deleteEntry(_entry.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '日记已删除', en: 'Deleted')),
      ),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _openAttachment(DiaryAttachment attachment) async {
    if (!attachment.isVisualImage && !attachment.isVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              zh: '当前附件类型不支持预览',
              en: 'This attachment type is not supported',
            ),
          ),
        ),
      );
      return;
    }
    final resolvedAttachment = await _ensureAttachmentReady(attachment);
    if (!mounted) {
      return;
    }
    final resolvedPath = resolvedAttachment?.path ?? '';
    if (resolvedPath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, zh: '附件文件不存在', en: 'Attachment file is missing'),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      buildPageTransitionRoute(
        AttachmentPreviewPage(attachment: resolvedAttachment!),
      ),
    );
  }

  Future<DiaryAttachment?> _ensureAttachmentReady(
    DiaryAttachment attachment,
  ) async {
    final appState = context.read<DiaryAppState>();
    final localPath = await _resolveAttachmentPath(attachment.path);
    if (localPath != null && localPath.isNotEmpty) {
      return attachment.copyWith(path: localPath);
    }
    if (attachment.remotePath.trim().isEmpty) {
      return null;
    }

    final restored = await appState.restoreAttachmentForEntry(
      _entry.id,
      attachment,
    );
    if (restored == null) {
      return null;
    }

    _resolvedPathCache.clear();
    final reloaded = appState.entries.firstWhere(
      (item) => item.id == _entry.id,
      orElse: () => _entry,
    );
    if (!mounted) {
      return restored;
    }
    final nextController = _buildPreviewController(reloaded);
    setState(() {
      _entry = reloaded;
      _previewController.dispose();
      _previewController = nextController;
    });
    return restored;
  }

  Future<String?> _resolveAttachmentPath(String rawPath) {
    if (rawPath.trim().isEmpty) {
      return Future.value(null);
    }
    return _resolvedPathCache.putIfAbsent(
      rawPath,
      () => _storageService.resolveAttachmentPath(rawPath),
    );
  }

  Widget _buildBrokenAttachment({required double size}) {
    return Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image_outlined),
    );
  }

  Widget _buildAttachment(DiaryAttachment attachment, {double size = 120}) {
    final previewPath = attachment.thumbnailPath.isNotEmpty
        ? attachment.thumbnailPath
        : attachment.path;

    if (attachment.isVisualImage) {
      return InkWell(
        onTap: () => _openAttachment(attachment),
        borderRadius: BorderRadius.circular(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: size,
            height: size,
            child: FutureBuilder<String?>(
              future: _resolveAttachmentPath(previewPath),
              builder: (context, snapshot) {
                final resolvedPath = snapshot.data;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting)
                      Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      )
                    else if (resolvedPath == null)
                      _buildBrokenAttachment(size: size)
                    else
                      Image.file(
                        File(resolvedPath),
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (context, _, _) =>
                            _buildBrokenAttachment(size: size),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.zoom_in_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => _openAttachment(attachment),
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<String?>(
          future: _resolveAttachmentPath(previewPath),
          builder: (context, snapshot) {
            final exists = snapshot.data != null;
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                exists
                    ? (attachment.isVideo
                          ? Icons.videocam_outlined
                          : Icons.attach_file)
                    : Icons.broken_image_outlined,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy-MM-dd HH:mm').format(_entry.eventAt);
    final locationText = _entry.location.trim().isEmpty
        ? tr(context, zh: '未设置', en: 'Not set')
        : _entry.location;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: '鏃ヨ璇︽儏', en: 'Entry Details')),
        actions: [
          IconButton(
            onPressed: _deleting ? null : _deleteEntry,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            tooltip: tr(context, zh: '鍒犻櫎', en: 'Delete'),
          ),
          TextButton(
            onPressed: _deleting ? null : _editEntry,
            child: Text(tr(context, zh: '缂栬緫', en: 'Edit')),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 900;
            final attachmentSize = isTablet ? 150.0 : 126.0;
            final attachmentsSection = Card(
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: _entry.attachments.isNotEmpty
                    ? SizedBox(
                        height: attachmentSize + 8,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemBuilder: (context, index) => _buildAttachment(
                            _entry.attachments[index],
                            size: attachmentSize,
                          ),
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemCount: _entry.attachments.length,
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: colors.surfaceContainerLowest,
                        ),
                        child: Text(
                          tr(context, zh: '鏆傛棤闄勪欢', en: 'No attachments'),
                        ),
                      ),
              ),
            );
            final moodMeta = parseMoodMeta(_entry.mood);
            final weatherMeta = parseWeatherMeta(_entry.weather);

            final metadataSection = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (moodMeta.hasValue)
                  Chip(
                    avatar: Icon(moodMeta.icon, size: 18),
                    label: Text(
                      moodMeta.notes.isEmpty
                          ? tr(context, zh: '蹇冩儏', en: 'Mood')
                          : moodMeta.notes,
                    ),
                  ),
                if (weatherMeta.hasValue)
                  Chip(
                    avatar: Icon(weatherMeta.icon, size: 18),
                    label: Text(
                      weatherMeta.notes.isEmpty
                          ? tr(context, zh: '澶╂皵', en: 'Weather')
                          : weatherMeta.notes,
                    ),
                  ),
                Chip(
                  label: Text(
                    tr(context, zh: '鏃堕棿 $dateText', en: 'Time $dateText'),
                  ),
                ),
                Chip(
                  label: Text(
                    tr(
                      context,
                      zh: '浣嶇疆 $locationText',
                      en: 'Location $locationText',
                    ),
                  ),
                ),
              ],
            );

            final contentSection = Card(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 180),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: QuillEditor.basic(
                  controller: _previewController,
                  focusNode: _previewFocusNode,
                  scrollController: _previewScrollController,
                  config: const QuillEditorConfig(
                    showCursor: false,
                    padding: EdgeInsets.all(4),
                  ),
                ),
              ),
            );
            final hasBodyText = _entry.plainText.trim().isNotEmpty;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                  child: isTablet
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  attachmentsSection,
                                  const SizedBox(height: 14),
                                  metadataSection,
                                ],
                              ),
                            ),
                            if (hasBodyText) ...[
                              const SizedBox(width: 14),
                              Expanded(flex: 6, child: contentSection),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            attachmentsSection,
                            const SizedBox(height: 14),
                            metadataSection,
                            if (hasBodyText) ...[
                              const SizedBox(height: 14),
                              contentSection,
                            ],
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _previewController.dispose();
    _previewScrollController.dispose();
    _previewFocusNode.dispose();
    super.dispose();
  }
}
