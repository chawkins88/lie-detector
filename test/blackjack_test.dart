import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cold_reading/main.dart';

PlayingCard c(String rank) => PlayingCard(rank, '♠');

void main() {
  test('hand totals', () {
    expect(Blackjack.handValue(<PlayingCard>[c('A'), c('K')]).total, 21);
    expect(Blackjack.isBlackjack(<PlayingCard>[c('A'), c('K')]), isTrue);
    expect(Blackjack.handValue(<PlayingCard>[c('A'), c('6')]), (total: 17, soft: true));
    expect(Blackjack.handValue(<PlayingCard>[c('A'), c('A'), c('9')]).total, 21);
    expect(Blackjack.handValue(<PlayingCard>[c('A'), c('6'), c('K')]), (total: 17, soft: false));
    expect(Blackjack.handValue(<PlayingCard>[c('K'), c('Q'), c('5')]).total, 25);
  });

  test('basic strategy advice', () {
    expect(Blackjack.advice(<PlayingCard>[c('6'), c('5')], c('6'), canDouble: true), 'Double');
    expect(Blackjack.advice(<PlayingCard>[c('6'), c('5')], c('6'), canDouble: false), 'Hit');
    expect(Blackjack.advice(<PlayingCard>[c('10'), c('6')], c('K'), canDouble: true), 'Hit');
    expect(Blackjack.advice(<PlayingCard>[c('10'), c('6')], c('5'), canDouble: true), 'Stand');
    expect(Blackjack.advice(<PlayingCard>[c('10'), c('2')], c('4'), canDouble: true), 'Stand');
    expect(Blackjack.advice(<PlayingCard>[c('10'), c('2')], c('2'), canDouble: true), 'Hit');
    expect(Blackjack.advice(<PlayingCard>[c('A'), c('7')], c('9'), canDouble: true), 'Hit');
    expect(Blackjack.advice(<PlayingCard>[c('A'), c('7')], c('2'), canDouble: true), 'Stand');
    expect(Blackjack.advice(<PlayingCard>[c('A'), c('7')], c('4'), canDouble: false), 'Stand');
    expect(Blackjack.advice(<PlayingCard>[c('10'), c('8')], c('A'), canDouble: true), 'Stand');
  });

  test('bets and payouts move IP and are saved', () {
    final g = GameState(missionsOn: false);
    g.recordCase('tips', 3); // 50 IP to play with
    expect(g.insightPoints, 50);
    g.placeBet(20);
    expect(g.insightPoints, 30);
    g.settleBlackjack(staked: 20, returned: 50); // blackjack pays 3:2
    expect(g.insightPoints, 80);
    g.placeBet(10);
    g.settleBlackjack(staked: 10, returned: 0);
    expect(g.insightPoints, 70);
    expect(g.blackjackStats, <int>[2, 20, 30]);

    final saved = jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>;
    g.dispose();
    final h = GameState()..restoreFrom(saved);
    expect(h.blackjackStats, <int>[2, 20, 30]);
    expect(h.insightPoints, 70);
    h.dispose();
  });
}
