import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/motion/motion_spec.dart';
import 'package:diary/ui/motion/staggered_entrance.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({required this.onOpen, super.key});

  final ValueChanged<DiaryEntry> onOpen;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  static const _timelineGap = 10.0;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final ScrollController _timelineController = ScrollController();

  DateTime _dayKey(DateTime day) => DateTime(day.year, day.month, day.day);

  Map<DateTime, _DayHeatStat> _buildDailyStats(List<DiaryEntry> entries) {
    final stats = <DateTime, _DayHeatStat>{};
    for (final entry in entries) {
      final day = _dayKey(entry.eventAt);
      final textLength = entry.plainText.trim().length;
      final existing = stats[day];
      if (existing == null) {
        stats[day] = _DayHeatStat(count: 1, textLength: textLength);
      } else {
        stats[day] = _DayHeatStat(
          count: existing.count + 1,
          textLength: existing.textLength + textLength,
        );
      }
    }
    return stats;
  }

  double _heatLevel(
    _DayHeatStat? stat, {
    required int maxCount,
    required int maxTextLength,
  }) {
    if (stat == null) {
      return 0;
    }
    final countScore = maxCount <= 0 ? 0.0 : stat.count / maxCount;
    final textScore = maxTextLength <= 0
        ? 0.0
        : stat.textLength / maxTextLength;
    return countScore > textScore ? countScore : textScore;
  }

  Color _heatFillColor(ColorScheme colors, double heat) {
    final level = heat.clamp(0.0, 1.0);
    if (level == 0) {
      return colors.surfaceContainerHighest.withValues(alpha: 0.54);
    }
    return Color.lerp(
      colors.secondaryContainer.withValues(alpha: 0.78),
      colors.primary.withValues(alpha: 0.86),
      0.2 + (0.8 * level),
    )!;
  }

  Widget _buildHeatDayCell({
    required BuildContext context,
    required DateTime day,
    required bool isSelected,
    required bool isToday,
    required bool isOutside,
    required double heat,
  }) {
    final colors = Theme.of(context).colorScheme;
    final hasHeat = heat > 0;
    final backgroundColor = isSelected
        ? colors.primary.withValues(alpha: 0.8)
        : (hasHeat ? _heatFillColor(colors, heat) : Colors.transparent);
    final textColor = isOutside
        ? colors.onSurfaceVariant.withValues(alpha: 0.5)
        : (isSelected
              ? colors.onPrimary
              : colors.onSurface.withValues(alpha: hasHeat ? 0.95 : 0.58));

    return Center(
      child: AnimatedContainer(
        duration: MotionSpec.clickDuration,
        curve: MotionSpec.clickCurve,
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: isToday && !isSelected
              ? Border.all(color: colors.primary.withValues(alpha: 0.55))
              : null,
        ),
        child: Text(
          '${day.day}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: textColor,
          ),
        ),
      ),
    );
  }

  int _findClosestEntryIndex(DateTime day, List<DiaryEntry> entries) {
    if (entries.isEmpty) {
      return -1;
    }
    for (var i = 0; i < entries.length; i++) {
      if (isSameDay(entries[i].eventAt, day)) {
        return i;
      }
    }
    var bestIndex = 0;
    var bestDelta = entries.first.eventAt.difference(day).inMinutes.abs();
    for (var i = 1; i < entries.length; i++) {
      final delta = entries[i].eventAt.difference(day).inMinutes.abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double _estimateItemExtent(DiaryEntry entry) {
    final hasImage = (entry.firstImagePath ?? '').isNotEmpty;
    return hasImage ? 190 : 122;
  }

  double _estimateOffsetForIndex(int index, List<DiaryEntry> entries) {
    if (index <= 0 || entries.isEmpty) {
      return 0;
    }
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _estimateItemExtent(entries[i]) + _timelineGap;
    }
    return offset;
  }

  void _scrollTimelineToDay(DateTime day, List<DiaryEntry> entries) {
    final targetIndex = _findClosestEntryIndex(day, entries);
    if (targetIndex < 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineController.hasClients) {
        return;
      }
      final targetOffset = _estimateOffsetForIndex(
        targetIndex,
        entries,
      ).clamp(0.0, _timelineController.position.maxScrollExtent);
      _timelineController.animateTo(
        targetOffset,
        duration: MotionSpec.pageTransitionDuration,
        curve: MotionSpec.pageTransitionCurve,
      );
    });
  }

  @override
  void dispose() {
    _timelineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeTag = isZh(context) ? 'zh_CN' : 'en_US';
    return Consumer<DiaryAppState>(
      builder: (context, appState, _) {
        final sortedEntries = [...appState.entries]
          ..sort((a, b) => b.eventAt.compareTo(a.eventAt));
        final dailyStats = _buildDailyStats(appState.entries);
        final maxCount = dailyStats.values.fold<int>(
          0,
          (maxValue, stat) => stat.count > maxValue ? stat.count : maxValue,
        );
        final maxTextLength = dailyStats.values.fold<int>(
          0,
          (maxValue, stat) =>
              stat.textLength > maxValue ? stat.textLength : maxValue,
        );
        final selectedEntries = appState.entriesOfDay(_selectedDay);
        final colors = Theme.of(context).colorScheme;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: _CalendarPanel(
                focusedDay: _focusedDay,
                selectedDay: _selectedDay,
                localeTag: localeTag,
                dailyStats: dailyStats,
                maxCount: maxCount,
                maxTextLength: maxTextLength,
                heatFillColorBuilder: (heat) => _heatFillColor(colors, heat),
                dayCellBuilder: ({
                  required DateTime day,
                  required bool isSelected,
                  required bool isToday,
                  required bool isOutside,
                  required double heat,
                }) {
                  return _buildHeatDayCell(
                    context: context,
                    day: day,
                    isSelected: isSelected,
                    isToday: isToday,
                    isOutside: isOutside,
                    heat: heat,
                  );
                },
                dayKey: _dayKey,
                heatLevelBuilder: ({
                  required _DayHeatStat? stat,
                  required int maxCount,
                  required int maxTextLength,
                }) {
                  return _heatLevel(
                    stat,
                    maxCount: maxCount,
                    maxTextLength: maxTextLength,
                  );
                },
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  _scrollTimelineToDay(selectedDay, sortedEntries);
                },
                onPageChanged: (focusedDay) {
                  setState(() {
                    _focusedDay = focusedDay;
                  });
                },
                onPrevMonth: () {
                  final prev = DateTime(
                    _focusedDay.year,
                    _focusedDay.month - 1,
                    1,
                  );
                  setState(() {
                    _focusedDay = prev;
                  });
                },
                onNextMonth: () {
                  final next = DateTime(
                    _focusedDay.year,
                    _focusedDay.month + 1,
                    1,
                  );
                  setState(() {
                    _focusedDay = next;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: _SelectedDayHeader(
                selectedDay: _selectedDay,
                count: selectedEntries.length,
              ),
            ),
            Expanded(
              child: sortedEntries.isEmpty
                  ? Center(
                      child: Text(
                        tr(
                          context,
                          zh: '还没有任何日记',
                          en: 'No entries yet',
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: _timelineController,
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 122),
                      itemCount: sortedEntries.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: _timelineGap),
                      itemBuilder: (context, itemIndex) {
                        final entry = sortedEntries[itemIndex];
                        final previous = itemIndex == 0
                            ? null
                            : sortedEntries[itemIndex - 1];
                        final next = itemIndex == sortedEntries.length - 1
                            ? null
                            : sortedEntries[itemIndex + 1];
                        final selected = isSameDay(entry.eventAt, _selectedDay);
                        return StaggeredEntrance(
                          key: ValueKey('timeline_${entry.id}'),
                          index: itemIndex,
                          skipAnimation: itemIndex >= 20,
                          child: RepaintBoundary(
                            child: _TimelineEntryCard(
                              entry: entry,
                              selected: selected,
                              onOpen: widget.onOpen,
                              hasLineAbove: previous != null,
                              hasLineBelow: next != null,
                            ),
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

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.focusedDay,
    required this.selectedDay,
    required this.localeTag,
    required this.dailyStats,
    required this.maxCount,
    required this.maxTextLength,
    required this.dayKey,
    required this.heatLevelBuilder,
    required this.dayCellBuilder,
    required this.heatFillColorBuilder,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final String localeTag;
  final Map<DateTime, _DayHeatStat> dailyStats;
  final int maxCount;
  final int maxTextLength;
  final DateTime Function(DateTime day) dayKey;
  final double Function({
    required _DayHeatStat? stat,
    required int maxCount,
    required int maxTextLength,
  })
  heatLevelBuilder;
  final Widget Function({
    required DateTime day,
    required bool isSelected,
    required bool isToday,
    required bool isOutside,
    required double heat,
  })
  dayCellBuilder;
  final Color Function(double heat) heatFillColorBuilder;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;
  final void Function(DateTime focusedDay) onPageChanged;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final monthText = DateFormat('M', localeTag).format(focusedDay);
    final yearText = DateFormat('yyyy', localeTag).format(focusedDay);

    return Card(
      color: colors.surfaceContainerLow.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          children: [
            _CalendarTopHeader(
              monthText: monthText,
              yearText: yearText,
              onPrevMonth: onPrevMonth,
              onNextMonth: onNextMonth,
            ),
            const SizedBox(height: 2),
            TableCalendar<DiaryEntry>(
              locale: localeTag,
              focusedDay: focusedDay,
              firstDay: DateTime.utc(2010, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              onDaySelected: onDaySelected,
              onPageChanged: onPageChanged,
              availableCalendarFormats: const {CalendarFormat.month: 'Month'},
              headerVisible: false,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              rowHeight: 46,
              daysOfWeekHeight: 22,
              calendarStyle: const CalendarStyle(
                markersMaxCount: 0,
                cellMargin: EdgeInsets.symmetric(vertical: 2),
                outsideDaysVisible: true,
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
                weekendStyle: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
              ),
              calendarBuilders: CalendarBuilders<DiaryEntry>(
                defaultBuilder: (context, day, _) {
                  final heat = heatLevelBuilder(
                    stat: dailyStats[dayKey(day)],
                    maxCount: maxCount,
                    maxTextLength: maxTextLength,
                  );
                  return dayCellBuilder(
                    day: day,
                    isSelected: false,
                    isToday: false,
                    isOutside: false,
                    heat: heat,
                  );
                },
                outsideBuilder: (context, day, _) {
                  final heat = heatLevelBuilder(
                    stat: dailyStats[dayKey(day)],
                    maxCount: maxCount,
                    maxTextLength: maxTextLength,
                  );
                  return dayCellBuilder(
                    day: day,
                    isSelected: false,
                    isToday: false,
                    isOutside: true,
                    heat: heat * 0.58,
                  );
                },
                todayBuilder: (context, day, _) {
                  final heat = heatLevelBuilder(
                    stat: dailyStats[dayKey(day)],
                    maxCount: maxCount,
                    maxTextLength: maxTextLength,
                  );
                  return dayCellBuilder(
                    day: day,
                    isSelected: false,
                    isToday: true,
                    isOutside: false,
                    heat: heat,
                  );
                },
                selectedBuilder: (context, day, _) {
                  final heat = heatLevelBuilder(
                    stat: dailyStats[dayKey(day)],
                    maxCount: maxCount,
                    maxTextLength: maxTextLength,
                  );
                  return dayCellBuilder(
                    day: day,
                    isSelected: true,
                    isToday: isSameDay(day, DateTime.now()),
                    isOutside: false,
                    heat: heat,
                  );
                },
              ),
            ),
            const SizedBox(height: 2),
            _HeatLegend(heatFillColorBuilder: heatFillColorBuilder),
          ],
        ),
      ),
    );
  }
}

class _CalendarTopHeader extends StatelessWidget {
  const _CalendarTopHeader({
    required this.monthText,
    required this.yearText,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  final String monthText;
  final String yearText;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final isChinese = isZh(context);
    final monthLabel = isChinese
        ? '$monthText月'
        : DateFormat('MMM').format(DateTime(2000, int.parse(monthText), 1));
    final yearLabel = isChinese ? '$yearText年' : yearText;

    return Row(
      children: [
        _PseudoDropdownLabel(text: monthLabel),
        const SizedBox(width: 8),
        _PseudoDropdownLabel(text: yearLabel),
        const Spacer(),
        _CircleIconButton(
          icon: Icons.chevron_left_rounded,
          onTap: onPrevMonth,
        ),
        const SizedBox(width: 4),
        _CircleIconButton(
          icon: Icons.chevron_right_rounded,
          onTap: onNextMonth,
        ),
      ],
    );
  }
}

class _PseudoDropdownLabel extends StatelessWidget {
  const _PseudoDropdownLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: colors.surfaceContainerHigh.withValues(alpha: 0.52),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.onSurface.withValues(alpha: 0.78),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: colors.onSurface.withValues(alpha: 0.58),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.52),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 22, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend({required this.heatFillColorBuilder});

  final Color Function(double heat) heatFillColorBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(context, zh: '少', en: 'Less'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          ...List<Widget>.generate(5, (index) {
            final heat = index / 4;
            return Container(
              margin: const EdgeInsets.only(right: 4),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: heatFillColorBuilder(heat),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
          Text(
            tr(context, zh: '多', en: 'More'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedDayHeader extends StatelessWidget {
  const _SelectedDayHeader({required this.selectedDay, required this.count});

  final DateTime selectedDay;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dateText = isZh(context)
        ? DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(selectedDay)
        : DateFormat('EEE, MMM d, yyyy').format(selectedDay);
    return Row(
      children: [
        Expanded(
          child: Text(
            dateText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.secondaryContainer.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tr(
              context,
              zh: '$count 条',
              en: '$count entries',
            ),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineEntryCard extends StatelessWidget {
  const _TimelineEntryCard({
    required this.entry,
    required this.selected,
    required this.onOpen,
    required this.hasLineAbove,
    required this.hasLineBelow,
  });

  final DiaryEntry entry;
  final bool selected;
  final ValueChanged<DiaryEntry> onOpen;
  final bool hasLineAbove;
  final bool hasLineBelow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final imagePath = entry.firstImagePath;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final content = entry.summary.trim().isEmpty
        ? tr(context, zh: '空白日记', en: 'Empty entry')
        : entry.summary.trim();
    final headerText = isZh(context)
        ? DateFormat('yyyy年M月d日 EEEE HH:mm:ss', 'zh_CN').format(entry.eventAt)
        : DateFormat('yyyy-MM-dd EEEE HH:mm:ss').format(entry.eventAt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimelineRail(
            hasLineAbove: hasLineAbove,
            hasLineBelow: hasLineBelow,
            active: selected,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card(
              color: selected
                  ? colors.surfaceContainerHigh.withValues(alpha: 0.92)
                  : colors.surfaceContainerLow.withValues(alpha: 0.86),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onOpen(entry),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              headerText,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12.5,
                                  ),
                            ),
                          ),
                          Icon(
                            Icons.edit_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.78,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        content,
                        maxLines: hasImage ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: colors.onSurface,
                          height: 1.3,
                        ),
                      ),
                      if (hasImage) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (context, _, _) => Container(
                                color: colors.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.hasLineAbove,
    required this.hasLineBelow,
    required this.active,
  });

  final bool hasLineAbove;
  final bool hasLineBelow;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dotColor = active
        ? Color.lerp(colors.primary, colors.secondary, 0.36)!
        : colors.secondary.withValues(alpha: 0.64);
    final lineColor = colors.onSurfaceVariant.withValues(alpha: 0.24);

    return SizedBox(
      width: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (hasLineAbove)
            Positioned(
              top: 0,
              bottom: 15,
              child: Container(width: 2, color: lineColor),
            ),
          if (hasLineBelow)
            Positioned(
              top: 15,
              bottom: 0,
              child: Container(width: 2, color: lineColor),
            ),
          Container(
            width: active ? 16 : 14,
            height: active ? 16 : 14,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.surface.withValues(alpha: 0.92),
                width: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeatStat {
  const _DayHeatStat({required this.count, required this.textLength});

  final int count;
  final int textLength;
}
