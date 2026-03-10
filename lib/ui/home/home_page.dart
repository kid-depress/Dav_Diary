import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

enum _HomeViewMode { timeline, grid }

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
  static const _minGridCardWidth = 180.0;
  static const _maxGridColumns = 7;
  static const _gridSpacing = 10.0;

  String _query = '';
  _HomeViewMode _viewMode = _HomeViewMode.timeline;

  int _dynamicColumnCount(double width) {
    final rawCount = ((width + _gridSpacing) /
            (_minGridCardWidth + _gridSpacing))
        .floor();
    return rawCount.clamp(1, _maxGridColumns);
  }

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
              child: Column(
                children: [
                  TextField(
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
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<_HomeViewMode>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: _HomeViewMode.timeline,
                            icon: const Icon(Icons.timeline_outlined),
                            label: Text(tr(context, zh: '时间轴', en: 'Timeline')),
                          ),
                          ButtonSegment(
                            value: _HomeViewMode.grid,
                            icon: const Icon(Icons.grid_view_rounded),
                            label: Text(tr(context, zh: '网格', en: 'Grid')),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (selection) {
                          final next = selection.first;
                          if (next == _viewMode) {
                            return;
                          }
                          setState(() => _viewMode = next);
                        },
                      ),
                    ),
                  ),
                ],
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
                        child: _buildContent(filtered, sections),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    List<DiaryEntry> entries,
    Map<DateTime, List<DiaryEntry>> sections,
  ) {
    if (_viewMode == _HomeViewMode.timeline) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final day = sections.keys.elementAt(index);
          final dayEntries = sections[day]!;
          return _TimelineDaySection(
            day: day,
            entries: dayEntries,
            onOpen: widget.onOpen,
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _dynamicColumnCount(constraints.maxWidth);
        return MasonryGridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
          gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
          ),
          mainAxisSpacing: _gridSpacing,
          crossAxisSpacing: _gridSpacing,
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _MasonryEntryCard(
              entry: entry,
              onTap: () => widget.onOpen(entry),
            );
          },
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
    final title = DateFormat('yyyy.MM.dd  EEEE').format(day);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (var i = 0; i < entries.length; i++)
            _TimelineEntryRow(
              entry: entries[i],
              isLast: i == entries.length - 1,
              onTap: () => onOpen(entries[i]),
            ),
        ],
      ),
    );
  }
}

class _TimelineEntryRow extends StatelessWidget {
  const _TimelineEntryRow({
    required this.entry,
    required this.isLast,
    required this.onTap,
  });

  final DiaryEntry entry;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: colors.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TimelineEntryCard(entry: entry, onTap: onTap),
            ),
          ],
        ),
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
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final summary = entry.summary;
    final hasBodyText = summary.isNotEmpty;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImage)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasBodyText) ...[
                    Text(
                      summary,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    DateFormat('MM-dd HH:mm').format(entry.eventAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MasonryEntryCard extends StatelessWidget {
  const _MasonryEntryCard({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  static const _imageAspectOptions = [0.95, 1.0, 1.08, 1.18, 1.28];

  int _textLineCount(String text) {
    if (text.length <= 30) {
      return 2;
    }
    if (text.length <= 70) {
      return 3;
    }
    if (text.length <= 110) {
      return 4;
    }
    return 5;
  }

  double _imageAspectBySeed(String seed) {
    final index = seed.hashCode.abs() % _imageAspectOptions.length;
    return _imageAspectOptions[index];
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = entry.firstImagePath;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final summary = entry.summary;
    final hasBodyText = summary.isNotEmpty;
    final lineCount = hasBodyText ? _textLineCount(summary) : 0;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasImage)
              AspectRatio(
                aspectRatio: _imageAspectBySeed(entry.id),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, _) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                color: Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
                child: Text(
                  '${entry.mood}  ${entry.weather}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasBodyText)
                    Text(
                      summary,
                      maxLines: lineCount,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (entry.location.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.location.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('MM-dd HH:mm').format(entry.eventAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
