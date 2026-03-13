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
  static const _tabletBreakpoint = 840.0;
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

  void _toggleHomeLayoutMode() {
    final appState = context.read<DiaryAppState>();
    final next = appState.homeLayoutMode == 'timeline' ? 'grid' : 'timeline';
    appState.setHomeLayoutMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<DiaryAppState>();
    final titles = [
      tr(context, zh: '\u4E3B\u9875', en: 'Home'),
      tr(context, zh: '\u65E5\u5386', en: 'Calendar'),
      tr(context, zh: '\u66F4\u591A', en: 'More'),
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
        viewMode: appState.homeLayoutMode == 'timeline'
            ? HomeViewMode.timeline
            : HomeViewMode.grid,
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
            title: showDailyQuote
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titles[_index]),
                      const SizedBox(height: 2),
                      Text(
                        appState.dailyQuoteText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  )
                : Text(titles[_index]),
            actions: _index == 0
                ? [
                    IconButton(
                      tooltip: tr(context, zh: '\u641C\u7D22', en: 'Search'),
                      onPressed: _openHomeSearchDialog,
                      icon: Icon(
                        Icons.search,
                        color: _homeQuery.isNotEmpty
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    IconButton(
                      tooltip: appState.homeLayoutMode == 'timeline'
                          ? tr(
                              context,
                              zh: '\u5207\u6362\u5230\u7F51\u683C',
                              en: 'Switch to grid',
                            )
                          : tr(
                              context,
                              zh: '\u5207\u6362\u5230\u65F6\u95F4\u8F74',
                              en: 'Switch to timeline',
                            ),
                      onPressed: _toggleHomeLayoutMode,
                      icon: Icon(
                        appState.homeLayoutMode == 'timeline'
                            ? Icons.grid_view_rounded
                            : Icons.timeline_outlined,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ]
                : null,
          ),
          body: isTablet
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (value) => setState(() {
                        _index = value;
                        if (_index != 0) {
                          _homeBottomBarVisible = true;
                          _showHomeScrollToTop = false;
                        }
                      }),
                      labelType: NavigationRailLabelType.all,
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
                    const VerticalDivider(width: 1),
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
                      FloatingActionButton(
                        heroTag: 'home_scroll_to_top',
                        onPressed: () {
                          setState(() {
                            _homeScrollToTopSignal++;
                            _homeBottomBarVisible = true;
                            _showHomeScrollToTop = false;
                          });
                        },
                        child: const Icon(Icons.keyboard_arrow_up),
                      ),
                      const SizedBox(height: 10),
                    ],
                    FloatingActionButton(
                      onPressed: () => _openEditor(),
                      child: const Icon(Icons.edit_outlined),
                    ),
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
                      NavigationBar(
                        height: 64,
                        selectedIndex: _index,
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysHide,
                        onDestinationSelected: (value) => setState(() {
                          _index = value;
                          if (_index != 0) {
                            _homeBottomBarVisible = true;
                            _showHomeScrollToTop = false;
                          }
                        }),
                        destinations: destinations,
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
