import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

void main() {
  test('every job has enough clues, and no clue belongs to two jobs', () {
    final seen = <String>{};
    for (final job in Deduction.jobs) {
      expect(job.clues.length, greaterThanOrEqualTo(4), reason: job.name);
      for (final c in job.clues) {
        expect(seen.add(c.clue), isTrue, reason: 'duplicate clue: ${c.clue}');
        expect(c.why, isNotEmpty);
      }
    }
    for (final d in Deduction.decoys) {
      expect(seen.contains(d), isFalse, reason: 'decoy is also a real clue: $d');
    }
  });

  test('deduction cases are fair', () {
    final rng = math.Random(4);
    for (var i = 0; i < 500; i++) {
      final q = Deduction.make(rng);
      expect(q.options.length, 4);
      expect(q.options.toSet().length, 4);
      expect(q.correct, inInclusiveRange(0, 3));
      final lines = q.context.split('\n').where((l) => l.startsWith('• ')).toList();
      expect(lines.length, 4, reason: '3 clues and 1 decoy');
      expect(lines.where((l) => Deduction.decoys.contains(l.substring(2))).length, 1);
      final answer = Deduction.jobs.firstWhere((j) => q.options[q.correct] == '${j.emoji} ${j.name}');
      final clueTexts = answer.clues.map((c) => c.clue).toSet();
      expect(lines.where((l) => clueTexts.contains(l.substring(2))).length, 3);
    }
  });

  test('Poker Face items are well formed, and length doesn\'t give the answer away', () {
    var longer = 0;
    for (final q in PokerFace.items) {
      expect(q.options.length, 2);
      expect(q.correct, inInclusiveRange(0, 1));
      expect(q.context, isNotEmpty);
      if (q.options[q.correct].length > q.options[1 - q.correct].length) longer++;
      final s = q.shuffled(math.Random(1));
      expect(s.options[s.correct], q.options[q.correct]);
    }
    expect(longer / PokerFace.items.length, inInclusiveRange(0.3, 0.7));
    expect(PokerFace.items.length, greaterThanOrEqualTo(10));
  });

  test('lab scores and real-life logs are saved', () {
    final a = GameState(missionsOn: false);
    expect(a.reportLab('deduce', 9), isTrue);
    expect(a.reportLab('deduce', 6), isFalse);
    a.recordDeduction(2);
    a.recordDeduction(1);
    a.recordDeduction(0);
    a.recordBluff('Sam', fooled: true);
    a.recordBluff('Sam', fooled: false);
    expect(a.achievements, contains('deducer'));
    final ip = a.insightPoints;
    expect(ip, 15 * GameState.labIp + 6 + 5);
    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();
    final b = GameState()..restoreFrom(saved);
    expect(b.labBest['deduce'], 9);
    expect(b.deduceStats, <int>[3, 1, 1]);
    expect(b.bluffStats['Sam'], <int>[2, 1]);
    expect(b.insightPoints, ip);
    b.dispose();
  });
}
