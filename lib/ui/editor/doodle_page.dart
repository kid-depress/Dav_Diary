import 'dart:typed_data';

import 'package:diary/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class DoodlePage extends StatefulWidget {
  const DoodlePage({super.key});

  @override
  State<DoodlePage> createState() => _DoodlePageState();
}

class _DoodlePageState extends State<DoodlePage> {
  late SignatureController _controller;
  Color _penColor = Colors.teal;
  double _strokeWidth = 3.5;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: _penColor,
      penStrokeWidth: _strokeWidth,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateController() {
    _controller.dispose();
    _controller = SignatureController(
      penColor: _penColor,
      penStrokeWidth: _strokeWidth,
      exportBackgroundColor: Colors.white,
    );
    setState(() {});
  }

  Future<void> _save() async {
    final png = await _controller.toPngBytes();
    if (png == null || png.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先绘制内容')));
      return;
    }
    final path = await const StorageService().saveDoodle(
      Uint8List.fromList(png),
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手绘涂鸦'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Signature(
                  controller: _controller,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('粗细'),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 12,
                        value: _strokeWidth,
                        onChanged: (value) {
                          setState(() => _strokeWidth = value);
                          _updateController();
                        },
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final color in [
                      Colors.teal,
                      Colors.deepOrange,
                      Colors.blue,
                      Colors.purple,
                      Colors.black,
                    ])
                      GestureDetector(
                        onTap: () {
                          _penColor = color;
                          _updateController();
                        },
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: color,
                          child: _penColor == color
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => _controller.clear(),
                      icon: const Icon(Icons.clear),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
