import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

void main() {
  test('auto-split always makes 2-4 digit chunks that add up', () {
    final rng = math.Random(3);
    for (var length = 2; length <= 20; length++) {
      for (var i = 0; i < 200; i++) {
        final sizes = ChunkCoach.autoSplit(length, rng);
        expect(sizes.fold<int>(0, (a, b) => a + b), length);
        expect(sizes.every((s) => s >= 2 && s <= 4), isTrue, reason: 'length $length: $sizes');
      }
    }
  });

  test('numbers match their chunk sizes', () {
    final rng = math.Random(9);
    for (final stage in ChunkCoach.stages) {
      for (var i = 0; i < 200; i++) {
        final sizes = ChunkCoach.autoSplit(stage.length, rng);
        final number = ChunkCoach.makeNumber(sizes, stage.meaningfulBias, rng);
        expect(number.length, stage.length);
        expect(RegExp(r'^\d+$').hasMatch(number), isTrue);
        expect(ChunkCoach.cut(number, sizes).join(), number);
        for (final chunk in ChunkCoach.cut(number, sizes)) {
          expect(ChunkCoach.hints(chunk), isNotEmpty);
          expect(ChunkCoach.spoken(chunk), isNotEmpty);
        }
      }
    }
  });

  test('chunks are spoken as single words', () {
    expect(ChunkCoach.spoken('41'), 'forty-one');
    expect(ChunkCoach.spoken('07'), 'oh-seven');
    expect(ChunkCoach.spoken('418'), 'four eighteen');
    expect(ChunkCoach.spoken('2001'), 'twenty oh-one');
    expect(ChunkCoach.spoken('1900'), 'nineteen hundred');
    expect(ChunkCoach.hints('1984'), contains('the year 1984'));
    expect(ChunkCoach.hints('745'), contains('a time: 7:45'));
    expect(ChunkCoach.hints('365').first, 'days in a year');
  });

  test('three in a row unlocks the next stage, and progress saves', () {
    final g = GameState();
    expect(g.memory.coachStage, 0);
    g.recordCoach(passed: true, stageIndex: 0);
    g.recordCoach(passed: false, stageIndex: 0);
    expect(g.memory.coachStreak, 0);
    for (var i = 0; i < 2; i++) {
      expect(g.recordCoach(passed: true, stageIndex: 0), isFalse);
    }
    expect(g.recordCoach(passed: true, stageIndex: 0), isTrue);
    expect(g.memory.coachStage, 1);
    // Replaying an earlier stage doesn't move you.
    g.recordCoach(passed: true, stageIndex: 0);
    expect(g.memory.coachStreak, 0);

    final saved = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    g.dispose();
    final h = GameState()..restoreFrom(saved);
    expect(h.memory.coachStage, 1);
    h.dispose();
  });
}
