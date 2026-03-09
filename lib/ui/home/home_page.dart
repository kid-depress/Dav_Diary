import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.onCreate,
    required this.onOpen,
    required this.onScrollStateChanged,
    super.key,
  });

  final VoidCallback onCreate;
  final ValueChanged<DiaryEntry> onOpen;
  final ValueChanged<bool> onScrollStateChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<DiaryAppState>(
      builder: (context, appState, _) {
        final query = _query.toLowerCase();
        final filtered = appState.entries.where((entry) {
          final title = entry.title.toLowerCase();
          final body = entry.plainText.toLowerCase();
          return title.contains(query) || body.contains(query);
        }).toList()..sort((a, b) => b.eventAt.compareTo(a.eventAt));

        final sections = <DateTime, List<DiaryEntry>>{};
        for (final entry in filtered) {
          final day = DateTime(
            entry.eventAt.year,
            entry.eventAt.month,
            entry.eventAt.day,
          );
          sections.putIfAbsent(day, () => <DiaryEntry>[]).add(entry);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: tr(
                    context,
                    zh: '搜索标题或内容',
                    en: 'Search title or content',
                  ),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? _EmptyState(onCreate: widget.onCreate)
                  : NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (notification.direction == ScrollDirection.reverse) {
                          widget.onScrollStateChanged(false);
                        } else if (notification.direction ==
                            ScrollDirection.forward) {
                          widget.onScrollStateChanged(true);
                        }
                        return false;
                      },
                      child: RefreshIndicator(
                        onRefresh: appState.refreshEntries,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                          itemCount: sections.length,
                          itemBuilder: (context, index) {
                            final day = sections.keys.elementAt(index);
                            final entries = sections[day]!;
                            return _TimelineDaySection(
                              day: day,
                              entries: entries,
                              onOpen: widget.onOpen,
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 42),
          const SizedBox(height: 12),
          Text(
            tr(
              context,
              zh: '还没有日记，先写第一篇吧',
              en: 'No entries yet, write your first one',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: Text(tr(context, zh: '新建日记', en: 'New Entry')),
          ),
        ],
      ),
    );
  }
}

class _TimelineDaySection extends StatelessWidget {
  const _TimelineDaySection({
    required this.day,
    required this.entries,
    required this.onOpen,
  });

  final DateTime day;
  final List<DiaryEntry> entries;
  final ValueChanged<DiaryEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = DateFormat('yyyy.MM.dd  EEEE').format(day);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: entries.length * 150.0,
                color: colors.surfaceContainerHighest,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final entry in entries) ...[
                  _TimelineEntryCard(entry: entry, onTap: () => onOpen(entry)),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntryCard extends StatelessWidget {
  const _TimelineEntryCard({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imagePath = entry.firstImagePath;
    final dateText = DateFormat('HH:mm').format(entry.eventAt);
    final summary = entry.summary.isEmpty
        ? tr(context, zh: '点击继续书写...', en: 'Tap to continue...')
        : entry.summary;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: imagePath != null && imagePath.isNotEmpty
            ? _ImageEntryLayout(
                imagePath: imagePath,
                summary: summary,
                dateText: dateText,
              )
            : _TextEntryLayout(
                summary: summary,
                dateText: dateText,
                mood: entry.mood,
                weather: entry.weather,
              ),
      ),
    );
  }
}

class _ImageEntryLayout extends StatelessWidget {
  const _ImageEntryLayout({
    required this.imagePath,
    required this.summary,
    required this.dateText,
  });

  final String imagePath;
  final String summary;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextEntryLayout extends StatelessWidget {
  const _TextEntryLayout({
    required this.summary,
    required this.dateText,
    required this.mood,
    required this.weather,
  });

  final String summary;
  final String dateText;
  final String mood;
  final String weather;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final firstChar = summary.isEmpty ? '' : summary.substring(0, 1);
    final tailText = summary.length <= 1 ? '' : summary.substring(1);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.tertiaryContainer.withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: color.onSurface),
              children: [
                TextSpan(
                  text: firstChar,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
                TextSpan(text: tailText),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$mood  $weather  •  $dateText',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
