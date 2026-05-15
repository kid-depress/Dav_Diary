import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/motion/motion_spec.dart';
import 'package:diary/ui/motion/pressable_scale.dart';
import 'package:diary/ui/motion/staggered_entrance.dart';
import 'package:diary/ui/widgets/entry_meta_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

enum HomeViewMode { grid }

class HomePage extends StatefulWidget {
  const HomePage({
    required this.onCreate,
    required this.onOpen,
    required this.onScrollStateChanged,
    required this.query,
    required this.scrollToTopSignal,
    super.key,
  });

  final VoidCallback onCreate;
  final ValueChanged<DiaryEntry> onOpen;
  final ValueChanged<bool> onScrollStateChanged;
  final String query;
  final int scrollToTopSignal;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _minGridCardWidth = 144.0;
  static const _maxGridColumns = 5;
  static const _gridSpacing = 8.0;
  final ScrollController _scrollController = ScrollController();
  late int _handledScrollToTopSignal;

  int _dynamicColumnCount(double width) {
    if (width < 700) {
      return 2;
    }
    final rawCount =
        ((width + _gridSpacing) / (_minGridCardWidth + _gridSpacing)).floor();
    return rawCount.clamp(1, _maxGridColumns);
  }

  @override
  void initState() {
    super.initState();
    _handledScrollToTopSignal = widget.scrollToTopSignal;
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollToTopSignal != _handledScrollToTopSignal) {
      _handledScrollToTopSignal = widget.scrollToTopSignal;
      _scrollToTop();
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: MotionSpec.pageTransitionDuration,
            curve: MotionSpec.pageTransitionCurve,
          );
        }
      });
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: MotionSpec.pageTransitionDuration,
      curve: MotionSpec.pageTransitionCurve,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DiaryAppState>(
      builder: (context, appState, _) {
        final query = widget.query.trim().toLowerCase();
        final filtered = appState.entries.where((entry) {
          if (query.isEmpty) {
            return true;
          }
          final title = entry.title.toLowerCase();
          final body = entry.plainText.toLowerCase();
          return title.contains(query) || body.contains(query);
        }).toList()..sort((a, b) => b.eventAt.compareTo(a.eventAt));

        if (filtered.isEmpty) {
          return _EmptyState(onCreate: widget.onCreate);
        }
        return NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction == ScrollDirection.reverse) {
              widget.onScrollStateChanged(false);
            } else if (notification.direction == ScrollDirection.forward) {
              widget.onScrollStateChanged(true);
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: appState.refreshEntries,
            child: _buildContent(filtered),
          ),
        );
      },
    );
  }

  Widget _buildContent(List<DiaryEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _dynamicColumnCount(constraints.maxWidth);
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                _gridSpacing,
                12,
                _gridSpacing,
                120,
              ),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: columns,
                mainAxisSpacing: _gridSpacing,
                crossAxisSpacing: _gridSpacing,
                childCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return StaggeredEntrance(
                    key: ValueKey('stagger_${entry.id}'),
                    index: index,
                    child: _GridEntryCard(
                      entry: entry,
                      onTap: () => widget.onOpen(entry),
                    ),
                  );
                },
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
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.primaryContainer,
                        colors.secondaryContainer,
                      ],
                    ),
                  ),
                  child: Icon(
                    Icons.menu_book_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tr(
                    context,
                    zh: '还没有日记，先写第一篇吧',
                    en: 'No entries yet, write your first one',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, zh: '新建日记', en: 'New Entry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridEntryCard extends StatelessWidget {
  const _GridEntryCard({required this.entry, required this.onTap});

  final DiaryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imagePath = entry.firstImagePath;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final hasLocation = entry.location.trim().isNotEmpty;
    final plainText = entry.plainText.trim();
    final summary = entry.summary.trim();
    final previewText = summary.isNotEmpty ? summary : plainText;
    final hasBodyText = plainText.isNotEmpty;
    final hasMeta =
        parseMoodMeta(entry.mood).hasValue ||
        parseWeatherMeta(entry.weather).hasValue;

    return PressableScale(
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage)
                Hero(
                  tag: 'entry_hero_${entry.id}',
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, _) => Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.08),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasBodyText)
                      Text(
                        previewText,
                        maxLines: hasImage ? 3 : 5,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: 1.34,
                          fontWeight: FontWeight.w400,
                          fontSize: 14,
                          color: colors.onSurface,
                        ),
                      ),
                    if (hasLocation) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.location.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant.withValues(alpha: 0.86),
                          fontWeight: FontWeight.w400,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat(hasMeta ? 'yyyy/M/d' : 'yyyy/M/d HH:mm:ss').format(entry.eventAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  letterSpacing: 0.05,
                                  color: colors.onSurfaceVariant.withValues(
                                    alpha: 0.86,
                                  ),
                                  fontWeight: FontWeight.w400,
                                  fontSize: 12,
                                ),
                          ),
                        ),
                        if (hasMeta) ...[
                          const SizedBox(width: 8),
                          _EntryMetaWrap(entry: entry),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryMetaWrap extends StatelessWidget {
  const _EntryMetaWrap({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final mood = parseMoodMeta(entry.mood);
    final weather = parseWeatherMeta(entry.weather);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mood.hasValue)
          _EntryMetaTag(
            icon: mood.icon,
            tooltip: mood.notes.isEmpty
                ? tr(context, zh: '心情', en: 'Mood')
                : mood.notes,
          ),
        if (mood.hasValue && weather.hasValue) const SizedBox(width: 6),
        if (weather.hasValue)
          _EntryMetaTag(
            icon: weather.icon,
            tooltip: weather.notes.isEmpty
                ? tr(context, zh: '天气', en: 'Weather')
                : weather.notes,
          ),
      ],
    );
  }
}

class _EntryMetaTag extends StatelessWidget {
  const _EntryMetaTag({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colors.secondaryContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 14, color: colors.onSecondaryContainer),
      ),
    );
  }
}
