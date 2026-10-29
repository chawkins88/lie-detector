import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

void main() {
  test('every drill has a lesson', () {
    for (final d in MemoryDrill.values) {
      expect(MemoryContent.lessons[d], isNotEmpty, reason: d.name);
    }
  });

  test('content pools are big enough for the hardest level', () {
    expect(MemoryContent.words.toSet().length, MemoryContent.words.length);
    expect(MemoryContent.words.length, greaterThan(MemoryDrill.words.maxLevel + 10));
    expect(MemoryContent.palaceRoute.length, MemoryDrill.palace.maxLevel);
    expect(MemoryContent.palaceItems.map((i) => i.name).toSet().length, MemoryContent.palaceItems.length);
    expect(MemoryContent.palaceItems.length, greaterThan(MemoryDrill.palace.maxLevel + 4));
    expect(MemoryContent.faces.toSet().length, greaterThanOrEqualTo(MemoryDrill.faces.maxLevel));
    expect(MemoryContent.names.toSet().length, greaterThan(MemoryDrill.faces.maxLevel + 4));
    expect(MemoryContent.jobs.toSet().length, greaterThanOrEqualTo(MemoryDrill.faces.maxLevel));
    expect(MemoryContent.details.toSet().length, greaterThan(MemoryDrill.faces.maxLevel + 4));
    expect(MemoryContent.kimItems.toSet().length, MemoryContent.kimItems.length);
    expect(MemoryContent.kimItems.length, greaterThan(20 + 4)); // biggest grid + spares
  });

  test('snapshot questions have 4 distinct options', () {
    for (final snap in MemoryContent.snapshots) {
      expect(snap.questions.length, 3, reason: snap.place);
      for (final q in snap.questions) {
        expect(q.options.toSet().length, 4, reason: q.question);
      }
    }
  });

  test('study card ids are unique', () {
    final ids = MemoryContent.cards.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('spaced review schedule', () {
    final m = MemoryState();
    const today = 100;
    final first = m.reviewQueue(today);
    expect(first.length, MemoryState.newCardsPerDay);

    m.review(first[0].id, knew: true, today: today);
    expect(m.cards[first[0].id]!.box, 1);
    expect(m.cards[first[0].id]!.dueDay, today + 1);

    m.review(first[1].id, knew: false, today: today);
    expect(m.cards[first[1].id]!.box, 0);
    expect(m.cards[first[1].id]!.dueDay, today + 1);

    // Known card keeps climbing: 1 → 3 → 7 days.
    m.review(first[0].id, knew: true, today: today + 1);
    expect(m.cards[first[0].id]!.dueDay, today + 1 + 3);
    m.review(first[0].id, knew: true, today: today + 4);
    expect(m.cards[first[0].id]!.dueDay, today + 4 + 7);
  });

  test('levels stay inside their limits', () {
    final m = MemoryState();
    for (var i = 0; i < 50; i++) {
      m.applyTrial(MemoryDrill.digits, passed: true, delta: 1);
    }
    expect(m.level[MemoryDrill.digits], MemoryDrill.digits.maxLevel);
    expect(m.best[MemoryDrill.digits], MemoryDrill.digits.maxLevel);
    for (var i = 0; i < 50; i++) {
      m.applyTrial(MemoryDrill.digits, passed: false, delta: -1);
    }
    expect(m.level[MemoryDrill.digits], MemoryDrill.digits.minLevel);
  });

  test('progress survives a save and reload', () {
    final a = GameState();
    a.recordMemoryTrial(MemoryDrill.palace, passed: true, levelDelta: 1, ip: 7);
    a.reviewCard(MemoryContent.cards.first.id, knew: true);
    a.completeMemorySession(MemoryDrill.palace);
    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();

    final b = GameState()..restoreFrom(saved);
    expect(b.insightPoints, 8);
    expect(b.streak, 1);
    expect(b.memory.level[MemoryDrill.palace], MemoryDrill.palace.startLevel + 1);
    expect(b.memory.cards[MemoryContent.cards.first.id]!.box, 1);
    expect(b.memory.sessions[MemoryDrill.palace], 1);
    b.dispose();
  });

  test('a damaged save falls back to defaults', () {
    final g = GameState()..restoreFrom(<String, dynamic>{'hearts': 'lots', 'memory': 42, 'completed': 'x'});
    expect(g.hearts, GameState.maxHearts);
    expect(g.insightPoints, 0);
    g.dispose();
  });
}
