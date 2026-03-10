import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/calendar/calendar_page.dart';
import 'package:diary/ui/editor/editor_page.dart';
import 'package:diary/ui/home/home_page.dart';
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
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => EditorPage(initialEntry: entry)),
    );
    if (!mounted) {
      return;
    }
    await context.read<DiaryAppState>().refreshEntries();
  }

  Future<void> _openPreview(DiaryEntry entry) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => EntryPreviewPage(entry: entry)),
    );
    if (!mounted) {
      return;
    }
    await context.read<DiaryAppState>().refreshEntries();
  }

  Future<void> _openHomeSearchDialog() async {
    final controller = TextEditingController(text: _homeQuery);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '搜索', en: 'Search')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: tr(
              context,
              zh: '搜索标题或内容',
              en: 'Search title or content',
            ),
            prefixIcon: const Icon(Icons.search),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(tr(context, zh: '清除', en: 'Clear')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(tr(context, zh: '确定', en: 'Done')),
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
      tr(context, zh: '日记', en: 'Diary'),
      tr(context, zh: '回顾', en: 'Calendar'),
      tr(context, zh: '设置', en: 'Settings'),
    ];
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
        label: tr(context, zh: '首页', en: 'Home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        label: tr(context, zh: '回顾', en: 'Calendar'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        label: tr(context, zh: '设置', en: 'Settings'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= _tabletBreakpoint;
        return Scaffold(
          appBar: AppBar(
            title: Text(titles[_index]),
            actions: _index == 0
                ? [
                    IconButton(
                      tooltip: tr(context, zh: '搜索', en: 'Search'),
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
                          ? tr(context, zh: '切换到网格', en: 'Switch to grid')
                          : tr(
                              context,
                              zh: '切换到时间轴',
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
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
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
                        duration: const Duration(milliseconds: 180),
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
