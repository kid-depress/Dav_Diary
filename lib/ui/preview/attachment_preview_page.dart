import 'dart:io';

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
        _fileError = 'Attachment file not found';
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
      setState(() => _videoError = 'Failed to load video');
    }
  }

  Future<void> _saveToAlbum() async {
    if (_saving) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final resolvedPath = _resolvedPath;
    if (resolvedPath == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Attachment not found')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isImage) {
        await Gal.putImage(resolvedPath, album: 'Kidary');
      } else if (_isVideo) {
        await Gal.putVideo(resolvedPath, album: 'Kidary');
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This file type cannot be saved to album'),
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Saved to album: ${p.basename(resolvedPath)}')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Save failed. Check media permissions.')),
      );
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
        title: const Text('Attachment Preview'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveToAlbum,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Save to album',
          ),
        ],
      ),
      body: SafeArea(child: Center(child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_resolvingPath) {
      return const CircularProgressIndicator();
    }

    if (_fileError != null) {
      return Text(_fileError!);
    }

    final resolvedPath = _resolvedPath;
    if (resolvedPath == null) {
      return const Text('Attachment not found');
    }

    if (_isImage) {
      return InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Image.file(
          File(resolvedPath),
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => const Text('Failed to load image'),
        ),
      );
    }

    if (_isVideo) {
      if (_videoError != null) {
        return Text(_videoError!);
      }
      if (!_videoReady || _videoController == null) {
        return const CircularProgressIndicator();
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

    return const Text('Preview not supported for this file');
  }
}
