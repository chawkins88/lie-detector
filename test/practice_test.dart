import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

String _behaviorOf(String line) {
  final afterArrow = line.split(' → ')[1];
  return afterArrow.substring(0, afterArrow.indexOf(': "'));
}

void main() {
  test('generated baseline cases are fair and need the baseline to solve', () {
    final rng = math.Random(42);
    var clean = 0;
    var longestIsAnswer = 0;
    var answered = 0;
    const runs = 2000;
    for (var i = 0; i < runs; i++) {
      final c = BaselineGenerator.generate(rng, hard: i.isOdd);
      expect(c.options.length, c.highLoad ? 6 : 5);
      expect(c.options.any((o) => o.contains('whether they')), isTrue, reason: 'accusation always asked');

      final baselineMoments = <String>{
        for (final e in BaselineGenerator.habitToMoment.entries)
          if (c.context.contains(e.key)) e.value,
      };
      expect(baselineMoments.length, c.highLoad ? 3 : 2);

      for (var j = 0; j < c.options.length; j++) {
        final behavior = _behaviorOf(c.options[j]);
        final isCause = behavior.contains('; ');
        if (c.correct.contains(j)) {
          expect(baselineMoments.contains(behavior), isFalse, reason: 'the answer must break baseline');
          expect(isCause, isFalse);
        } else if (!isCause) {
          expect(baselineMoments.contains(behavior), isTrue, reason: 'decoys must be baseline habits: $behavior');
        }
      }

      if (c.isClean) {
        clean++;
      } else {
        answered++;
        final lengths = c.options.map((o) => o.length).toList();
        final answerLength = lengths[c.correct.single];
        if (lengths.where((l) => l >= answerLength).length == 1) longestIsAnswer++;
      }
    }
    expect(clean / runs, inInclusiveRange(0.28, 0.42));
    expect(longestIsAnswer / answered, lessThan(0.4), reason: 'length must not give the answer away');
  });

  test('live() swaps fixed baseline questions and leaves others alone', () {
    final rng = math.Random(1);
    for (final c in Curriculum.challenges) {
      final live = BaselineGenerator.live(c, rng);
      if (c.type == ChallengeType.baseline) {
        expect(live.id, startsWith('gen_'));
        expect(live.highLoad, c.highLoad);
      } else {
        expect(identical(live, c), isTrue);
      }
    }
  });

  test('an older save still loads (progress survives updates)', () {
    final today = dayIndex();
    final oldSave = jsonDecode(jsonEncode(<String, Object?>{
      'version': 1,
      'hearts': 2,
      'ip': 340,
      'streak': 3,
      'lastDay': today,
      'unlocked': 4,
      'completed': <String>['l1a', 'l1b', 'r1', 'l2a'],
      'answered': 30,
      'correct': 24,
      'recent': <bool>[true, false, true],
      'attempts': <String, int>{'pacifying': 3},
      'misses': <String, int>{'pacifying': 1},
      'typeMisses': <String, int>{'baseline': 1},
      'nextHeart': null,
      'memory': <String, Object?>{
        'level': <String, int>{'digits': 9},
        'best': <String, int>{'digits': 9},
        'sessions': <String, int>{'digits': 2},
        'lastDone': <String, int>{},
        'cards': <String, List<int>>{'m_chunk': <int>[2, today + 3]},
        'newDay': today,
        'newCount': 3,
      },
    })) as Map<String, dynamic>;

    final g = GameState()..restoreFrom(oldSave);
    expect(g.insightPoints, 340);
    expect(g.hearts, 2);
    expect(g.streak, 3);
    expect(g.unlockedIndex, 4);
    expect(g.completedNodeIds, containsAll(<String>['l1a', 'l1b', 'r1', 'l2a']));
    expect(g.memory.level[MemoryDrill.digits], 9);
    expect(g.memory.cards['m_chunk']!.box, 2);
    expect(g.mistakes, isEmpty);
    g.dispose();
  });

  test('practice state round-trips', () {
    final a = GameState();
    final missed = Curriculum.challenges.first;
    a.recordPractice(missed, correct: false, ip: 0);
    a.reportPracticeScore(PracticeMode.survival.name, 12);
    a.completeDaily(25);
    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();

    final b = GameState()..restoreFrom(saved);
    expect(b.mistakes, contains(missed.id));
    expect(b.practiceBest[PracticeMode.survival.name], 12);
    expect(b.dailyDoneDay, dayIndex());
    expect(b.insightPoints, 25);
    b.recordPractice(missed, correct: true, ip: 3);
    expect(b.mistakes, isNot(contains(missed.id)));
    b.dispose();
  });
}
