import 'dart:io';

import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EntryCard extends StatelessWidget {
  const EntryCard({required this.entry, required this.onTap, super.key});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imagePath = entry.firstImagePath;
    final dateText = DateFormat('MM-dd HH:mm').format(entry.eventAt);
    final metaText = [
      entry.mood.trim(),
      entry.weather.trim(),
    ].where((value) => value.isNotEmpty).join('  ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePath != null && imagePath.isNotEmpty)
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    );
                  },
                ),
              )
            else if (metaText.isNotEmpty)
              Container(
                height: 90,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                child: Text(
                  metaText,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.summary.isEmpty
                        ? tr(context, zh: '点击继续写作...', en: 'Tap to continue...')
                        : entry.summary,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(dateText, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
