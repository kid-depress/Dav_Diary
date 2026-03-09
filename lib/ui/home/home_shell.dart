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
  bool _fabExtended = true;

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
        onScrollStateChanged: (extended) {
          if (_fabExtended == extended) {
            return;
          }
          setState(() => _fabExtended = extended);
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
          appBar: AppBar(title: Text(titles[_index])),
          body: isTablet
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
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
              ? AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _fabExtended
                      ? FloatingActionButton.extended(
                          key: const ValueKey('fab_extended'),
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.edit_note_outlined),
                          label: Text(
                            tr(context, zh: '写日记', en: 'Write Diary'),
                          ),
                        )
                      : FloatingActionButton(
                          key: const ValueKey('fab_compact'),
                          onPressed: () => _openEditor(),
                          child: const Icon(Icons.edit_outlined),
                        ),
                )
              : null,
          bottomNavigationBar: isTablet
              ? null
              : Column(
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
                      selectedIndex: _index,
                      onDestinationSelected: (value) =>
                          setState(() => _index = value),
                      destinations: destinations,
                    ),
                  ],
                ),
        );
      },
    );
  }
}
