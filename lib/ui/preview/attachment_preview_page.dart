import 'dart:io';

import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

class AttachmentPreviewPage extends StatefulWidget {
  const AttachmentPreviewPage({required this.attachment, super.key});

  final DiaryAttachment attachment;

  @override
  State<AttachmentPreviewPage> createState() => _AttachmentPreviewPageState();
}

class _AttachmentPreviewPageState extends State<AttachmentPreviewPage> {
  final StorageService _storageService = const StorageService();
  VideoPlayerController? _videoController;
  bool _saving = false;
  bool _videoReady = false;
  bool _resolvingPath = true;
  String? _resolvedPath;
  String? _fileError;
  String? _videoError;

  bool get _isImage => widget.attachment.isVisualImage;
  bool get _isVideo => widget.attachment.isVideo;

  @override
  void initState() {
    super.initState();
    _initAttachment();
  }

  Future<void> _initAttachment() async {
    final resolved = await _storageService.resolveAttachmentPath(
      widget.attachment.path,
    );
    if (!mounted) {
      return;
    }
    if (resolved == null) {
      setState(() {
        _resolvingPath = false;
        _fileError = tr(
          context,
          zh: '附件文件不存在',
          en: 'Attachment file not found',
        );
      });
      return;
    }

    setState(() {
      _resolvedPath = resolved;
      _resolvingPath = false;
    });

    if (_isVideo) {
      await _initVideo(File(resolved));
    }
  }

  Future<void> _initVideo(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoController = controller;
        _videoReady = true;
      });
      await controller.play();
    } catch (_) {
      await controller.dispose();
      setState(
        () =>
            _videoError = tr(context, zh: '视频加载失败', en: 'Failed to load video'),
      );
    }
  }

  Future<void> _saveToAlbum() async {
    if (_saving) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final zh = isZh(context);
    final msgNotFound = zh ? '附件不存在' : 'Attachment not found';
    final msgUnsupported = zh
        ? '该类型附件不支持保存到相册'
        : 'This file type cannot be saved to album';
    final msgSaved = zh ? '已保存到相册' : 'Saved to album';
    final msgFailed = zh
        ? '保存失败，请检查媒体权限'
        : 'Save failed. Check media permissions.';

    final resolvedPath = _resolvedPath;
    if (resolvedPath == null) {
      messenger.showSnackBar(SnackBar(content: Text(msgNotFound)));
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isImage) {
        await Gal.putImage(resolvedPath, album: 'Kidary');
      } else if (_isVideo) {
        await Gal.putVideo(resolvedPath, album: 'Kidary');
      } else {
        messenger.showSnackBar(SnackBar(content: Text(msgUnsupported)));
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('$msgSaved: ${p.basename(resolvedPath)}')),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(msgFailed)));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: '附件预览', en: 'Attachment Preview')),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveToAlbum,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: tr(context, zh: '保存到相册', en: 'Save to album'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_resolvingPath) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_fileError != null) {
      return Center(child: Text(_fileError!));
    }

    final resolvedPath = _resolvedPath;
    if (resolvedPath == null) {
      return Center(
        child: Text(
          tr(context, zh: '附件文件不存在', en: 'Attachment file not found'),
        ),
      );
    }

    if (_isImage) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Image.file(
          File(resolvedPath),
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => Center(
            child: Text(tr(context, zh: '图片加载失败', en: 'Failed to load image')),
          ),
        ),
      );
    }

    if (_isVideo) {
      if (_videoError != null) {
        return Center(child: Text(_videoError!));
      }
      if (!_videoReady || _videoController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
          const SizedBox(height: 12),
          IconButton.filledTonal(
            onPressed: () async {
              final controller = _videoController!;
              if (controller.value.isPlaying) {
                await controller.pause();
              } else {
                await controller.play();
              }
              if (mounted) {
                setState(() {});
              }
            },
            icon: Icon(
              _videoController!.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
          ),
        ],
      );
    }

    return Center(
      child: Text(tr(context, zh: '该附件类型暂不支持预览', en: 'Preview not supported')),
    );
  }
}
