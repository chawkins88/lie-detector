import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

void main() {
  test('every case is complete', () {
    for (final c in ConsultantCases.all) {
      expect(c.unexpectedQuestions.length, c.suspects.length, reason: c.id);
      expect(c.evidence.any((e) => e.implicates), isTrue, reason: c.id);
      for (var i = 0; i < c.suspects.length; i++) {
        final s = c.suspects[i];
        for (final kind in AskKind.values) {
          expect(s.answers[kind], isNotNull, reason: '${c.id}/${s.name}/${kind.name}');
        }
        for (final e in c.evidence) {
          expect(s.evidence[e.id], isNotNull, reason: '${c.id}/${s.name}/${e.id}');
        }
        if (i == c.guilty) {
          expect(s.confession, isNotNull, reason: c.id);
          for (final e in c.evidence.where((e) => e.implicates)) {
            expect(s.evidenceEarly[e.id], isNotNull, reason: '${c.id}/${s.name} early ${e.id}');
          }
        }
      }
    }
  });

  test('good technique gets a confession within budget', () {
    for (final c in ConsultantCases.all) {
      final inv = Investigation(c);
      final g = c.guilty;
      inv.ask(g, AskKind.smallTalk);
      inv.ask(g, AskKind.open);
      inv.ask(g, AskKind.detail);
      inv.ask(g, AskKind.reverse);
      for (final e in c.evidence.where((e) => e.implicates)) {
        inv.show(g, e);
      }
      expect(inv.questionsUsed, lessThanOrEqualTo(c.questionBudget));
      inv.accuse(g);
      expect(inv.solved, isTrue, reason: c.id);
      expect(inv.stars, 3, reason: c.id);
    }
  });

  test('pressure and early evidence are not enough', () {
    for (final c in ConsultantCases.all) {
      final inv = Investigation(c);
      final g = c.guilty;
      inv.ask(g, AskKind.pressure);
      for (final e in c.evidence.where((e) => e.implicates)) {
        inv.show(g, e); // before their story: weak
      }
      inv.accuse(g);
      expect(inv.solved, isFalse, reason: c.id);
    }
  });

  test('two wrong accusations end the case', () {
    final c = ConsultantCases.all.first;
    final innocent = List<int>.generate(c.suspects.length, (i) => i).firstWhere((i) => i != c.guilty);
    final inv = Investigation(c);
    inv.accuse(innocent);
    expect(inv.over, isFalse);
    inv.accuse(innocent);
    expect(inv.over, isTrue);
    expect(inv.solved, isFalse);
  });

  test('progress log, case stars and real-life record are saved', () {
    final a = GameState();
    a.recordPractice(Curriculum.challenges.first, correct: true, ip: 0);
    a.recordPractice(Curriculum.challenges.first, correct: false, ip: 0);
    a.recordCase('tips', 3);
    a.recordRealLife('Sam', correct: true);
    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();

    final b = GameState()..restoreFrom(saved);
    expect(b.dayLog[dayIndex()], <int>[2, 1]);
    expect(b.caseStars['tips'], 3);
    expect(b.realLifeStats['Sam'], <int>[1, 1]);
    b.dispose();
  });
}
