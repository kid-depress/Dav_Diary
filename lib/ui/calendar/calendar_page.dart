import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
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
    final textScore = maxTextLength <= 0 ? 0.0 : stat.textLength / maxTextLength;
    return countScore > textScore ? countScore : textScore;
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
      final minStrength = 0.18;
      final maxStrength = 0.72;
      backgroundColor = Color.lerp(
        colors.surface,
        colors.primary,
        minStrength + (maxStrength - minStrength) * ratio,
      )!;
    }

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: isToday && !isSelected
              ? Border.all(color: colors.primary.withValues(alpha: 0.7))
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
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Card(
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
                  calendarStyle: const CalendarStyle(
                    markersMaxCount: 0,
                    markerDecoration: BoxDecoration(
                      color: Colors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    DateFormat('yyyy-MM-dd').format(_selectedDay),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr(
                      context,
                      zh: '共 ${dayEntries.length} 条',
                      en: '${dayEntries.length} entries',
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
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                      itemBuilder: (context, index) {
                        final entry = dayEntries[index];
                        return ListTile(
                          tileColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          title: Text(
                            entry.summary.isEmpty
                                ? tr(context, zh: '空白日记', en: 'Empty entry')
                                : entry.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            DateFormat('HH:mm').format(entry.eventAt),
                          ),
                          trailing: entry.mood.trim().isEmpty
                              ? null
                              : Text(entry.mood),
                          onTap: () => widget.onOpen(entry),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
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
