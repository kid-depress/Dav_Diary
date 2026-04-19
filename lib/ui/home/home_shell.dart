import 'dart:ui' as ui;

import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/calendar/calendar_page.dart';
import 'package:diary/ui/editor/editor_page.dart';
import 'package:diary/ui/home/home_page.dart';
import 'package:diary/ui/motion/motion_dialog.dart';
import 'package:diary/ui/motion/motion_route.dart';
import 'package:diary/ui/motion/motion_spec.dart';
import 'package:diary/ui/preview/entry_preview_page.dart';
import 'package:diary/ui/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabletBreakpoint = 900.0;
  int _index = 0;
  String _homeQuery = '';
  bool _homeBottomBarVisible = true;
  bool _showHomeScrollToTop = false;
  int _homeScrollToTopSignal = 0;

  Future<void> _openEditor([DiaryEntry? entry]) async {
    await Navigator.of(
      context,
    ).push<bool>(buildPageTransitionRoute(EditorPage(initialEntry: entry)));
    if (!mounted) {
      return;
    }
    await context.read<DiaryAppState>().refreshEntries();
  }

  Future<void> _openPreview(DiaryEntry entry) async {
    await Navigator.of(
      context,
    ).push<bool>(buildCardExpandPreviewRoute(EntryPreviewPage(entry: entry)));
    if (!mounted) {
      return;
    }
    await context.read<DiaryAppState>().refreshEntries();
  }

  Future<void> _openHomeSearchDialog() async {
    final controller = TextEditingController(text: _homeQuery);
    final result = await showMotionDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '\u641C\u7D22', en: 'Search')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr(
              context,
              zh: '\u641C\u7D22\u6807\u9898\u6216\u5185\u5BB9',
              en: 'Search title or content',
            ),
            prefixIcon: const Icon(Icons.search),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, zh: '\u53D6\u6D88', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(tr(context, zh: '\u6E05\u7A7A', en: 'Clear')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(tr(context, zh: '\u5B8C\u6210', en: 'Done')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) {
      return;
    }
    setState(() => _homeQuery = result);
  }

  void _selectTab(int value) {
    setState(() {
      _index = value;
      if (_index != 0) {
        _homeBottomBarVisible = true;
        _showHomeScrollToTop = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<DiaryAppState>();
    final colors = Theme.of(context).colorScheme;
    final titles = [
      tr(context, zh: '\u4E3B\u9875', en: 'Home'),
      tr(context, zh: '\u65E5\u5386', en: 'Calendar'),
      tr(context, zh: '\u8BBE\u7F6E', en: 'Settings'),
    ];
    final showDailyQuote =
        _index == 0 &&
        appState.dailyQuoteEnabled &&
        appState.dailyQuoteText.trim().isNotEmpty;
    final pages = [
      HomePage(
        onCreate: () => _openEditor(),
        onOpen: _openPreview,
        query: _homeQuery,
        scrollToTopSignal: _homeScrollToTopSignal,
        onScrollStateChanged: (extended) {
          final bottomVisible = extended;
          final showTopArrow = !extended;
          if (_homeBottomBarVisible == bottomVisible &&
              _showHomeScrollToTop == showTopArrow) {
            return;
          }
          setState(() {
            _homeBottomBarVisible = bottomVisible;
            _showHomeScrollToTop = showTopArrow;
          });
        },
      ),
      CalendarPage(onOpen: _openPreview),
      const SettingsPage(),
    ];
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.grid_view_rounded),
        label: tr(context, zh: '\u4E3B\u9875', en: 'Home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        label: tr(context, zh: '\u65E5\u5386', en: 'Calendar'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.more_horiz),
        label: tr(context, zh: '\u66F4\u591A', en: 'More'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= _tabletBreakpoint;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 72,
            titleSpacing: 22,
            title: _index == 0
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          context,
                          zh: 'THE LIVING ARCHIVE',
                          en: 'THE LIVING ARCHIVE',
                        ),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.tertiary,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        titles[_index],
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (showDailyQuote) ...[
                        const SizedBox(height: 1),
                        Text(
                          appState.dailyQuoteText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                        ),
                      ],
                    ],
                  )
                : Text(
                    titles[_index],
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.86),
                  ),
                ),
              ),
            ),
            actions: _index == 0
                ? [
                    _TopRoundIconButton(
                      tooltip: tr(context, zh: '\u641C\u7D22', en: 'Search'),
                      icon: Icons.search,
                      active: _homeQuery.isNotEmpty,
                      onTap: _openHomeSearchDialog,
                    ),
                    const SizedBox(width: 10),
                  ]
                : const [SizedBox(width: 4)],
          ),
          body: isTablet
              ? Row(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 14, 0, 12),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: _selectTab,
                        labelType: NavigationRailLabelType.all,
                        useIndicator: true,
                        indicatorColor: colors.secondaryContainer,
                        backgroundColor: Colors.transparent,
                        destinations: destinations
                            .map(
                              (item) => NavigationRailDestination(
                                icon: item.icon,
                                selectedIcon: item.selectedIcon,
                                label: Text(item.label),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: IndexedStack(index: _index, children: pages),
                    ),
                  ],
                )
              : IndexedStack(index: _index, children: pages),
          floatingActionButton: _index == 0
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_showHomeScrollToTop) ...[
                      FloatingActionButton.small(
                        heroTag: 'home_scroll_to_top',
                        onPressed: () {
                          setState(() {
                            _homeScrollToTopSignal++;
                            _homeBottomBarVisible = true;
                            _showHomeScrollToTop = false;
                          });
                        },
                        backgroundColor: colors.surfaceContainerHigh,
                        foregroundColor: colors.onSurface,
                        child: const Icon(Icons.keyboard_arrow_up),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _PrimaryGradientFab(onPressed: () => _openEditor()),
                  ],
                )
              : null,
          bottomNavigationBar: isTablet
              ? null
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: (_index == 0 && !_homeBottomBarVisible) ? 0 : 1,
                  ),
                  duration: MotionSpec.pageTransitionDuration,
                  curve: MotionSpec.pageTransitionCurve,
                  builder: (context, value, child) {
                    return ClipRect(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: value,
                        child: FractionalTranslation(
                          translation: Offset(0, 1 - value),
                          child: Opacity(opacity: value, child: child),
                        ),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: MotionSpec.popupDuration,
                        child: appState.syncing
                            ? const SizedBox(
                                height: 2,
                                child: LinearProgressIndicator(),
                              )
                            : const SizedBox(height: 2),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surface.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.shadow.withValues(
                                      alpha: 0.07,
                                    ),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: NavigationBar(
                                height: 68,
                                selectedIndex: _index,
                                labelBehavior:
                                    NavigationDestinationLabelBehavior
                                        .onlyShowSelected,
                                onDestinationSelected: _selectTab,
                                destinations: destinations,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PrimaryGradientFab extends StatelessWidget {
  const _PrimaryGradientFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Ink(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary,
                Color.lerp(colors.primary, colors.secondary, 0.52)!,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(Icons.edit_outlined, color: colors.onPrimary),
        ),
      ),
    );
  }
}

class _TopRoundIconButton extends StatelessWidget {
  const _TopRoundIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? colors.secondaryContainer
            : colors.surfaceContainerHigh.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 20,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
