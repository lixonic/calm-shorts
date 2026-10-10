import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'video_library.dart';

class ReelPlayer extends StatefulWidget {
  const ReelPlayer({
    required this.clip,
    required this.isCurrent,
    required this.active,
    required this.paused,
    required this.muted,
    required this.onTogglePause,
    required this.onFinished,
    required this.onSkip,
    super.key,
  });

  final VideoClip clip;
  final bool isCurrent;
  final bool active;
  final bool paused;
  final bool muted;
  final VoidCallback onTogglePause;
  final VoidCallback onFinished;
  final VoidCallback onSkip;

  @override
  State<ReelPlayer> createState() => _ReelPlayerState();
}

class _ReelPlayerState extends State<ReelPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _finishedNotified = false;
  bool _completionScheduled = false;
  int _playbackRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.asset(
      widget.clip.assetPath,
      // The reel screen owns lifecycle playback so resumed clips cannot rewind.
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    _controller = controller;
    controller.addListener(_onPlayback);
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      await controller.setLooping(false);
      if (!mounted || _controller != controller) return;
      setState(() => _failed = false);
      await _syncPlayback();
    } catch (_) {
      if (mounted && _controller == controller) {
        setState(() => _failed = true);
      }
    }
  }

  void _onPlayback() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError && !_failed) {
      setState(() => _failed = true);
    }
    if (!_finishedNotified &&
        !_completionScheduled &&
        value.isInitialized &&
        !value.hasError &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        widget.isCurrent &&
        widget.active &&
        !widget.paused) {
      _completionScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _completionScheduled = false;
        if (mounted &&
            widget.isCurrent &&
            widget.active &&
            !widget.paused &&
            controller == _controller &&
            controller.value.position >= controller.value.duration) {
          _finishedNotified = true;
          widget.onFinished();
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void didUpdateWidget(covariant ReelPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final returningToHistory = widget.isCurrent && !oldWidget.isCurrent;
    if (returningToHistory) {
      _finishedNotified = false;
    }
    if (returningToHistory ||
        widget.active != oldWidget.active ||
        widget.paused != oldWidget.paused ||
        widget.muted != oldWidget.muted) {
      unawaited(_syncPlayback(restart: returningToHistory));
    }
  }

  Future<void> _syncPlayback({bool restart = false}) async {
    final controller = _controller;
    final revision = ++_playbackRevision;
    if (controller == null || !controller.value.isInitialized || _failed) {
      return;
    }
    try {
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted ||
          controller != _controller ||
          revision != _playbackRevision) {
        return;
      }
      if (restart) await controller.seekTo(Duration.zero);
      if (!mounted || revision != _playbackRevision) return;
      if (widget.active && !widget.paused) {
        if (controller.value.duration > Duration.zero &&
            controller.value.position >= controller.value.duration) {
          _onPlayback();
          return;
        }
        if (!mounted || revision != _playbackRevision) return;
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {
      if (mounted && controller == _controller) setState(() => _failed = true);
    }
  }

  Future<void> _retry() async {
    final previous = _controller;
    _controller = null;
    _playbackRevision++;
    previous?.removeListener(_onPlayback);
    if (previous != null) await previous.dispose();
    if (!mounted) return;
    setState(() {
      _failed = false;
      _finishedNotified = false;
    });
    await _initialize();
  }

  @override
  void dispose() {
    _playbackRevision++;
    _controller?.removeListener(_onPlayback);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized = controller?.value.isInitialized ?? false;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xff101410)),
        if (!initialized && widget.clip.posterAssetPath != null)
          Image.asset(widget.clip.posterAssetPath!, fit: BoxFit.cover),
        if (initialized && !_failed && controller != null)
          ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
          ),
        if (!_failed)
          Semantics(
            button: true,
            label: widget.paused ? 'Play video' : 'Pause video',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTogglePause,
              child: Center(
                child: AnimatedOpacity(
                  opacity: widget.paused && widget.active ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.36),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, size: 42),
                  ),
                ),
              ),
            ),
          ),
        if (!initialized && !_failed)
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_failed)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.spa_outlined, size: 36),
                  const SizedBox(height: 12),
                  const Text('This moment could not play'),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _retry,
                        child: const Text('Try again'),
                      ),
                      FilledButton(
                        onPressed: widget.onSkip,
                        child: const Text('Next video'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (initialized && widget.active)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller!,
              builder: (context, value, child) => LinearProgressIndicator(
                value: value.duration.inMilliseconds == 0
                    ? 0
                    : (value.position.inMilliseconds /
                              value.duration.inMilliseconds)
                          .clamp(0.0, 1.0),
                minHeight: 2,
                color: const Color(0xffccdec2),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
      ],
    );
  }
}
