import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

/// Guards against answer choices that give the answer away.
void main() {
  final challenges = Curriculum.challenges;

  test('challenge ids are unique', () {
    final ids = challenges.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('answers point at real options', () {
    for (final c in challenges) {
      expect(c.correct, isNotEmpty, reason: c.id);
      for (final i in c.correct) {
        if (i == Challenge.clean) {
          expect(c.offersClean, isTrue, reason: '${c.id}: clean answer on a layout without it');
          expect(c.correct.length, 1, reason: c.id);
        } else {
          expect(i, inInclusiveRange(0, c.options.length - 1), reason: c.id);
        }
      }
      if (c.type == ChallengeType.cluster) {
        expect(c.options.length, 6, reason: c.id);
        expect(c.correct.length, 3, reason: c.id);
      } else {
        expect(c.correct.length, 1, reason: c.id);
      }
    }
  });

  test('the correct answer is never the longest option', () {
    for (final c in challenges) {
      if (c.type == ChallengeType.microExpression) continue; // one-word emotion labels
      if (c.isClean) continue; // no option is correct
      final lengths = c.options.map((o) => o.length).toList();
      if (c.type == ChallengeType.cluster) {
        final byLength = List<int>.generate(lengths.length, (i) => i)
          ..sort((a, b) => lengths[b].compareTo(lengths[a]));
        expect(byLength.take(3).toSet().containsAll(c.correct), isFalse,
            reason: '${c.id}: the 3 correct indicators are the 3 longest');
      } else {
        final answer = lengths[c.correct.single];
        final longestWrong = [
          for (var i = 0; i < lengths.length; i++)
            if (!c.correct.contains(i)) lengths[i],
        ].reduce(math.max);
        expect(answer <= longestWrong, isTrue, reason: '${c.id}: correct answer is the longest option');
      }
    }
  });

  test('statement answers are not always in the same position', () {
    for (final highLoad in [false, true]) {
      final positions = challenges
          .where((c) => c.type == ChallengeType.statement && c.highLoad == highLoad && !c.isClean)
          .map((c) => c.correct.single)
          .toSet();
      expect(positions.length, greaterThan(1), reason: 'highLoad=$highLoad');
    }
  });

  test('shuffling keeps the same correct answers', () {
    final rng = math.Random(7);
    for (final c in challenges) {
      final s = c.shuffled(rng);
      expect(s.options.toSet(), c.options.toSet(), reason: c.id);
      expect(s.isClean, c.isClean, reason: c.id);
      expect(
        s.correct.where((i) => i >= 0).map((i) => s.options[i]).toSet(),
        c.correct.where((i) => i >= 0).map((i) => c.options[i]).toSet(),
        reason: c.id,
      );
    }
  });

  test('every level with a "nothing here" choice has clean cases', () {
    final levels = challenges.where((c) => c.offersClean).map((c) => c.level).toSet();
    for (final level in levels) {
      expect(challenges.any((c) => c.level == level && c.isClean), isTrue, reason: 'level $level');
    }
  });
}
