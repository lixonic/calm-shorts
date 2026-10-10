import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'breath_prompts.dart';
import 'reel_player.dart';
import 'session_feed.dart';
import 'video_library.dart';

class ReelsScreen extends StatefulWidget {
  const ReelsScreen({required this.clips, super.key});

  final List<VideoClip> clips;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> with WidgetsBindingObserver {
  late final SessionFeed _feed;
  late final PageController _pages;
  var _index = 0;
  var _paused = false;
  var _muted = true;
  var _foreground = true;
  var _scrolling = false;
  var _advancing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _feed = SessionFeed(widget.clips);
    _pages = PageController();
  }

  FeedItem get _current => _feed.at(_index);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  Future<void> _move(int delta) async {
    if (!_pages.hasClients || _advancing || _scrolling) return;
    final target = _index + delta;
    if (target < 0 || target >= _feed.length) return;
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
    final video = current is VideoFeedItem ? current : null;
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
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (current is VideoFeedItem) {
              setState(() => _paused = !_paused);
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: PageView.builder(
                    controller: _pages,
                    scrollDirection: Axis.vertical,
                    itemCount: _feed.length,
                    onPageChanged: (index) => setState(() {
                      _index = index;
                      _paused = false;
                    }),
                    itemBuilder: (context, index) {
                      final item = _feed.at(index);
                      return switch (item) {
                        PromptFeedItem(:final prompt) => BreathPromptCard(
                          key: ValueKey('prompt:${prompt.id}:$index'),
                          prompt: prompt,
                          onContinue: () => unawaited(_move(1)),
                        ),
                        VideoFeedItem(:final clip) => ReelPlayer(
                          key: ValueKey('video:${clip.id}:$index'),
                          clip: clip,
                          isCurrent: index == _index,
                          active: index == _index && _foreground && !_scrolling,
                          paused: _paused,
                          muted: _muted,
                          onTogglePause: () =>
                              setState(() => _paused = !_paused),
                          onFinished: () => unawaited(_move(1)),
                          onSkip: () => unawaited(_move(1)),
                        ),
                      };
                    },
                  ),
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.18, 0.72, 1],
                        colors: [
                          Color(0x99000000),
                          Colors.transparent,
                          Colors.transparent,
                          Color(0xcc000000),
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
                      child: Row(
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
                          if (video != null)
                            Text(
                              '${video.videoNumber} / ${video.videoCount}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.65),
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
                            child: Row(
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  size: 16,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  current is PromptFeedItem
                                      ? 'SWIPE WHEN READY'
                                      : 'SWIPE TO WANDER',
                                  style: TextStyle(
                                    letterSpacing: 1.2,
                                    fontSize: 9,
                                    color: Colors.white.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (current is VideoFeedItem) ...[
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
                              ],
                              _CircleControl(
                                label: _index >= _feed.length - 1
                                    ? 'Last moment'
                                    : 'Next',
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
        ),
      ),
    );
  }
}

class BreathPromptCard extends StatelessWidget {
  const BreathPromptCard({
    required this.prompt,
    required this.onContinue,
    super.key,
  });

  final BreathPrompt prompt;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff101410),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 88, 36, 120),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.spa_rounded, size: 42, color: Color(0xffccdec2)),
              const SizedBox(height: 28),
              Text(
                prompt.line,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.25,
                  fontWeight: FontWeight.w400,
                  color: Color(0xfff4f2ea),
                ),
              ),
              const SizedBox(height: 36),
              TextButton(
                onPressed: onContinue,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xff26352b),
                  backgroundColor: const Color(0xffccdec2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Continue'),
              ),
              const Spacer(),
            ],
          ),
        ),
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
