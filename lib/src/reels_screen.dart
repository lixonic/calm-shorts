import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'reel_player.dart';
import 'round_robin.dart';
import 'video_library.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({required this.clips, super.key});

  final List<VideoClip> clips;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> with WidgetsBindingObserver {
  final Map<AspectGroup, RoundRobinTimeline<VideoClip>> _feeds = {};
  final Map<AspectGroup, int> _positions = {};
  late AspectGroup _group;
  late PageController _pages;
  bool _paused = false;
  bool _muted = true;
  bool _foreground = true;
  bool _scrolling = false;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    for (final group in AspectGroup.values) {
      final pool = widget.clips.where((clip) => clip.group == group).toList();
      if (pool.isNotEmpty) {
        _feeds[group] = RoundRobinTimeline(pool);
        _positions[group] = 0;
      }
    }
    _group = _feeds.containsKey(AspectGroup.portrait)
        ? AspectGroup.portrait
        : _feeds.keys.first;
    _pages = PageController();
  }

  int get _index => _positions[_group]!;
  ReelDraw<VideoClip> get _current => _feeds[_group]!.at(_index);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  void _selectGroup(AspectGroup group) {
    if (group == _group || !_feeds.containsKey(group) || _advancing) return;
    final oldPages = _pages;
    setState(() {
      _group = group;
      _pages = PageController(initialPage: _positions[group]!);
      _scrolling = false;
      _paused = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => oldPages.dispose());
  }

  Future<void> _move(int delta) async {
    if (!_pages.hasClients || _advancing || _scrolling) return;
    final target = _index + delta;
    if (target < 0) return;
    _advancing = true;
    try {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (reduceMotion) {
        _pages.jumpToPage(target);
      } else {
        await _pages.animateToPage(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _advancing = false;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification && !_scrolling) {
      setState(() => _scrolling = true);
    } else if (notification is ScrollEndNotification && _scrolling) {
      setState(() => _scrolling = false);
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              unawaited(_move(1)),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              unawaited(_move(1)),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              unawaited(_move(-1)),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              unawaited(_move(-1)),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              setState(() => _paused = !_paused),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth > 640;
              return Container(
                color: desktop ? const Color(0xff26352b) : Colors.black,
                alignment: Alignment.center,
                child: Container(
                  constraints: desktop
                      ? const BoxConstraints(maxWidth: 440)
                      : null,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xff101410),
                    border: desktop
                        ? Border.symmetric(
                            vertical: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          )
                        : null,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: _onScroll,
                        child: PageView.builder(
                          key: ValueKey(_group),
                          controller: _pages,
                          scrollDirection: Axis.vertical,
                          onPageChanged: (index) => setState(() {
                            _positions[_group] = index;
                            _paused = false;
                          }),
                          itemBuilder: (context, index) {
                            final draw = _feeds[_group]!.at(index);
                            return ReelPlayer(
                              key: ValueKey('${_group.name}:$index'),
                              clip: draw.item,
                              isCurrent: index == _index,
                              active:
                                  index == _index && _foreground && !_scrolling,
                              paused: _paused,
                              muted: _muted,
                              onTogglePause: () =>
                                  setState(() => _paused = !_paused),
                              onFinished: () => unawaited(_move(1)),
                              onSkip: () => unawaited(_move(1)),
                            );
                          },
                        ),
                      ),
                      const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0, 0.24, 0.65, 1],
                              colors: [
                                Color(0xcc000000),
                                Colors.transparent,
                                Colors.transparent,
                                Color(0xe0000000),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        top: 0,
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.spa_rounded,
                                      size: 22,
                                      color: Color(0xffccdec2),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'CALM',
                                      style: TextStyle(
                                        letterSpacing: 3,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xfff4f2ea),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${current.position} / ${current.roundSize}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: AspectGroup.values
                                        .map(
                                          (group) => _AspectPill(
                                            label: group.label,
                                            selected: group == _group,
                                            enabled: _feeds.containsKey(group),
                                            onTap: () => _selectGroup(group),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 22,
                        right: 18,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.keyboard_arrow_up_rounded,
                                            size: 16,
                                            color: Colors.white.withValues(
                                              alpha: 0.65,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'SWIPE TO WANDER',
                                            style: TextStyle(
                                              letterSpacing: 1.2,
                                              fontSize: 9,
                                              color: Colors.white.withValues(
                                                alpha: 0.65,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _CircleControl(
                                      label: _muted ? 'Turn sound on' : 'Mute',
                                      icon: _muted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      onPressed: () =>
                                          setState(() => _muted = !_muted),
                                    ),
                                    const SizedBox(height: 12),
                                    _CircleControl(
                                      label: _paused ? 'Play' : 'Pause',
                                      icon: _paused
                                          ? Icons.play_arrow_rounded
                                          : Icons.pause_rounded,
                                      onPressed: () =>
                                          setState(() => _paused = !_paused),
                                    ),
                                    const SizedBox(height: 12),
                                    _CircleControl(
                                      label: 'Next video',
                                      icon: Icons.keyboard_arrow_up_rounded,
                                      onPressed: () => unawaited(_move(1)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AspectPill extends StatelessWidget {
  const _AspectPill({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: enabled ? onTap : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(108, 40),
          foregroundColor: selected
              ? const Color(0xff26352b)
              : const Color(0xfff4f2ea),
          backgroundColor: selected
              ? const Color(0xffccdec2)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 23),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        foregroundColor: const Color(0xfff4f2ea),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
    );
  }
}
