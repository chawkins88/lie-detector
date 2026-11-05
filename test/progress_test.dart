import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

void main() {
  Challenge pick({required int level, required bool hard}) =>
      Curriculum.challenges.firstWhere((c) => c.level == level && c.highLoad == hard && c.type != ChallengeType.baseline);

  test('rating rewards hard questions more and punishes easy misses', () {
    final a = GameState(missionsOn: false);
    a.recordPractice(pick(level: 8, hard: true), correct: true, ip: 0);
    final hardGain = a.lastRatingDelta;
    final b = GameState(missionsOn: false);
    b.recordPractice(pick(level: 2, hard: false), correct: true, ip: 0);
    final easyGain = b.lastRatingDelta;
    expect(hardGain, greaterThan(easyGain));
    expect(easyGain, greaterThan(0));
    b.recordPractice(pick(level: 2, hard: false), correct: false, ip: 0);
    expect(b.lastRatingDelta, lessThan(0));
    expect(a.peakRating, a.rating);
    a.dispose();
    b.dispose();
  });

  test('ranks follow the rating thresholds', () {
    expect(ReaderRank.of(0), ReaderRank.rookie);
    expect(ReaderRank.of(899), ReaderRank.rookie);
    expect(ReaderRank.of(900), ReaderRank.observer);
    expect(ReaderRank.of(1400), ReaderRank.interrogator);
    expect(ReaderRank.of(5000), ReaderRank.human);
    expect(ReaderRank.human.next, isNull);
  });

  test('three missions a day, one from each group, stable for the day', () {
    for (var day = 0; day < 60; day++) {
      final m = MissionKind.forDay(day);
      expect(m.map((k) => k.group).toList(), <int>[0, 1, 2]);
      expect(MissionKind.forDay(day), m);
    }
  });

  test('a lie-reading mission pays once', () {
    final g = GameState();
    final mission = g.todaysMissions.first;
    expect(mission.group, 0);
    for (var i = 0; i < 20; i++) {
      g.recordPractice(pick(level: 2, hard: false), correct: true, ip: 0);
    }
    expect(g.missionDone(mission), isTrue);
    expect(g.insightPoints, GameState.missionReward);
    g.dispose();
  });

  test('checkup covers every level the same way each time', () {
    final maxLevel = Curriculum.challenges.map((c) => c.level).reduce(math.max);
    for (var seed = 0; seed < 30; seed++) {
      final set = checkupSet(math.Random(seed));
      expect(set.length, GameState.checkupLength);
      expect(set.map((c) => c.level).toSet(), <int>{for (var l = 1; l <= maxLevel; l++) l});
      expect(set.map((c) => c.id).toSet().length, set.length, reason: 'no repeats');
      for (var i = 1; i < set.length; i++) {
        expect(set[i].level, greaterThanOrEqualTo(set[i - 1].level));
      }
    }
  });

  test('weak spots list the most-missed skills first', () {
    final g = GameState(missionsOn: false);
    final c = pick(level: 3, hard: false);
    for (var i = 0; i < 4; i++) {
      g.recordPractice(c, correct: false, ip: 0);
    }
    expect(g.weakFlags().first, c.flag);
    g.dispose();
  });

  test('rating, checkups, missions and badges are saved', () {
    final a = GameState(missionsOn: false);
    a.recordPractice(pick(level: 5, hard: true), correct: true, ip: 0);
    a.recordCheckup(14, 20);
    expect(a.achievements, containsAll(<String>['first', 'checkup']));
    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();

    final b = GameState()..restoreFrom(saved);
    expect(b.rating, a.rating);
    expect(b.peakRating, a.peakRating);
    expect(b.checkups, <List<int>>[
      <int>[dayIndex(), 14, 20],
    ]);
    expect(b.firstCheckupPct, 70);
    expect(b.achievements, containsAll(<String>['first', 'checkup']));
    expect(b.ratingLog[dayIndex()], b.rating);
    b.dispose();
  });

  test('older saves start with a rating that reflects their progress', () {
    final level3 = Curriculum.nodes.indexWhere((n) => n.level == 3);
    final g = GameState()
      ..restoreFrom(<String, dynamic>{'answered': 200, 'correct': 160, 'unlocked': level3});
    expect(g.rating, greaterThan(GameState.startRating));
    expect(g.ratingLog, isNotEmpty);
    g.dispose();
  });

  test('real-life clues and confidence are tracked, saved and turned into advice', () {
    final a = GameState(missionsOn: false);
    for (var i = 0; i < 4; i++) {
      a.recordRealLife('Sam', correct: i != 0, clue: LieClue.checkable, confidence: 2);
      a.recordRealLife('Sam', correct: i == 0, clue: LieClue.body, confidence: 0);
    }
    a.recordRealLife('Jo', correct: true); // older-style round, no clue
    expect(a.clueStats[LieClue.checkable], <int>[4, 3]);
    expect(a.clueStats[LieClue.body], <int>[4, 1]);
    expect(a.confidenceStats[2], <int>[4, 3]);
    final advice = RealLifeInsights.takeaway(a)!;
    expect(advice, contains('Checkable facts'));
    expect(advice, contains('body language'));

    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();
    final b = GameState()..restoreFrom(saved);
    expect(b.clueStats[LieClue.checkable], <int>[4, 3]);
    expect(b.confidenceStats[0], <int>[4, 1]);
    expect(b.realLifeStats['Sam'], <int>[8, 4]);
    expect(RealLifeInsights.takeaway(GameState()), isNull);
    b.dispose();
  });
}
