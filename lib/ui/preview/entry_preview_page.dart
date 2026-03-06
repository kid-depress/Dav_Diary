import 'dart:convert';
import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/services/storage_service.dart';
import 'package:diary/ui/editor/editor_page.dart';
import 'package:diary/ui/preview/attachment_preview_page.dart';
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => EditorPage(initialEntry: _entry)),
    );
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

  Future<void> _openAttachment(DiaryAttachment attachment) async {
    if (!attachment.isVisualImage && !attachment.isVideo) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该附件暂不支持预览')));
      return;
    }
    final resolvedPath = await _resolveAttachmentPath(attachment.path);
    if (!mounted) {
      return;
    }
    if (resolvedPath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('附件文件不存在或已丢失')));
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AttachmentPreviewPage(
          attachment: attachment.copyWith(path: resolvedPath),
        ),
      ),
    );
  }

  Future<String?> _resolveAttachmentPath(String rawPath) {
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
    if (attachment.isVisualImage) {
      return InkWell(
        onTap: () => _openAttachment(attachment),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: size,
            height: size,
            child: FutureBuilder<String?>(
              future: _resolveAttachmentPath(attachment.path),
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
                      right: 6,
                      bottom: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black45,
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
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<String?>(
          future: _resolveAttachmentPath(attachment.path),
          builder: (context, snapshot) {
            final exists = snapshot.data != null;
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
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
        ? '未设置'
        : _entry.location;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记预览'),
        actions: [TextButton(onPressed: _editEntry, child: const Text('编辑'))],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 900;
            final attachmentSize = isTablet ? 150.0 : 120.0;
            final attachmentsSection = _entry.attachments.isNotEmpty
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                    ),
                    child: const Text('无附件'),
                  );

            final metadataSection = Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('心情 ${_entry.mood}')),
                Chip(label: Text('天气 ${_entry.weather}')),
                Chip(label: Text('时间 $dateText')),
                Chip(label: Text('地址 $locationText')),
              ],
            );

            final contentSection = Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
              child: _entry.plainText.trim().isEmpty
                  ? Text('（无正文）', style: Theme.of(context).textTheme.bodyLarge)
                  : QuillEditor.basic(
                      controller: _previewController,
                      focusNode: _previewFocusNode,
                      scrollController: _previewScrollController,
                      config: const QuillEditorConfig(
                        showCursor: false,
                        padding: EdgeInsets.all(4),
                      ),
                    ),
            );

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                            const SizedBox(width: 14),
                            Expanded(flex: 6, child: contentSection),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            attachmentsSection,
                            const SizedBox(height: 14),
                            metadataSection,
                            const SizedBox(height: 14),
                            contentSection,
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
