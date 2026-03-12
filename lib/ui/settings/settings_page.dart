import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/ui/motion/motion_dialog.dart';
import 'package:diary/ui/motion/motion_route.dart';
import 'package:diary/ui/motion/motion_spec.dart';
import 'package:diary/ui/settings/trash_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) {
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, zh: '无法打开链接', en: 'Cannot open link')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        const _MoodTrendCard(),
        const SizedBox(height: 10),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(tr(context, zh: '清理附件缓存', en: 'Clear Attachment Cache')),
          subtitle: Text(
            tr(
              context,
              zh: '删除本地已同步附件，需要时会从 WebDAV 重新拉取',
              en: 'Delete synced local files and re-download from WebDAV when needed',
            ),
          ),
          onTap: () async {
            final confirmed = await showMotionDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text(tr(context, zh: '清理缓存', en: 'Clear Cache')),
                  content: Text(
                    tr(
                      context,
                      zh: '将删除本地已同步附件的原图文件，缩略图会保留。是否继续？',
                      en: 'Original synced files will be removed and thumbnails kept. Continue?',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(tr(context, zh: '取消', en: 'Cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(tr(context, zh: '清理', en: 'Clear')),
                    ),
                  ],
                );
              },
            );
            if (confirmed != true || !context.mounted) {
              return;
            }
            final removed = await context
                .read<DiaryAppState>()
                .clearSyncedAttachmentCache();
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  tr(
                    context,
                    zh: '已清理 $removed 个附件缓存文件',
                    en: 'Cleared $removed cached attachment files',
                  ),
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(tr(context, zh: '回收站', en: 'Trash')),
          subtitle: Text(
            tr(
              context,
              zh: '恢复或彻底删除已删除日记',
              en: 'Restore or permanently delete entries',
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(
              context,
            ).push(buildPageTransitionRoute(const TrashPage()));
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(tr(context, zh: 'WebDAV 设置', en: 'WebDAV')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(
              context,
            ).push(buildPageTransitionRoute(const WebDavSettingsPage()));
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(tr(context, zh: '外观', en: 'Appearance')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(
              context,
            ).push(buildPageTransitionRoute(const AppearanceSettingsPage()));
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr(context, zh: '关于项目', en: 'About Project')),
          subtitle: Text(
            tr(context, zh: '打开 GitHub 项目主页', en: 'Open GitHub project page'),
          ),
          trailing: const Icon(Icons.open_in_new),
          onTap: () =>
              _openLink(context, 'https://github.com/kid-depress/Dav_Diary'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: Text(tr(context, zh: '联系作者', en: 'Contact Author')),
          subtitle: Text(tr(context, zh: '加入交流群', en: 'Join Group')),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openLink(
            context,
            'https://qun.qq.com/universal-share/share?ac=1&authKey=OwDtxNxyG47DX3WMUDnu91lAyFdkzIU613RHHxCVWrAs2iL15plLPUnpyj95SfjM&busi_data=eyJncm91cENvZGUiOiIxMDkxMTI1NDk1IiwidG9rZW4iOiJjMmM1d2FVMzNOd0NyaXVEeThGR2NjZFdNMVhZKzRpbzlhZ3krQS9lWWY2MzFnOUlGa1plRFErUHVwNW9NUUZ0IiwidWluIjoiMzQ2ODk0MzM2NyJ9&data=pg995AanOfOHor1w9a0u6DhsRI9j991Z3W8kmfoPzum9XTgpaJlgnyU8gCjJ2y-TP6KEkaKxRh1VkEECMt7Hug&svctype=4&tempid=h5_group_info',
          ),
        ),
      ],
    );
  }
}

class _MoodTrendCard extends StatefulWidget {
  const _MoodTrendCard();

  @override
  State<_MoodTrendCard> createState() => _MoodTrendCardState();
}

class _MoodTrendCardState extends State<_MoodTrendCard> {
  bool _showLineChart = true;

  @override
  Widget build(BuildContext context) {
    final entries = context.watch<DiaryAppState>().entries;
    final points = _buildMoodTrendPoints(entries, windowDays: 180);
    final hasData = points.length >= 2;
    final average = hasData
        ? points.map((point) => point.score).reduce((a, b) => a + b) /
              points.length
        : 0.0;
    final latest = hasData ? points.last.score : 0.0;
    final previous = hasData ? points[points.length - 2].score : 0.0;
    final delta = latest - previous;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(context, zh: '心情趋势', en: 'Mood Trend'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: hasData
                      ? () => setState(() => _showLineChart = !_showLineChart)
                      : null,
                  icon: Icon(
                    _showLineChart
                        ? Icons.bar_chart_rounded
                        : Icons.show_chart_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _showLineChart
                        ? tr(context, zh: '柱状图', en: 'Bars')
                        : tr(context, zh: '曲线图', en: 'Line'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                context,
                zh: '近 180 天按周聚合，帮助你观察心理状态变化',
                en: 'Weekly trend over the last 180 days to support self-care',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (!hasData)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  tr(
                    context,
                    zh: '记录两条以上带心情的日记后，即可生成趋势图。',
                    en: 'Add at least two diary entries with mood to generate the trend chart.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else ...[
              SizedBox(
                height: 190,
                width: double.infinity,
                child: CustomPaint(
                  painter: _showLineChart
                      ? _MoodLineChartPainter(
                          points: points,
                          color: Theme.of(context).colorScheme.primary,
                          axisColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          labelColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        )
                      : _MoodBarChartPainter(
                          points: points,
                          color: Theme.of(context).colorScheme.primary,
                          axisColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          labelColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatChip(
                    context,
                    tr(context, zh: '周平均', en: 'Avg'),
                    average.toStringAsFixed(1),
                    Icons.favorite_outline,
                  ),
                  _buildStatChip(
                    context,
                    tr(context, zh: '最新', en: 'Latest'),
                    latest.toStringAsFixed(1),
                    Icons.today_outlined,
                  ),
                  _buildStatChip(
                    context,
                    tr(context, zh: '变化', en: 'Change'),
                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                    delta >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text('$label $value', style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _MoodTrendPoint {
  const _MoodTrendPoint({
    required this.start,
    required this.score,
    required this.count,
  });

  final DateTime start;
  final double score;
  final int count;
}

List<_MoodTrendPoint> _buildMoodTrendPoints(
  List<DiaryEntry> entries, {
  int windowDays = 180,
}) {
  final now = DateTime.now();
  final start = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: windowDays - 1));
  final weekly = <DateTime, List<double>>{};
  for (final entry in entries) {
    if (entry.eventAt.isBefore(start)) {
      continue;
    }
    final score = _extractMoodScore(entry.mood);
    if (score == null) {
      continue;
    }
    final bucket = _startOfWeek(entry.eventAt);
    (weekly[bucket] ??= <double>[]).add(score);
  }

  final points = weekly.entries.map((item) {
    final values = item.value;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return _MoodTrendPoint(start: item.key, score: avg, count: values.length);
  }).toList();
  points.sort((a, b) => a.start.compareTo(b.start));
  if (points.length > 26) {
    return points.sublist(points.length - 26);
  }
  return points;
}

DateTime _startOfWeek(DateTime dateTime) {
  final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

double? _extractMoodScore(String rawMood) {
  final mood = rawMood.trim();
  if (mood.isEmpty) {
    return null;
  }
  const moodScores = <String, double>{
    '😞': 1.0,
    '😐': 2.0,
    '😌': 3.0,
    '🙂': 4.0,
    '😄': 5.0,
    '🥰': 5.0,
  };
  for (final item in moodScores.entries) {
    if (mood.contains(item.key)) {
      return item.value;
    }
  }

  final lower = mood.toLowerCase();
  const positiveHints = ['开心', '高兴', '满足', '愉快', 'happy', 'great', 'good'];
  for (final word in positiveHints) {
    if (lower.contains(word)) {
      return 4.0;
    }
  }
  const negativeHints = [
    '难过',
    '焦虑',
    '疲惫',
    '烦',
    'sad',
    'anxious',
    'tired',
    'bad',
  ];
  for (final word in negativeHints) {
    if (lower.contains(word)) {
      return 2.0;
    }
  }
  return 3.0;
}

class _MoodLineChartPainter extends CustomPainter {
  const _MoodLineChartPainter({
    required this.points,
    required this.color,
    required this.axisColor,
    required this.labelColor,
  });

  final List<_MoodTrendPoint> points;
  final Color color;
  final Color axisColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    const left = 28.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 24.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    if (width <= 0 || height <= 0) {
      return;
    }

    final gridPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + height * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = left + width * i / (points.length - 1);
      final y = top + (5 - points[i].score).clamp(0, 4) / 4 * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.5;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = color;
    for (var i = 0; i < points.length; i++) {
      final x = left + width * i / (points.length - 1);
      final y = top + (5 - points[i].score).clamp(0, 4) / 4 * height;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }

    _drawDateLabels(canvas, size, points.first.start, points.last.start);
  }

  @override
  bool shouldRepaint(covariant _MoodLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.labelColor != labelColor;
  }

  void _drawDateLabels(Canvas canvas, Size size, DateTime start, DateTime end) {
    final style = TextStyle(color: labelColor, fontSize: 11);
    final startPainter = TextPainter(
      text: TextSpan(text: DateFormat('M/d').format(start), style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    startPainter.paint(canvas, Offset(6, size.height - 18));

    final endPainter = TextPainter(
      text: TextSpan(text: DateFormat('M/d').format(end), style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    endPainter.paint(
      canvas,
      Offset(size.width - endPainter.width - 6, size.height - 18),
    );
  }
}

class _MoodBarChartPainter extends CustomPainter {
  const _MoodBarChartPainter({
    required this.points,
    required this.color,
    required this.axisColor,
    required this.labelColor,
  });

  final List<_MoodTrendPoint> points;
  final Color color;
  final Color axisColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    const left = 28.0;
    const right = 12.0;
    const top = 12.0;
    const bottom = 24.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    if (width <= 0 || height <= 0) {
      return;
    }

    final gridPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + height * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    final barGap = 5.0;
    final barWidth = math.max(
      2.0,
      (width - (points.length - 1) * barGap) / points.length,
    );
    final paint = Paint()..color = color.withValues(alpha: 0.82);
    var x = left;
    for (final point in points) {
      final barHeight = ((point.score - 1).clamp(0, 4) / 4) * height;
      final topY = top + height - barHeight;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, topY, barWidth, barHeight),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, paint);
      x += barWidth + barGap;
    }

    _drawDateLabels(canvas, size, points.first.start, points.last.start);
  }

  @override
  bool shouldRepaint(covariant _MoodBarChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.labelColor != labelColor;
  }

  void _drawDateLabels(Canvas canvas, Size size, DateTime start, DateTime end) {
    final style = TextStyle(color: labelColor, fontSize: 11);
    final startPainter = TextPainter(
      text: TextSpan(text: DateFormat('M/d').format(start), style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    startPainter.paint(canvas, Offset(6, size.height - 18));

    final endPainter = TextPainter(
      text: TextSpan(text: DateFormat('M/d').format(end), style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    endPainter.paint(
      canvas,
      Offset(size.width - endPainter.width - 6, size.height - 18),
    );
  }
}

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  static const List<Color> _presetThemeSeedColors = [
    Color(0xFF7A8DA1),
    Color(0xFF1F8A70),
    Color(0xFF00639A),
    Color(0xFF7B5EA7),
    Color(0xFFB25D43),
    Color(0xFFAF3B6E),
    Color(0xFF4E6E58),
    Color(0xFF8F6B00),
    Color(0xFF2F6F9F),
    Color(0xFF008571),
    Color(0xFF8C4A64),
    Color(0xFF4F5D75),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: '外观', en: 'Appearance')),
      ),
      body: Consumer<DiaryAppState>(
        builder: (context, appState, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Text(
                tr(context, zh: '主题', en: 'Theme'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(tr(context, zh: '跟随系统', en: 'System')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(tr(context, zh: '浅色', en: 'Light')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(tr(context, zh: '深色', en: 'Dark')),
                  ),
                ],
                selected: {appState.themeMode},
                onSelectionChanged: (selection) {
                  appState.setThemeMode(selection.first);
                },
              ),
              const SizedBox(height: 20),
              Text(
                tr(context, zh: '自定义主题色', en: 'Custom Theme Color'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  zh: '选择一个种子颜色，应用将自动生成完整的 Material 3 配色方案。',
                  en: 'Pick a seed color and generate a full Material 3 color scheme automatically.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _presetThemeSeedColors.map((color) {
                  return _ThemeSeedColorOption(
                    color: color,
                    selected:
                        appState.themeSeedColor.toARGB32() == color.toARGB32(),
                    onTap: () => appState.setThemeSeedColor(color),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                '${tr(context, zh: '当前', en: 'Current')}: #${appState.themeSeedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text(
                tr(context, zh: '语言', en: 'Language'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'zh_CN', label: Text('中文')),
                  ButtonSegment(value: 'en_US', label: Text('English')),
                ],
                selected: {
                  appState.locale.languageCode == 'en' ? 'en_US' : 'zh_CN',
                },
                onSelectionChanged: (selection) {
                  final code = selection.first;
                  if (code == 'en_US') {
                    appState.setLocale(const Locale('en', 'US'));
                  } else {
                    appState.setLocale(const Locale('zh', 'CN'));
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeSeedColorOption extends StatelessWidget {
  const _ThemeSeedColorOption({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionSpec.clickDuration,
        curve: MotionSpec.clickCurve,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2.4 : 1.2),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 18,
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              )
            : null,
      ),
    );
  }
}

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remoteDirController = TextEditingController();

  bool _loaded = false;
  bool _obscurePassword = true;
  ConflictStrategy _conflictStrategy = ConflictStrategy.lastWriteWins;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    final appState = context.read<DiaryAppState>();
    final config = appState.webDavConfig;
    _urlController.text = config.serverUrl;
    _userController.text = config.username;
    _passwordController.text = config.password;
    _remoteDirController.text = config.remoteDir;
    _conflictStrategy = config.conflictStrategy;
    _loaded = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _remoteDirController.dispose();
    super.dispose();
  }

  Future<bool> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }
    final appState = context.read<DiaryAppState>();
    final messenger = ScaffoldMessenger.of(context);
    final config = WebDavConfig(
      serverUrl: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
      remoteDir: _remoteDirController.text.trim().isEmpty
          ? '/diary'
          : _remoteDirController.text.trim(),
      conflictStrategy: _conflictStrategy,
    );
    await appState.updateWebDavConfig(config);
    if (!mounted) {
      return false;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '配置已保存', en: 'Saved')),
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: 'WebDAV 设置', en: 'WebDAV')),
      ),
      body: Consumer<DiaryAppState>(
        builder: (context, appState, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: tr(context, zh: '服务器地址', en: 'Server URL'),
                        hintText: 'https://dav.example.com',
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? tr(context, zh: '必填', en: 'Required')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _userController,
                      decoration: InputDecoration(
                        labelText: tr(context, zh: '用户名', en: 'Username'),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? tr(context, zh: '必填', en: 'Required')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: tr(context, zh: '密码', en: 'Password'),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? tr(context, zh: '必填', en: 'Required')
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _remoteDirController,
                      decoration: InputDecoration(
                        labelText: tr(context, zh: '远端目录', en: 'Remote Dir'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<ConflictStrategy>(
                      initialValue: _conflictStrategy,
                      decoration: InputDecoration(
                        labelText: tr(
                          context,
                          zh: '冲突策略',
                          en: 'Conflict Strategy',
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: ConflictStrategy.lastWriteWins,
                          child: Text(
                            tr(context, zh: '最后修改者优先', en: 'Last Write Wins'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: ConflictStrategy.keepBoth,
                          child: Text(
                            tr(context, zh: '保留两个副本', en: 'Keep Both'),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _conflictStrategy = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (appState.lastSyncAt != null)
                Text(
                  tr(context, zh: '上次同步：', en: 'Last sync: ') +
                      DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(appState.lastSyncAt!),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _saveConfig,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(tr(context, zh: '保存', en: 'Save')),
                  ),
                  OutlinedButton.icon(
                    onPressed: appState.syncing
                        ? null
                        : () async {
                            final okToContinue = await _saveConfig();
                            if (!okToContinue || !context.mounted) {
                              return;
                            }
                            try {
                              final ok = await appState.testWebDavConnection();
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? tr(
                                            context,
                                            zh: '连接成功',
                                            en: 'Connected',
                                          )
                                        : tr(
                                            context,
                                            zh: '连接失败',
                                            en: 'Failed to connect',
                                          ),
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${tr(context, zh: '连接失败：', en: 'Connection failed: ')}$e',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.network_check_outlined),
                    label: Text(tr(context, zh: '测试连接', en: 'Test')),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: appState.syncing
                        ? null
                        : () async {
                            final okToContinue = await _saveConfig();
                            if (!okToContinue || !context.mounted) {
                              return;
                            }
                            final result = await appState.syncNow();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${result.message} ${tr(context, zh: '上传', en: 'up')}:${result.uploaded} ${tr(context, zh: '下载', en: 'down')}:${result.downloaded} ${tr(context, zh: '冲突', en: 'conflicts')}:${result.conflicts}',
                                ),
                              ),
                            );
                          },
                    icon: appState.syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      appState.syncing
                          ? tr(context, zh: '同步中...', en: 'Syncing...')
                          : tr(context, zh: '立即同步', en: 'Sync now'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
