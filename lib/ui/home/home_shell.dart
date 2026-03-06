import 'package:diary/app/app_state.dart';
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
  int _index = 0;

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
    final titles = ['日记', '回顾', '设置'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(onCreate: () => _openEditor(), onOpen: _openPreview),
          CalendarPage(onOpen: _openPreview),
          const SettingsPage(),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.edit),
              label: const Text('写日记'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: '主页',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: '回顾',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
