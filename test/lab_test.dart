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

  test('typed guesses: right, close (same field) or wrong', () {
    const cases = <(String, String, GuessVerdict)>[
      ('car mechanic', 'Mechanic', GuessVerdict.right),
      ('mechnic', 'Mechanic', GuessVerdict.right),
      ('welder', 'Mechanic', GuessVerdict.close),
      ('a welder i think', 'Mechanic', GuessVerdict.close),
      ('nurse', 'Mechanic', GuessVerdict.wrong),
      ('asdfgh', 'Mechanic', GuessVerdict.unknown),
      ('I think a fire fighter', 'Firefighter', GuessVerdict.right),
      ('doctor', 'Nurse', GuessVerdict.close),
      ('cook', 'Chef', GuessVerdict.right),
      ('teacher', 'Guitar teacher', GuessVerdict.close),
      ('musician', 'Guitar teacher', GuessVerdict.right),
      ('mailman', 'Mail carrier', GuessVerdict.right),
      ('ups driver', 'Truck driver', GuessVerdict.close),
      ('electrician', 'Carpenter', GuessVerdict.close),
      ('lawyer', 'Programmer', GuessVerdict.wrong),
      ('software engineer', 'Programmer', GuessVerdict.right),
      ('electrican', 'Electrician', GuessVerdict.right),
      ('Nurses', 'Nurse', GuessVerdict.right),
      ('they are a dentist', 'Dentist', GuessVerdict.right),
      ('vet', 'Vet tech', GuessVerdict.right),
      ('veteran', 'Vet tech', GuessVerdict.unknown),
      ('waiter', 'Chef', GuessVerdict.close),
      ('farmer', 'Landscaper', GuessVerdict.close),
      ('hair stylist', 'Hairdresser', GuessVerdict.right),
      ('it', 'Programmer', GuessVerdict.unknown),
      ("it's a nurse", 'Nurse', GuessVerdict.right),
      ('trainer', 'Personal trainer', GuessVerdict.right),
      ('coach', 'Personal trainer', GuessVerdict.close),
      ('plumber', 'House painter', GuessVerdict.close),
      ('accountant', 'Lawyer', GuessVerdict.wrong),
      ('music teacher', 'Teacher', GuessVerdict.close),
      ('engineer', 'Electrician', GuessVerdict.wrong),
    ];
    for (final (guess, answer, verdict) in cases) {
      expect(JobWords.judge(guess, answer).verdict, verdict, reason: '"$guess" for $answer');
    }
    expect(JobWords.judge('welder', 'Mechanic').field, 'skilled trades');
  });

  test('every Case Files job is known by name, and names don\'t collide', () {
    for (final job in Deduction.jobs) {
      expect(JobWords.targets.containsKey(job.name), isTrue, reason: job.name);
      expect(JobWords.judge(job.name, job.name).verdict, GuessVerdict.right, reason: job.name);
      for (final alias in JobWords.targets[job.name]!.$2) {
        expect(JobWords.judge(alias, job.name).verdict, GuessVerdict.right, reason: alias);
      }
    }
    final seen = <String>{};
    for (final e in JobWords.targets.entries) {
      for (final a in e.value.$2) {
        expect(seen.add(JobWords.words(a).join(' ')), isTrue, reason: 'duplicate name: $a');
      }
    }
    for (final k in JobWords.others.keys) {
      expect(seen.add(JobWords.words(k).join(' ')), isTrue, reason: 'duplicate name: $k');
      for (final f in JobWords.others[k]!) {
        expect(JobWords.fieldNames.containsKey(f), isTrue, reason: '$k field $f');
      }
    }
  });

  test('Think Like Jane cases are fair and play in four steps', () {
    for (final c in ThinkLikeJane.cases) {
      expect(c.steps.length, 4, reason: c.title);
      for (final q in c.steps) {
        expect(q.options.length, 4, reason: c.title);
        expect(q.options.toSet().length, 4, reason: c.title);
        final lengths = q.options.map((o) => o.length).toList();
        final longestWrong = <int>[
          for (var i = 0; i < 4; i++)
            if (i != q.correct) lengths[i],
        ].reduce(math.max);
        expect(lengths[q.correct], lessThanOrEqualTo(longestWrong), reason: '${c.title}: ${q.prompt}');
      }
    }
    final rng = math.Random(8);
    final run = ThinkLikeJane.caseQuestions(rng);
    expect(run.length, 8);
    expect(run.first.context, contains('📁'));
    final when = ThinkLikeJane.whenQuestions(rng);
    expect(when.length, 10);
    for (final q in when) {
      expect(q.options.toSet().length, 4);
      expect(q.explain, startsWith(q.options[q.correct]));
    }
  });
}
