import 'dart:io';

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/motion/motion_spec.dart';
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
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

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

  List<double> _monthHeatPreview(
    DateTime month,
    Map<DateTime, _DayHeatStat> dailyStats, {
    required int maxCount,
    required int maxTextLength,
  }) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final values = <double>[];
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      values.add(
        _heatLevel(
          dailyStats[_dayKey(date)],
          maxCount: maxCount,
          maxTextLength: maxTextLength,
        ),
      );
    }
    return values;
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
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: isSelected
          ? colors.onPrimary
          : (isOutside
                ? colors.onSurfaceVariant
                : (isToday ? colors.primary : colors.onSurface)),
      fontWeight: isToday || isSelected ? FontWeight.w600 : FontWeight.w400,
    );

    final Color backgroundColor;
    if (isSelected) {
      backgroundColor = colors.primary;
    } else if (heat <= 0) {
      backgroundColor = Colors.transparent;
    } else {
      final ratio = heat.clamp(0.0, 1.0);
      backgroundColor = Color.lerp(
        colors.surface,
        colors.primary,
        0.2 + 0.7 * ratio,
      )!;
    }

    return Center(
      child: AnimatedContainer(
        duration: MotionSpec.clickDuration,
        curve: MotionSpec.clickCurve,
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: isToday && !isSelected
              ? Border.all(color: colors.primary.withValues(alpha: 0.72))
              : null,
        ),
        child: Text('${day.day}', style: textStyle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeTag = isZh(context) ? 'zh_CN' : 'en_US';
    return Consumer<DiaryAppState>(
      builder: (context, appState, _) {
        final dayEntries = appState.entriesOfDay(_selectedDay);
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

        final colors = Theme.of(context).colorScheme;
        final selectedLabel = DateFormat('yyyy-MM-dd').format(_selectedDay);
        final monthLabel = DateFormat(
          'MMMM yyyy',
          localeTag,
        ).format(_focusedDay);
        final monthHeat = _monthHeatPreview(
          _focusedDay,
          dailyStats,
          maxCount: maxCount,
          maxTextLength: maxTextLength,
        );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Card(
                color: colors.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, zh: '年度成长轨迹', en: 'Growth Heatmap'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          context,
                          zh: '$monthLabel · 记录密度',
                          en: '$monthLabel · Entry density',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: monthHeat.map((heat) {
                          final level = heat.clamp(0.0, 1.0);
                          final fill = level == 0
                              ? colors.surfaceContainerHighest
                              : Color.lerp(
                                  colors.surfaceContainerHighest,
                                  colors.primary,
                                  0.2 + 0.75 * level,
                                )!;
                          return Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.insights_outlined,
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr(
                                context,
                                zh: '颜色越深表示当天记录更密集',
                                en: 'Darker cells mean denser writing activity',
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: TableCalendar<DiaryEntry>(
                    locale: localeTag,
                    focusedDay: _focusedDay,
                    firstDay: DateTime.utc(2010, 1, 1),
                    lastDay: DateTime.utc(2100, 12, 31),
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    eventLoader: appState.entriesOfDay,
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                      });
                    },
                    onPageChanged: (focusedDay) => _focusedDay = focusedDay,
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Month',
                    },
                    headerStyle: HeaderStyle(
                      titleCentered: true,
                      formatButtonVisible: false,
                      titleTextStyle: Theme.of(context).textTheme.titleMedium!
                          .copyWith(fontWeight: FontWeight.w700),
                      leftChevronIcon: Icon(
                        Icons.chevron_left_rounded,
                        color: colors.primary,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right_rounded,
                        color: colors.primary,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      weekendStyle: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    calendarStyle: const CalendarStyle(markersMaxCount: 0),
                    calendarBuilders: CalendarBuilders<DiaryEntry>(
                      defaultBuilder: (context, day, focusedDay) {
                        final heat = _heatLevel(
                          dailyStats[_dayKey(day)],
                          maxCount: maxCount,
                          maxTextLength: maxTextLength,
                        );
                        return _buildHeatDayCell(
                          context: context,
                          day: day,
                          isSelected: false,
                          isToday: false,
                          isOutside: false,
                          heat: heat,
                        );
                      },
                      outsideBuilder: (context, day, focusedDay) {
                        final heat = _heatLevel(
                          dailyStats[_dayKey(day)],
                          maxCount: maxCount,
                          maxTextLength: maxTextLength,
                        );
                        return _buildHeatDayCell(
                          context: context,
                          day: day,
                          isSelected: false,
                          isToday: false,
                          isOutside: true,
                          heat: heat * 0.55,
                        );
                      },
                      todayBuilder: (context, day, focusedDay) {
                        final heat = _heatLevel(
                          dailyStats[_dayKey(day)],
                          maxCount: maxCount,
                          maxTextLength: maxTextLength,
                        );
                        return _buildHeatDayCell(
                          context: context,
                          day: day,
                          isSelected: false,
                          isToday: true,
                          isOutside: false,
                          heat: heat,
                        );
                      },
                      selectedBuilder: (context, day, focusedDay) {
                        final heat = _heatLevel(
                          dailyStats[_dayKey(day)],
                          maxCount: maxCount,
                          maxTextLength: maxTextLength,
                        );
                        return _buildHeatDayCell(
                          context: context,
                          day: day,
                          isSelected: true,
                          isToday: isSameDay(day, DateTime.now()),
                          isOutside: false,
                          heat: heat,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tr(
                        context,
                        zh: '$monthLabel · ${dayEntries.length} 条',
                        en: '$monthLabel · ${dayEntries.length} entries',
                      ),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: dayEntries.isEmpty
                  ? Center(
                      child: Text(
                        tr(
                          context,
                          zh: '这一天还没有记录',
                          en: 'No entries on this day',
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 112),
                      itemBuilder: (context, index) {
                        final entry = dayEntries[index];
                        final imagePath = entry.firstImagePath;
                        final hasImage =
                            imagePath != null && imagePath.isNotEmpty;
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => widget.onOpen(entry),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hasImage)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Image.file(
                                          File(imagePath),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, _, _) =>
                                              Container(
                                                color: colors
                                                    .surfaceContainerHighest,
                                                alignment: Alignment.center,
                                                child: const Icon(
                                                  Icons.broken_image_outlined,
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                  if (hasImage) const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceContainerHigh,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          DateFormat(
                                            'HH:mm',
                                          ).format(entry.eventAt),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelMedium,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      if (entry.mood.trim().isNotEmpty)
                                        Text(
                                          entry.mood,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.summary.isEmpty
                                        ? tr(
                                            context,
                                            zh: '空白日记',
                                            en: 'Empty entry',
                                          )
                                        : entry.summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(height: 1.45),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemCount: dayEntries.length,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DayHeatStat {
  const _DayHeatStat({required this.count, required this.textLength});

  final int count;
  final int textLength;
}
