import 'dart:math';

class ReelDraw<T> {
  const ReelDraw({
    required this.item,
    required this.round,
    required this.position,
    required this.roundSize,
  });

  final T item;
  final int round;
  final int position;
  final int roundSize;
}

/// Shuffles a complete pool for each pass. Navigation history never redraws it.
class RoundRobinTimeline<T> {
  RoundRobinTimeline(Iterable<T> items, {Random? random})
    : _pool = List.unmodifiable(items),
      _random = random ?? Random() {
    if (_pool.isEmpty) {
      throw ArgumentError.value(items, 'items', 'The pool cannot be empty');
    }
    if (_pool.toSet().length != _pool.length) {
      throw ArgumentError.value(items, 'items', 'The pool must be unique');
    }
  }

  final List<T> _pool;
  final Random _random;
  final List<ReelDraw<T>> _history = [];
  List<T> _deck = [];
  int _cursor = 0;
  int _round = 0;
  T? _lastDrawn;

  int get poolSize => _pool.length;

  ReelDraw<T> at(int index) {
    if (index < 0) throw RangeError.index(index, _history);
    while (_history.length <= index) {
      if (_cursor >= _deck.length) _startRound();
      final item = _deck[_cursor++];
      _history.add(
        ReelDraw(
          item: item,
          round: _round,
          position: _cursor,
          roundSize: _pool.length,
        ),
      );
      _lastDrawn = item;
    }
    return _history[index];
  }

  void _startRound() {
    _deck = List.of(_pool)..shuffle(_random);
    if (_deck.length > 1 && _deck.first == _lastDrawn) {
      final swapIndex = 1 + _random.nextInt(_deck.length - 1);
      final first = _deck.first;
      _deck[0] = _deck[swapIndex];
      _deck[swapIndex] = first;
    }
    _cursor = 0;
    _round++;
  }
}
