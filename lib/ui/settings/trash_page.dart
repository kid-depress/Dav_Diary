import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/diary_entry.dart';
import 'package:diary/ui/motion/motion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  bool _loading = true;
  bool _clearing = false;
  List<DiaryEntry> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await context.read<DiaryAppState>().listDeletedEntries();
    if (!mounted) {
      return;
    }
    setState(() {
      _items = entries;
      _loading = false;
    });
  }

  Future<void> _restore(DiaryEntry entry) async {
    await context.read<DiaryAppState>().restoreEntry(entry.id);
    if (!mounted) {
      return;
    }
    await _load();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '已恢复', en: 'Restored')),
      ),
    );
  }

  Future<void> _deleteForever(DiaryEntry entry) async {
    final confirmed = await showMotionDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '彻底删除', en: 'Delete Forever')),
        content: Text(
          tr(
            context,
            zh: '彻底删除后不可恢复，是否继续？',
            en: 'This cannot be undone. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(context, zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<DiaryAppState>().deleteEntryForever(entry.id);
    if (!mounted) {
      return;
    }
    await _load();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '已彻底删除', en: 'Deleted permanently')),
      ),
    );
  }

  Future<void> _clearAll() async {
    if (_clearing || _items.isEmpty) {
      return;
    }
    final confirmed = await showMotionDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, zh: '清空回收站', en: 'Empty Trash')),
        content: Text(
          tr(
            context,
            zh: '将彻底删除回收站中的全部日记，是否继续？',
            en: 'All trashed entries will be permanently deleted. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(context, zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(context, zh: '清空', en: 'Empty')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _clearing = true);
    final removed = await context.read<DiaryAppState>().clearDeletedEntries();
    if (!mounted) {
      return;
    }
    await _load();
    if (!mounted) {
      return;
    }
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(context, zh: '已清空 $removed 条', en: 'Removed $removed entries'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: '回收站', en: 'Trash')),
        actions: [
          TextButton(
            onPressed: (_items.isEmpty || _clearing) ? null : _clearAll,
            child: _clearing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr(context, zh: '清空', en: 'Empty')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: _TrashSummaryCard(
                        count: _items.length,
                        onClear: (_items.isEmpty || _clearing)
                            ? null
                            : _clearAll,
                      ),
                    ),
                  ),
                  if (_items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.delete_sweep_outlined,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  tr(
                                    context,
                                    zh: '回收站为空',
                                    en: 'Trash is empty',
                                  ),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  tr(
                                    context,
                                    zh: '删除的日记会先保留在这里。',
                                    en: 'Deleted entries will appear here first.',
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                      sliver: SliverList.separated(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final entry = _items[index];
                          return _TrashEntryCard(
                            entry: entry,
                            onRestore: () => _restore(entry),
                            onDeleteForever: () => _deleteForever(entry),
                          );
                        },
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _TrashSummaryCard extends StatelessWidget {
  const _TrashSummaryCard({required this.count, required this.onClear});

  final int count;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.delete_outline, color: colors.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, zh: '已删除条目', en: 'Deleted Entries'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr(context, zh: '$count 条', en: '$count entries'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: onClear,
              child: Text(tr(context, zh: '清空', en: 'Empty')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrashEntryCard extends StatelessWidget {
  const _TrashEntryCard({
    required this.entry,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final DiaryEntry entry;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final updatedText = DateFormat('yyyy-MM-dd HH:mm').format(entry.updatedAt);
    final eventText = DateFormat('yyyy-MM-dd').format(entry.eventAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title.trim().isEmpty
                  ? tr(context, zh: '无标题', en: 'Untitled')
                  : entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              entry.summary.isEmpty
                  ? tr(context, zh: '（无正文）', en: '(No text)')
                  : entry.summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 10),
            Text(
              tr(
                context,
                zh: '记录于 $eventText · 删除于 $updatedText',
                en: 'Event $eventText · Deleted $updatedText',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onRestore,
                    icon: const Icon(Icons.restore_outlined, size: 18),
                    label: Text(tr(context, zh: '恢复', en: 'Restore')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onDeleteForever,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.errorContainer,
                      foregroundColor: colors.onErrorContainer,
                    ),
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: Text(tr(context, zh: '彻底删除', en: 'Delete Forever')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
