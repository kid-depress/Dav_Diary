import 'dart:convert';
import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/editor/editor_page.dart';
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

  Widget _buildAttachment(DiaryAttachment attachment) {
    if (attachment.isVisualImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(attachment.path),
          width: 120,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (context, _, _) => Container(
            width: 120,
            height: 120,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Icon(
        attachment.isVideo ? Icons.videocam_outlined : Icons.attach_file,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy-MM-dd HH:mm').format(_entry.eventAt);
    final locationText = _entry.location.trim().isEmpty ? '未设置' : _entry.location;

    return Scaffold(
      appBar: AppBar(
        title: const Text('日记预览'),
        actions: [
          TextButton(
            onPressed: _editEntry,
            child: const Text('编辑'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_entry.attachments.isNotEmpty)
                SizedBox(
                  height: 128,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) =>
                        _buildAttachment(_entry.attachments[index]),
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemCount: _entry.attachments.length,
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  ),
                  child: const Text('无附件'),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('心情 ${_entry.mood}')),
                  Chip(label: Text('天气 ${_entry.weather}')),
                  Chip(label: Text('时间 $dateText')),
                  Chip(label: Text('地址 $locationText')),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                ),
                child: _entry.plainText.trim().isEmpty
                    ? Text(
                        '（无正文）',
                        style: Theme.of(context).textTheme.bodyLarge,
                      )
                    : QuillEditor.basic(
                        controller: _previewController,
                        focusNode: _previewFocusNode,
                        scrollController: _previewScrollController,
                        config: const QuillEditorConfig(
                          showCursor: false,
                          padding: EdgeInsets.all(4),
                        ),
                      ),
              ),
            ],
          ),
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
