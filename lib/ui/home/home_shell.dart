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
import 'package:diary/ui/motion/pressable_scale.dart';
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
            title: AnimatedSwitcher(
              duration: MotionSpec.tabSwitchDuration,
              switchInCurve: MotionSpec.emphasizedDecelerate,
              switchOutCurve: MotionSpec.emphasizedAccelerate,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [...previousChildren, ?currentChild],
              ),
              child: KeyedSubtree(
                key: ValueKey<String>('appbar_title_$_index'),
                child: _index == 0
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
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
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
                      child: _IndexedTabFadeThrough(
                        index: _index,
                        children: pages,
                      ),
                    ),
                  ],
                )
              : _IndexedTabFadeThrough(index: _index, children: pages),
          floatingActionButton: _index == 0
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedScale(
                      scale: _showHomeScrollToTop ? 1.0 : 0.5,
                      duration: MotionSpec.popupDuration,
                      curve: MotionSpec.popupCurve,
                      child: AnimatedOpacity(
                        opacity: _showHomeScrollToTop ? 1.0 : 0.0,
                        duration: MotionSpec.popupDuration,
                        curve: MotionSpec.popupCurve,
                        child: IgnorePointer(
                          ignoring: !_showHomeScrollToTop,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FloatingActionButton.small(
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
                          ),
                        ),
                      ),
                    ),
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
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
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
                                height: 58,
                                selectedIndex: _index,
                                labelBehavior:
                                    NavigationDestinationLabelBehavior
                                        .alwaysHide,
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

/// A state-preserving fade-through for tab switches. The wrapped subtree
/// (an [IndexedStack]) keeps all pages alive; on each index change we replay a
/// short M3 fade-through (delayed fade-in + subtle upscale) on the now-visible
/// page. Only opacity + transform animate, so it stays cheap.
class _TabFadeThrough extends StatefulWidget {
  const _TabFadeThrough({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFadeThrough> createState() => _TabFadeThroughState();
}

class _TabFadeThroughState extends State<_TabFadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: MotionSpec.tabSwitchDuration,
    vsync: this,
    value: 1,
  );

  // Reveal the incoming page in the back portion of the timeline — the
  // hallmark of an M3 fade-through.
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.35, 1, curve: Curves.easeOut),
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.97, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: MotionSpec.emphasizedDecelerate,
        ),
      );

  @override
  void didUpdateWidget(covariant _TabFadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MotionSpec.reduceMotion(context);
    return FadeTransition(
      opacity: _fade,
      child: reduceMotion
          ? RepaintBoundary(child: widget.child)
          : ScaleTransition(
              scale: _scale,
              child: RepaintBoundary(child: widget.child),
            ),
    );
  }
}

/// A state-preserving M3 fade-through for tab switches.
///
/// All pages stay mounted in one [IndexedStack]. The old page fades away before
/// the visible index changes, then the new page fades in with a subtle scale.
/// This avoids a hard content swap while retaining scroll positions and form
/// state for every tab.
class _IndexedTabFadeThrough extends StatefulWidget {
  const _IndexedTabFadeThrough({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_IndexedTabFadeThrough> createState() => _IndexedTabFadeThroughState();
}

class _IndexedTabFadeThroughState extends State<_IndexedTabFadeThrough>
    with SingleTickerProviderStateMixin {
  static const _swapPoint = 0.35;

  late final AnimationController _controller = AnimationController(
    duration: MotionSpec.tabSwitchDuration,
    vsync: this,
    value: 1,
  )..addListener(_updateVisibleIndex);
  late int _visibleIndex;
  int? _nextIndex;
  bool _swapped = true;

  late final Animation<double> _fade = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 0,
      ).chain(CurveTween(curve: MotionSpec.emphasizedAccelerate)),
      weight: _swapPoint,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: 1,
      ).chain(CurveTween(curve: MotionSpec.emphasizedDecelerate)),
      weight: 1 - _swapPoint,
    ),
  ]).animate(_controller);

  late final Animation<double> _scale = Tween<double>(begin: 0.98, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(
            _swapPoint,
            1,
            curve: MotionSpec.emphasizedDecelerate,
          ),
        ),
      );

  @override
  void initState() {
    super.initState();
    _visibleIndex = widget.index;
  }

  @override
  void didUpdateWidget(covariant _IndexedTabFadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _nextIndex = widget.index;
      _swapped = false;
      _controller.forward(from: 0);
    }
  }

  void _updateVisibleIndex() {
    if (_swapped || _controller.value < _swapPoint) {
      return;
    }
    setState(() {
      _visibleIndex = _nextIndex ?? widget.index;
      _swapped = true;
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_updateVisibleIndex)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(
      child: IndexedStack(index: _visibleIndex, children: widget.children),
    );
    return FadeTransition(
      opacity: _fade,
      child: MotionSpec.reduceMotion(context)
          ? content
          : ScaleTransition(scale: _scale, child: content),
    );
  }
}

class _PrimaryGradientFab extends StatefulWidget {
  const _PrimaryGradientFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PrimaryGradientFab> createState() => _PrimaryGradientFabState();
}

class _PrimaryGradientFabState extends State<_PrimaryGradientFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    duration: MotionSpec.medium2,
    vsync: this,
  );
  late final Animation<double> _scale = CurvedAnimation(
    parent: _entrance,
    curve: MotionSpec.emphasizedDecelerate,
  );

  @override
  void initState() {
    super.initState();
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fab = PressableScale(
      pressedScale: 0.92,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onPressed,
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
      ),
    );
    if (MotionSpec.reduceMotion(context)) {
      return fab;
    }
    return ScaleTransition(scale: _scale, child: fab);
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
