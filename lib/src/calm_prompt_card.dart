import 'dart:async';

import 'package:flutter/material.dart';

import 'activity_sound.dart';
import 'calm_prompts.dart';
import 'session_feed.dart';

class CalmPromptCard extends StatefulWidget {
  const CalmPromptCard({
    required this.item,
    required this.onContinue,
    this.active = true,
    this.sound,
    super.key,
  });

  final PromptFeedItem item;
  final VoidCallback onContinue;
  final bool active;
  final ActivitySound? sound;

  @override
  State<CalmPromptCard> createState() => _CalmPromptCardState();
}

class _CalmPromptCardState extends State<CalmPromptCard>
    with WidgetsBindingObserver {
  late final ActivitySound _sound;
  var _playing = false;
  var _hidden = false;
  var _audioGeneration = 0;
  int? _answer;
  String? _feedback;

  PromptActivity get _activity => widget.item.prompt.activity;
  bool get _counting => _activity != PromptActivity.notice;

  @override
  void initState() {
    super.initState();
    _sound = widget.sound ?? OfflineActivitySound();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(CalmPromptCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void didHaveMemoryPressure() => _stop();

  void _stop() {
    _audioGeneration++;
    unawaited(_sound.stop());
    if (mounted && _playing) setState(() => _playing = false);
  }

  Future<void> _listen() async {
    if (_playing) {
      _stop();
      return;
    }
    final asset = widget.item.soundAsset;
    if (!widget.active || asset == null) return;
    final generation = ++_audioGeneration;
    setState(() {
      _playing = true;
      _feedback = null;
    });
    try {
      await _sound.play(asset);
    } catch (_) {
      if (mounted && generation == _audioGeneration) {
        setState(() => _feedback = 'Sound is unavailable. You can keep going.');
      }
    } finally {
      if (mounted && generation == _audioGeneration) {
        setState(() => _playing = false);
      }
    }
  }

  String get _noun => switch (_activity) {
    PromptActivity.fingers => widget.item.count == 1 ? 'finger' : 'fingers',
    PromptActivity.stars => widget.item.count == 1 ? 'star' : 'stars',
    PromptActivity.voices => widget.item.count == 1 ? 'hello' : 'hellos',
    PromptActivity.chimes => widget.item.count == 1 ? 'chime' : 'chimes',
    _ => widget.item.count == 1 ? 'leaf' : 'leaves',
  };

  void _showAnswer([int? answer]) {
    setState(() {
      _answer = answer;
      _feedback =
          '${widget.item.count} $_noun. ${answer == widget.item.count ? 'Nice noticing.' : 'Take your time.'}';
      _hidden = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audioGeneration++;
    unawaited(_sound.stop());
    super.dispose();
  }

  Widget _cue() {
    if (_activity == PromptActivity.fingers) {
      return Semantics(
        label: '${widget.item.count} $_noun held up',
        child: SizedBox(
          width: 120,
          height: 150,
          child: CustomPaint(painter: _FingerPainter(widget.item.count)),
        ),
      );
    }
    if (widget.item.soundAsset != null) {
      return OutlinedButton.icon(
        onPressed: widget.active ? () => unawaited(_listen()) : null,
        icon: Icon(_playing ? Icons.stop_rounded : Icons.volume_up_rounded),
        label: Text(_playing ? 'Stop' : 'Listen'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xfff4f2ea),
          side: const BorderSide(color: Color(0x66f4f2ea)),
          minimumSize: const Size(132, 48),
        ),
      );
    }
    if (_activity == PromptActivity.notice) {
      return const Icon(
        Icons.nights_stay_rounded,
        size: 46,
        color: Color(0xffe8ebdf),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 68,
          child: Center(
            child: _hidden
                ? const Text(
                    'The leaves are resting.',
                    style: TextStyle(color: Color(0xffe8ebdf)),
                  )
                : Semantics(
                    label: '${widget.item.count} $_noun',
                    child: ExcludeSemantics(
                      child: Wrap(
                        spacing: 13,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: List.generate(
                          widget.item.count,
                          (_) => Icon(
                            _activity == PromptActivity.stars
                                ? Icons.star_rounded
                                : Icons.eco_rounded,
                            size: 38,
                            color: const Color(0xffe8ebdf),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (_activity == PromptActivity.memory)
          TextButton(
            onPressed: () => setState(() => _hidden = !_hidden),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xffe8ebdf),
            ),
            child: Text(_hidden ? 'Show leaves' : 'Hide leaves'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.item.colors.map(Color.new).toList();
    return DecoratedBox(
      decoration: BoxDecoration(color: colors[0]),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -0.5),
                radius: 1.35,
                colors: [colors[1], colors[1].withValues(alpha: 0)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.9, 0.7),
                radius: 1.3,
                colors: [colors[2], colors[2].withValues(alpha: 0)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 76, 24, 86),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'A LITTLE PAUSE',
                                  style: TextStyle(
                                    letterSpacing: 2.6,
                                    fontSize: 11,
                                    color: Color(0xffd0d9cd),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  widget.item.prompt.line,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 25,
                                    height: 1.3,
                                    color: Color(0xfff4f2ea),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _cue(),
                                const SizedBox(height: 20),
                                if (_counting)
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: List.generate(
                                      5,
                                      (index) => OutlinedButton(
                                        onPressed: () => _showAnswer(index + 1),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xfff4f2ea,
                                          ),
                                          backgroundColor: _answer == index + 1
                                              ? const Color(0x22f4f2ea)
                                              : Colors.transparent,
                                          side: const BorderSide(
                                            color: Color(0x55f4f2ea),
                                          ),
                                          minimumSize: const Size(46, 48),
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _feedback ??
                                        'At your own pace. You can just rest, too.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: Color(0xffd0d9cd),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      if (_counting) ...[
                        TextButton(
                          onPressed: () => _showAnswer(),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xffe8ebdf),
                          ),
                          child: const Text('Show me'),
                        ),
                      ],
                      FilledButton(
                        onPressed: () {
                          _stop();
                          widget.onContinue();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffe8ebdf),
                          foregroundColor: const Color(0xff253a37),
                          minimumSize: const Size(126, 48),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FingerPainter extends CustomPainter {
  const _FingerPainter(this.count);
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 110, size.height / 130);
    final skin = Paint()..color = const Color(0xffe8d8c4);
    final outline = Paint()
      ..color = const Color(0xffaa9680)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    void pill(Rect rect, double radius) {
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(shape, skin);
      canvas.drawRRect(shape, outline);
    }

    const tops = [25.0, 12.0, 20.0, 37.0];
    for (var finger = 0; finger < 4; finger++) {
      if (finger < count) {
        pill(
          Rect.fromLTRB(29 + finger * 14, tops[finger], 41 + finger * 14, 87),
          7,
        );
      }
    }
    if (count == 5) {
      canvas.save();
      canvas.translate(19, 70);
      canvas.rotate(-0.65);
      pill(const Rect.fromLTWH(-7, -20, 17, 51), 8);
      canvas.restore();
    }
    pill(const Rect.fromLTWH(27, 69, 60, 49), 17);
    for (var finger = count; finger < 4; finger++) {
      pill(Rect.fromLTWH(29 + finger * 14, 74, 12, 21), 6);
    }
    if (count < 5) {
      final thumb = Path()
        ..moveTo(29, 83)
        ..quadraticBezierTo(51, 78, 56, 96);
      canvas.drawPath(thumb, outline);
    }
    canvas.drawLine(const Offset(46, 107), const Offset(66, 107), outline);
  }

  @override
  bool shouldRepaint(_FingerPainter oldDelegate) => oldDelegate.count != count;
}
