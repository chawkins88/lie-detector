import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

/// Cards like 'As', 'Td', '7h': rank then suit (s, h, d, c).
List<int> cards(String spec) {
  const ranks = '23456789TJQKA';
  const suits = 'shdc';
  return spec.split(' ').map((c) => Poker.card(ranks.indexOf(c[0]), suits.indexOf(c[1]))).toList();
}

int score(String spec) => Poker.evaluate(cards(spec));

void main() {
  test('hand categories rank in the right order', () {
    final ladder = <String>[
      'As Ks Qs Js Ts 2d 3c', // royal flush
      '9h 8h 7h 6h 5h Ad Kc', // straight flush
      '7c 7d 7h 7s Kd 2c 3h', // quads
      'Kh Ks Kd 4c 4h 2s 9d', // full house
      'Ah 9h 6h 4h 2h Kd Qc', // flush
      'Ts 9d 8c 7h 6s 2d 2c', // straight
      'Qs Qd Qh 9c 5h 3d 2s', // trips
      'Js Jd 5c 5h Ad 9s 2c', // two pair
      'As Ad Kc 9h 7d 4s 2c', // pair
      'Ah Kd 9c 7s 5h 3d 2c', // high card
    ];
    for (var i = 0; i < ladder.length - 1; i++) {
      expect(score(ladder[i]), greaterThan(score(ladder[i + 1])), reason: '${ladder[i]} vs ${ladder[i + 1]}');
    }
    expect(Poker.describe(score(ladder[0])), 'Royal flush');
    expect(Poker.describe(score(ladder[3])), 'Kings full of Fours');
    expect(Poker.describe(score(ladder[7])), 'Two pair, Jacks and Fives');
  });

  test('wheels, kickers, best five of seven, and splits', () {
    expect(Poker.describe(score('As 2d 3c 4h 5s Kd Kc')), 'Straight, Five high');
    expect(score('6s 2d 3c 4h 5s Kd Qc'), greaterThan(score('As 2d 3c 4h 5s Kd Qc')));
    expect(score('Ks Kd Ac 9h 7d 4s 2c'), greaterThan(score('Kh Kc Qd 9s 7c 4d 2h')));
    // Board plays for both: a split.
    final board = cards('As Ks Qs Js Ts');
    expect(Poker.evaluate(<int>[...cards('2d 3c'), ...board]), Poker.evaluate(<int>[...cards('4h 5h'), ...board]));
    // Two trips make a full house with the higher one on top.
    expect(Poker.describe(score('9s 9d 9c 4h 4s 4d Ac')), 'Nines full of Fours');
  });

  test('equity is sensible', () {
    final rng = math.Random(3);
    expect(Poker.equity(cards('As Ad'), const <int>[], rng, trials: 2000), greaterThan(0.8));
    expect(Poker.equity(cards('7c 2d'), const <int>[], rng, trials: 2000), lessThan(0.4));
  });

  test('a flush draw has 9 outs', () {
    final (flush, straight) = Poker.drawOuts(cards('Ah 7h Kh 2h 9c'));
    expect(flush, 9);
    expect(straight, 0);
  });

  test('hands follow the betting rules and never create or lose chips', () {
    final rng = math.Random(11);
    for (var n = 0; n < 400; n++) {
      final stacks = <int>[20 + rng.nextInt(500), 20 + rng.nextInt(500)];
      final h = HoldemHand(stacks: stacks, button: n % 2, rng: rng);
      expect(h.pot, 15);
      var guard = 0;
      while (!h.over && guard++ < 100) {
        final seat = h.toAct;
        expect(h.stacks[seat], greaterThanOrEqualTo(0));
        final roll = rng.nextInt(10);
        if (roll == 0 && h.toCall(seat) > 0) {
          h.fold();
        } else if (roll < 3 && h.canRaise(seat)) {
          h.raiseTo(h.minRaiseTo(seat) + rng.nextInt(60));
        } else {
          h.checkOrCall();
        }
      }
      expect(h.over, isTrue);
      expect(h.stacks[0] + h.stacks[1], stacks[0] + stacks[1], reason: 'hand $n');
      expect(h.net(0) + h.net(1), 0);
      if (!h.endedByFold) expect(h.board.length, 5);
    }
  });

  test('checking it down reaches a showdown', () {
    final h = HoldemHand(stacks: <int>[200, 200], button: 0, rng: math.Random(1));
    h.checkOrCall(); // button completes the small blind
    expect(h.street, PokerStreet.preflop, reason: 'big blind still gets an option');
    h.checkOrCall(); // big blind checks
    expect(h.street, PokerStreet.flop);
    expect(h.board.length, 3);
    expect(h.toAct, 1, reason: 'the non-button acts first after the flop');
    for (var i = 0; i < 6; i++) {
      h.checkOrCall();
    }
    expect(h.over, isTrue);
    expect(h.endedByFold, isFalse);
  });

  test('bots make legal choices', () {
    final rng = math.Random(5);
    for (final bot in PokerBot.all) {
      for (var n = 0; n < 40; n++) {
        final h = HoldemHand(stacks: <int>[300, 300], button: n % 2, rng: rng);
        var guard = 0;
        while (!h.over && guard++ < 60) {
          final choice = bot.decide(h, rng);
          expect(choice.equity, inInclusiveRange(0.0, 1.0));
          if (choice.act == PokerAct.fold) expect(h.toCall(h.toAct), greaterThan(0), reason: 'never folds a free check');
          switch (choice.act) {
            case PokerAct.fold:
              h.fold();
            case PokerAct.check:
            case PokerAct.call:
              h.checkOrCall();
            case PokerAct.raise:
              h.raiseTo(choice.raiseTo);
          }
        }
        expect(h.over, isTrue);
        expect(h.stacks[0] + h.stacks[1], 600);
      }
    }
  });

  test('drill questions are well formed', () {
    final rng = math.Random(9);
    for (final drill in PokerDrill.values) {
      for (var i = 0; i < 25; i++) {
        final q = PokerQuestion.make(drill, rng);
        expect(q.correct, inInclusiveRange(0, q.options.length - 1));
        expect(q.options.toSet().length, q.options.length, reason: '${drill.name}: ${q.options}');
        final all = <int>[...q.yours, ...q.theirs, ...q.board];
        expect(all.toSet().length, all.length, reason: 'no card dealt twice');
        expect(q.explain, isNotEmpty);
        if (drill == PokerDrill.outs) {
          final (f, s) = Poker.drawOuts(<int>[...q.yours, ...q.board]);
          expect(q.options[q.correct], '${f + s} outs');
        }
      }
    }
  });

  test('starting-hand guide', () {
    expect(Poker.playable(cards('As Ad')[0], cards('As Ad')[1], late: false), isTrue);
    final sevenTwo = cards('7c 2d');
    expect(Poker.playable(sevenTwo[0], sevenTwo[1], late: true), isFalse);
    final small = cards('4c 4d');
    expect(Poker.playable(small[0], small[1], late: false), isFalse);
    expect(Poker.playable(small[0], small[1], late: true), isTrue);
    expect(Poker.startingName(cards('Ks Qs')[0], cards('Ks Qs')[1]), 'King-Queen suited');
  });

  test('poker results and drill bests are saved', () {
    final a = GameState(missionsOn: false);
    a.recordCase('tips', 3); // 50 IP
    a.settlePoker(net: 40, won: true, pot: 80);
    a.settlePoker(net: -30, won: false, pot: 60);
    expect(a.insightPoints, 60);
    expect(a.reportPokerDrill(PokerDrill.outs.name, 7), isTrue);
    expect(a.reportPokerDrill(PokerDrill.outs.name, 5), isFalse);
    final saved = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    a.dispose();
    final b = GameState()..restoreFrom(saved);
    expect(b.pokerStats, <int>[2, 1, 10, 80]);
    expect(b.pokerBest[PokerDrill.outs.name], 7);
    expect(b.insightPoints, 60 + 12 * GameState.pokerDrillIp);
    b.dispose();
  });
}
