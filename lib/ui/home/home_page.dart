import 'package:diary/app/app_state.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/widgets/entry_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.onCreate, required this.onOpen, super.key});

  final VoidCallback onCreate;
  final ValueChanged<DiaryEntry> onOpen;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<DiaryAppState>(
      builder: (context, appState, _) {
        final list = appState.entries
            .where(
              (entry) =>
                  entry.title.contains(_query) ||
                  entry.plainText.contains(_query),
            )
            .toList();

        return RefreshIndicator(
          onRefresh: appState.refreshEntries,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索标题或内容',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                ),
              ),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 42),
                        const SizedBox(height: 12),
                        const Text('还没有日记，先写第一篇吧'),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.add),
                          label: const Text('新建日记'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.72,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final entry = list[index];
                      return EntryCard(
                        entry: entry,
                        onTap: () => widget.onOpen(entry),
                      );
                    }, childCount: list.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
