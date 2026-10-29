// ════════════════════════════════════════════════════════════════════════════
//  Cold Reading
//  A Duolingo-style trainer for reading people, spotting deception and
//  mastering statement analysis.
//
//  • Single file, no third-party packages, no network, all state in memory.
//  • Run:  flutter create cold_reading
//          replace cold_reading/lib/main.dart with this file
//          flutter run
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.open();
  runApp(ColdReadingApp(store: store));
}

/// Days since a fixed epoch, by the calendar (immune to DST hour shifts).
int dayIndex([DateTime? when]) {
  final t = when ?? DateTime.now();
  return DateTime.utc(t.year, t.month, t.day).difference(DateTime.utc(2024)).inDays;
}

int _readInt(Object? value, int fallback) => value is int ? value : fallback;

void _readCounts<K>(Object? raw, Map<K, int> into, Map<String, K> byName) {
  if (raw is! Map) return;
  raw.forEach((Object? key, Object? value) {
    final k = byName[key];
    if (k != null && value is int) into[k] = value;
  });
}

// ════════════════════════════════════════════════════════════════════════════
//  PERSISTENCE: one JSON blob in on-device storage
// ════════════════════════════════════════════════════════════════════════════

class AppStore {
  AppStore._(this._prefs);

  static const String _key = 'cold_reading_state_v1';
  final SharedPreferences? _prefs;

  static Future<AppStore> open() async {
    try {
      return AppStore._(await SharedPreferences.getInstance());
    } catch (_) {
      return AppStore._(null); // storage unavailable: run in memory
    }
  }

  factory AppStore.memoryOnly() => AppStore._(null);

  Map<String, dynamic>? load() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void save(Map<String, Object?> data) {
    _prefs?.setString(_key, jsonEncode(data));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  THEME
// ════════════════════════════════════════════════════════════════════════════

class Palette {
  Palette._();

  static const Color background = Color(0xFF131F24);
  static const Color surface = Color(0xFF1C2B33);
  static const Color surfaceHigh = Color(0xFF243640);
  static const Color border = Color(0xFF37464F);
  static const Color textPrimary = Color(0xFFF1F7FB);
  static const Color textMuted = Color(0xFF9CB0BC);

  static const Color green = Color(0xFF58CC02);
  static const Color red = Color(0xFFFF4B4B);
  static const Color blue = Color(0xFF1CB0F6);
  static const Color purple = Color(0xFFCE82FF);
  static const Color orange = Color(0xFFFF9600);
  static const Color gold = Color(0xFFFFC800);
  static const Color highlight = Color(0xFFFFE066);
  static const Color pink = Color(0xFFFF86D0);
  static const Color teal = Color(0xFF00CD9C);
  static const Color indigo = Color(0xFF8C9EFF);
  static const Color lime = Color(0xFFA5D63A);

  static const Color locked = Color(0xFF3B4A52);
  static const Color lockedIcon = Color(0xFF6F8591);

  // Feedback sheets.
  static const Color feedbackGreen = Color(0xFF2FA83A);
  static const Color feedbackRed = Color(0xFF9B1C1C);
}

Color darken(Color color, [double amount = 0.18]) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

const Map<String, String> kEmotionEmoji = <String, String>{
  'Contempt': '😏',
  'Happiness': '😊',
  'Disgust': '🤢',
  'Surprise': '😮',
  'Fear': '😨',
  'Anger': '😠',
  'Sadness': '😢',
  'Duping Delight': '😈',
};

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

/// The four question layouts. Each one maps to a curriculum level.
enum ChallengeType {
  baseline('Baseline Anomaly', Icons.timeline),
  microExpression('Micro-Expression Flash', Icons.face),
  cluster('Cluster Builder', Icons.hub),
  statement('Statement Analysis', Icons.format_quote),
  scenario('Investigator Decision', Icons.policy);

  const ChallengeType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The specific skill a challenge tests. Misses are tracked per flag to build
/// the user's weakness calibration profile.
enum Flag {
  vocalShift('Vocal Shift', ChallengeType.baseline),
  gestureShift('Gesture Suppression', ChallengeType.baseline),
  pacifying('Pacifying Behavior', ChallengeType.baseline),
  ocularShift('Eye Behavior Shift', ChallengeType.baseline),
  postureShift('Posture & Freeze Shift', ChallengeType.baseline),
  contempt('Contempt', ChallengeType.microExpression),
  fear('Fear', ChallengeType.microExpression),
  disgust('Disgust', ChallengeType.microExpression),
  anger('Anger', ChallengeType.microExpression),
  surprise('Surprise', ChallengeType.microExpression),
  sadness('Sadness', ChallengeType.microExpression),
  dupingDelight('Duping Delight', ChallengeType.microExpression),
  clusterBuilding('Behavioral Clusters', ChallengeType.cluster),
  pronounDrop('Pronoun Drop', ChallengeType.statement),
  temporalGap('Temporal Gap', ChallengeType.statement),
  tenseShift('Verb Tense Shift', ChallengeType.statement),
  nonAnswer('Non-Answer Assertion', ChallengeType.statement),
  happiness('Genuine Happiness', ChallengeType.microExpression),
  qualifier('Credibility Qualifier', ChallengeType.statement),
  distancing('Distancing Language', ChallengeType.statement),
  minimizing('Minimizing Language', ChallengeType.statement),
  stalling('Stalling Tactic', ChallengeType.statement),
  truthMarkers('Truthful Account Markers', ChallengeType.cluster),
  openQuestion('Question Design', ChallengeType.scenario),
  probeHotSpot('Probing Hot Spots', ChallengeType.scenario),
  contamination('Avoiding Contamination', ChallengeType.scenario),
  rapport('Rapport & Pressure', ChallengeType.scenario),
  cleanBaseline('Reading a Clean Baseline', ChallengeType.baseline),
  cleanStatement('Spotting Truthful Statements', ChallengeType.statement);

  const Flag(this.label, this.family);
  final String label;
  final ChallengeType family;
}

class Challenge {
  Challenge({
    required this.id,
    required this.level,
    required this.type,
    required this.flag,
    required this.prompt,
    required this.context,
    required this.options,
    required this.correct,
    required this.insight,
    this.highLoad = false,
  });

  /// Level 1 — pick the moment the baseline breaks.
  factory Challenge.baseline({
    required String id,
    required Flag flag,
    required String context,
    required List<String> moments,
    required int answer,
    required String insight,
    bool highLoad = false,
  }) =>
      Challenge(
        id: id,
        level: 1,
        type: ChallengeType.baseline,
        flag: flag,
        prompt: 'Which moment breaks the baseline, if any?',
        context: context,
        options: moments,
        correct: <int>{answer},
        insight: insight,
        highLoad: highLoad,
      );

  /// Emotions most often confused with each one, used to pad answer choices.
  static const Map<String, List<String>> _confusable = <String, List<String>>{
    'Contempt': <String>['Disgust', 'Duping Delight', 'Anger', 'Happiness'],
    'Fear': <String>['Surprise', 'Sadness', 'Anger', 'Disgust'],
    'Disgust': <String>['Contempt', 'Anger', 'Sadness', 'Fear'],
    'Anger': <String>['Disgust', 'Contempt', 'Fear', 'Sadness'],
    'Surprise': <String>['Fear', 'Happiness', 'Duping Delight', 'Sadness'],
    'Sadness': <String>['Fear', 'Contempt', 'Disgust', 'Anger'],
    'Duping Delight': <String>['Happiness', 'Contempt', 'Surprise', 'Disgust'],
    'Happiness': <String>['Duping Delight', 'Contempt', 'Surprise', 'Fear'],
  };

  static List<String> _sixEmotions(List<String> emotions, int answer) {
    final result = List<String>.of(emotions);
    for (final e in <String>[...?_confusable[emotions[answer]], ...kEmotionEmoji.keys]) {
      if (result.length >= 6) break;
      if (!result.contains(e)) result.add(e);
    }
    return result;
  }

  /// Level 2 — flash card describing a facial movement.
  factory Challenge.micro({
    required String id,
    required Flag flag,
    required String card,
    required List<String> emotions,
    required int answer,
    required String insight,
    bool highLoad = false,
  }) =>
      Challenge(
        id: id,
        level: 2,
        type: ChallengeType.microExpression,
        flag: flag,
        prompt: 'Which emotion just leaked?',
        context: card,
        options: _sixEmotions(emotions, answer),
        correct: <int>{answer},
        insight: insight,
        highLoad: highLoad,
      );

  /// Level 3 — pick exactly three genuine stress indicators.
  factory Challenge.cluster({
    required String id,
    required String profile,
    required List<String> indicators,
    required Set<int> answers,
    required String insight,
    bool highLoad = false,
    int level = 3,
    Flag flag = Flag.clusterBuilding,
    String prompt = 'Tap exactly 3 genuine stress indicators to build the cluster.',
  }) =>
      Challenge(
        id: id,
        level: level,
        type: ChallengeType.cluster,
        flag: flag,
        prompt: prompt,
        context: profile,
        options: indicators,
        correct: answers,
        insight: insight,
        highLoad: highLoad,
      );

  /// Level 4 — tap the sentence that holds the structural flaw.
  factory Challenge.statement({
    required String id,
    required Flag flag,
    required String question,
    required List<String> sentences,
    required int answer,
    required String insight,
    bool highLoad = false,
    int level = 4,
    String prompt = 'Tap the sentence with the structural flaw, if there is one.',
  }) =>
      Challenge(
        id: id,
        level: level,
        type: ChallengeType.statement,
        flag: flag,
        prompt: prompt,
        context: question,
        options: sentences,
        correct: <int>{answer},
        insight: insight,
        highLoad: highLoad,
      );

  /// Level 7 — choose the best investigative move.
  factory Challenge.scenario({
    required String id,
    required Flag flag,
    required String context,
    required List<String> moves,
    required int answer,
    required String insight,
    bool highLoad = false,
  }) =>
      Challenge(
        id: id,
        level: 7,
        type: ChallengeType.scenario,
        flag: flag,
        prompt: 'What\'s your best next move?',
        context: context,
        options: moves,
        correct: <int>{answer},
        insight: insight,
        highLoad: highLoad,
      );

  final String id;
  final int level;
  final ChallengeType type;
  final Flag flag;
  final String prompt;

  /// Scenario text: baseline profile, flash card, behavior log, or the
  /// interviewer's question, depending on [type].
  final String context;
  final List<String> options;
  final Set<int> correct;
  final String insight;

  /// True for "High Cognitive Load" variants where the flag is buried inside
  /// ordinary dialogue and distractors.
  final bool highLoad;

  /// Answer index for "nothing here: no deception flag".
  static const int clean = -1;

  /// Baseline and statement questions always offer the "nothing here" choice,
  /// so its presence never hints at the answer.
  bool get offersClean => type == ChallengeType.baseline || type == ChallengeType.statement;
  bool get isClean => correct.contains(clean);

  String get cleanLabel {
    if (type == ChallengeType.baseline) return 'Nothing here: every moment stays on baseline.';
    if (level == 8) return 'Nothing here: this message reads as truthful.';
    return 'Nothing here: this statement reads as truthful.';
  }

  int get requiredSelections => correct.length;
  bool get isMultiSelect => type == ChallengeType.cluster;

  String get correctAnswerText {
    if (isClean) return cleanLabel;
    final indices = correct.toList()..sort();
    final lines = indices.map((i) => switch (type) {
          ChallengeType.statement => 'Sentence ${i + 1}: "${options[i]}"',
          ChallengeType.cluster => '• ${options[i]}',
          ChallengeType.baseline => 'Moment ${String.fromCharCode(65 + i)}: ${options[i]}',
          ChallengeType.microExpression => options[i],
          ChallengeType.scenario => options[i],
        });
    return lines.join('\n');
  }

  /// A copy with the answer order randomized, so position never gives the
  /// answer away. Statements keep their order: the sentences tell a story.
  Challenge shuffled(math.Random rng) {
    if (type == ChallengeType.statement) return this;
    final order = List<int>.generate(options.length, (i) => i)..shuffle(rng);
    return Challenge(
      id: id,
      level: level,
      type: type,
      flag: flag,
      prompt: prompt,
      context: context,
      options: <String>[for (final i in order) options[i]],
      correct: <int>{
        if (correct.contains(clean)) clean,
        for (var n = 0; n < order.length; n++)
          if (correct.contains(order[n])) n,
      },
      insight: insight,
      highLoad: highLoad,
    );
  }
}

class LevelInfo {
  const LevelInfo(this.number, this.title, this.subtitle, this.color, this.type);
  final int number;
  final String title;
  final String subtitle;
  final Color color;
  final ChallengeType type;
}

class SkillNode {
  const SkillNode({
    required this.id,
    required this.level,
    required this.title,
    required this.description,
    required this.icon,
    this.isReview = false,
    this.questLength = 4,
  });

  final String id;
  final int level;
  final String title;
  final String description;
  final IconData icon;

  /// Review nodes mix every level up to [level] and are weighted toward the
  /// user's weakest flags.
  final bool isReview;
  final int questLength;
}

enum NodeStatus { locked, current, completed }

// ════════════════════════════════════════════════════════════════════════════
//  CURRICULUM DATA
// ════════════════════════════════════════════════════════════════════════════

class Curriculum {
  Curriculum._();

  static const List<LevelInfo> levels = <LevelInfo>[
    LevelInfo(1, 'The Baseline', 'Intro to the grammar of behavior', Palette.green, ChallengeType.baseline),
    LevelInfo(2, 'Micro-Expressions & Asymmetry', 'Catch emotion leaking in under a second', Palette.blue,
        ChallengeType.microExpression),
    LevelInfo(3, 'Cluster Decoding', 'Build behavioral sentences, not single words', Palette.purple,
        ChallengeType.cluster),
    LevelInfo(4, 'Statement Analysis', 'The Master Class: the structure of a lie', Palette.orange,
        ChallengeType.statement),
    LevelInfo(5, 'Verbal Tells', 'Qualifiers, distancing, minimizing and stalling', Palette.pink,
        ChallengeType.statement),
    LevelInfo(6, 'Truth Signals', 'Recognize what real memories sound like', Palette.teal, ChallengeType.cluster),
    LevelInfo(7, 'Interview Tactics', 'Ask the question that gets the truth', Palette.indigo, ChallengeType.scenario),
    LevelInfo(8, 'Digital Deception', 'Texts, emails, reviews and DMs', Palette.lime, ChallengeType.statement),
  ];

  static LevelInfo level(int number) => levels[number - 1];

  static const List<SkillNode> nodes = <SkillNode>[
    SkillNode(
      id: 'l1a',
      level: 1,
      title: 'Resting State',
      description: 'Learn to log a person\'s normal voice, hands, eyes and posture before judging anything.',
      icon: Icons.self_improvement,
    ),
    SkillNode(
      id: 'l1b',
      level: 1,
      title: 'Anomaly Spotting',
      description: 'Pinpoint the exact moment behavior departs from baseline.',
      icon: Icons.radar,
    ),
    SkillNode(
      id: 'r1',
      level: 1,
      title: 'Baseline Review',
      description: 'Adaptive review weighted toward the baseline signals you miss most.',
      icon: Icons.fitness_center,
      isReview: true,
    ),
    SkillNode(
      id: 'l2a',
      level: 2,
      title: 'Flash Faces',
      description: 'Rapid flash cards: name the universal emotion from the muscle movement.',
      icon: Icons.face,
    ),
    SkillNode(
      id: 'l2b',
      level: 2,
      title: 'Asymmetry',
      description: 'One-sided and masked expressions: contempt, duping delight and leakage.',
      icon: Icons.contrast,
    ),
    SkillNode(
      id: 'r2',
      level: 2,
      title: 'Expression Review',
      description: 'Mixed review of baselines and micro-expressions, tuned to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
    ),
    SkillNode(
      id: 'l3a',
      level: 3,
      title: 'Stress Signals',
      description: 'Separate real stress indicators from habits, noise and myths.',
      icon: Icons.hub,
    ),
    SkillNode(
      id: 'l3b',
      level: 3,
      title: 'Cluster Decoding',
      description: 'Build valid three-signal behavioral clusters from a suspect profile.',
      icon: Icons.account_tree,
    ),
    SkillNode(
      id: 'r3',
      level: 3,
      title: 'Cluster Review',
      description: 'Everything so far, weighted toward the flags you misread most.',
      icon: Icons.fitness_center,
      isReview: true,
    ),
    SkillNode(
      id: 'l4a',
      level: 4,
      title: 'Pronouns & Time',
      description: 'Spot pronoun drops and temporal gaps in written statements.',
      icon: Icons.record_voice_over,
    ),
    SkillNode(
      id: 'l4b',
      level: 4,
      title: 'The Master Class',
      description: 'Tense shifts and non-answer assertions: the structure of deception.',
      icon: Icons.gavel,
    ),
    SkillNode(
      id: 'r4',
      level: 4,
      title: 'Statement Review',
      description: 'Levels 1–4 mixed, weighted toward the flags you misread most.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 5,
    ),
    SkillNode(
      id: 'l5a',
      level: 5,
      title: 'Qualifiers & Oaths',
      description: '"To be honest", "I swear", "frankly": words that try to sound true.',
      icon: Icons.campaign,
    ),
    SkillNode(
      id: 'l5b',
      level: 5,
      title: 'Distance & Minimizing',
      description: '"That woman", "just a little", and repeating the question back.',
      icon: Icons.social_distance,
    ),
    SkillNode(
      id: 'r5',
      level: 5,
      title: 'Verbal Review',
      description: 'Levels 1–5 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 5,
    ),
    SkillNode(
      id: 'l6a',
      level: 6,
      title: 'Memory vs. Fiction',
      description: 'Real memories are messy: corrections, gaps and odd details.',
      icon: Icons.auto_stories,
    ),
    SkillNode(
      id: 'l6b',
      level: 6,
      title: 'Truth Markers',
      description: 'Separate what happened from credibility pitches.',
      icon: Icons.verified,
    ),
    SkillNode(
      id: 'r6',
      level: 6,
      title: 'Truth Review',
      description: 'Levels 1–6 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 5,
    ),
    SkillNode(
      id: 'l7a',
      level: 7,
      title: 'Opening Moves',
      description: 'Open questions, rapport and a clean baseline.',
      icon: Icons.forum,
    ),
    SkillNode(
      id: 'l7b',
      level: 7,
      title: 'Pressure & Probing',
      description: 'Dig into hot spots without leaking what you know.',
      icon: Icons.manage_search,
    ),
    SkillNode(
      id: 'r7',
      level: 7,
      title: 'Tactics Review',
      description: 'Levels 1–7 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 5,
    ),
    SkillNode(
      id: 'l8a',
      level: 8,
      title: 'Texts & Emails',
      description: 'Spot the tells in written messages.',
      icon: Icons.sms,
    ),
    SkillNode(
      id: 'l8b',
      level: 8,
      title: 'Reviews & Profiles',
      description: 'Fake reviews, slick DMs and polished excuses.',
      icon: Icons.alternate_email,
    ),
    SkillNode(
      id: 'exam',
      level: 8,
      title: 'Master Exam',
      description: 'The final adaptive exam across all eight levels, calibrated to your profile.',
      icon: Icons.emoji_events,
      isReview: true,
      questLength: 6,
    ),
  ];

  /// Fixed questions by id (used to replay saved mistakes).
  static final Map<String, Challenge> byId = <String, Challenge>{for (final c in challenges) c.id: c};

  static final List<Challenge> challenges = <Challenge>[
    // ── LEVEL 1 · THE BASELINE ─────────────────────────────────────────────
    Challenge.baseline(
      id: 'b1',
      flag: Flag.vocalShift,
      context: 'Marcus is questioned about cash missing from the office safe.\n\nBASELINE: Marcus speaks slowly in a low, even monotone. He rubs his eyes a lot (he says his contacts are dry) and keeps his hands on the table.',
      moments: <String>[
        'Asked if he took the money → slow and even, rubs his eyes: "No. I didn\'t take anything."',
        'Asked where he parked → voice jumps higher and quicker: "Side lot, by the gym."',
        'Asked who has a key → slow and low, hands flat on the table, names three people.',
        'Asked if he has money troubles → slow monotone, rubs his eyes: "Same as anybody."',
        'Asked about his manager → his phone buzzes; he glances at it, silences it, then answers slowly.',
      ],
      answer: 1,
      insight: 'The theft question got a calm, on-baseline "No", and eye rubbing is his normal habit. The break came on a side question: where he parked. Slips often show up on questions the person didn\'t prepare for, which is exactly why they\'re worth probing. His glance at the buzzing phone had an outside cause, so it isn\'t a signal.',
    ),
    Challenge.baseline(
      id: 'b2',
      flag: Flag.gestureShift,
      context: 'Dana is asked about leaked client files.\n\nBASELINE: Dana is an animated talker whose hands move constantly. She twirls her hair whenever she\'s thinking.',
      moments: <String>[
        'Asked if she leaked the files → hands sweep wide, a frown: "No. I didn\'t send them anywhere."',
        'Asked which laptop she uses → twirls her hair, then waves at the window as she answers.',
        'Asked when she logged off Friday → answers smoothly, but both hands go still in her lap.',
        'Asked who else had access → hands chop the air as she lists three coworkers by name.',
        'Asked about the client → stops to sneeze twice, apologizes, then gestures as usual.',
      ],
      answer: 2,
      insight: 'The direct question got Dana\'s usual big gestures. Her hands only froze on Friday\'s log-off time, a detail she may not want examined. Hair twirling is her thinking habit, so it doesn\'t count. The pause to sneeze had an outside cause, so it doesn\'t count.',
    ),
    Challenge.baseline(
      id: 'b3',
      flag: Flag.pacifying,
      context: 'Ray is interviewed about cash missing from his register.\n\nBASELINE: Ray sits calmly with his hands loosely folded. He scratches his beard whenever he stops to think.',
      moments: <String>[
        'Asked who closed the register → scratches his beard, thinks, then names his partner Luis.',
        'Asked if he took the cash → hands folded, steady: "No, I didn\'t. Check the camera."',
        'Asked about his lunch break → unfolds his hands and rubs the side of his neck.',
        'Asked if he\'s behind on rent → hands folded, a small laugh: "Isn\'t everyone?"',
        'Asked about his shift → the AC kicks on, he zips up his jacket, then refolds his hands.',
      ],
      answer: 2,
      insight: 'Neck rubbing is a pacifier, and it\'s new for Ray; the beard scratching is his normal thinking habit. The reaction came on the lunch-break question, not the accusation. Ask what happened at lunch. Zipping his jacket when the AC came on had an outside cause.',
    ),
    Challenge.baseline(
      id: 'b4',
      flag: Flag.ocularShift,
      context: 'Priya is asked about a meeting with a competitor.\n\nBASELINE: Priya blinks at a normal rate and holds steady eye contact. She glances up and to the side whenever she recalls a date.',
      moments: <String>[
        'Asked if she met with Halvorsen Corp → steady eye contact: "No, I\'ve never met them."',
        'Asked the date of the last sales meeting → glances up to the side, then answers.',
        'Asked who drove her to the airport → a burst of fast blinks, then steady eyes again.',
        'Asked about her bonus → steady gaze, normal blinks, calls it "honestly disappointing."',
        'Asked about her team → someone knocks; she looks at the door, then back, eyes steady again.',
      ],
      answer: 2,
      insight: 'Glancing up while recalling a date is her baseline. The blink burst came on who drove her to the airport, a side detail that may connect to the meeting. The direct denial was delivered on baseline. Looking at the door after a knock had an outside cause.',
    ),
    Challenge.baseline(
      id: 'b5',
      flag: Flag.postureShift,
      context: 'Tom is interviewed about a skipped safety inspection.\n\nBASELINE: Tom leans forward with both feet pointed at the interviewer. He has a bad back, so he shifts in his seat every few minutes.',
      moments: <String>[
        'Asked if he skipped the inspection → leans in and frowns: "No. I did it myself."',
        'Asked about his training → shifts in his seat, rubs his lower back, keeps leaning in.',
        'Asked who else was on site → stays leaning in, but both feet slide toward the door.',
        'Asked about the injured worker → leans in, open torso, names him and his crew.',
        'Asked about the weather that day → his chair squeaks and wobbles; he fixes it and leans back in.',
      ],
      answer: 2,
      insight: 'The seat shifting is his bad back, present all along. His feet turned to the exit only when asked who else was there, which suggests that\'s the uncomfortable part of the story. Adjusting a wobbly chair had an outside cause.',
    ),
    // High Cognitive Load · Level 1
    Challenge.baseline(
      id: 'b6',
      flag: Flag.vocalShift,
      highLoad: true,
      context: 'Elena is questioned about an unauthorized login on Saturday night.\n\nBASELINE: Elena talks fast and high-pitched and laughs constantly, even about serious subjects.',
      moments: <String>[
        'Asked about the login → rapid and high, laughing: "Wasn\'t me, I can barely use email!"',
        'Asked about her weekend → still quick, but a beat lower, and no laugh this time.',
        'Asked if anyone knows her password → fast and high, with a giggle: "Only my cat."',
        'Asked if she was online at 2 AM → fast and giggling: "At 2 AM? I\'m always asleep!"',
        'Asked about her coworkers → her coffee spills; she yelps, mops it up, laughing as usual.',
      ],
      answer: 1,
      insight: 'For a fast, laughing baseline, the anomaly runs the other way: lower and no laugh. It landed on her weekend, when the login happened, not on the direct questions she seemed ready for. The spilled coffee was an outside cause, not a signal.',
    ),
    Challenge.baseline(
      id: 'b7',
      flag: Flag.ocularShift,
      highLoad: true,
      context: 'Kenji is asked about deleted server logs.\n\nBASELINE: Kenji avoids eye contact, looks down while he thinks and pushes his glasses up every few sentences.',
      moments: <String>[
        'Asked if he ran the delete command → eyes on the table, pushes up his glasses: "No."',
        'Asked about the backup schedule → glances away, a long pause, adjusts his glasses.',
        'Asked what time he left Tuesday → looks up and holds her gaze the whole answer.',
        'Asked about the deleted logs → stares at his hands, then pushes his glasses up twice.',
        'Asked about his team lead → an alarm sounds outside; he looks at the window, then back down.',
      ],
      answer: 2,
      insight: 'Overcompensation. For someone who never makes eye contact, a sudden held gaze is the anomaly, and it came on a time question, not the accusation. People sometimes stare to look honest on the detail they rehearsed. Looking up at an alarm outside had an outside cause.',
    ),
    Challenge.baseline(
      id: 'b8',
      flag: Flag.postureShift,
      highLoad: true,
      context: 'Sofia is asked about a client meeting that never appeared on the calendar.\n\nBASELINE: Sofia rocks gently, twirls her necklace and shifts position every minute or so.',
      moments: <String>[
        'Asked who she met Thursday → rocks gently, twirling her necklace: "Just a client lunch."',
        'Asked which restaurant they went to → answers calmly, hands in her lap, perfectly still.',
        'Asked why it isn\'t on the calendar → shifts in her seat: "I forgot to add it, sorry."',
        'Asked about her sales numbers → rocks, laughs and changes position twice while answering.',
        'Asked about her commute → her phone rings; she stops rocking to silence it, then starts again.',
      ],
      answer: 1,
      insight: 'The freeze response. A restless person going still looks calm, which is exactly why it\'s easy to miss. It came on the restaurant question: a specific detail that can be checked. Stopping to silence her phone had an outside cause, unlike the freeze.',
    ),
    Challenge.baseline(
      id: 'b9',
      flag: Flag.pacifying,
      highLoad: true,
      context: 'Victor is asked about a duplicated invoice.\n\nBASELINE: Victor is loud and confident. He sits wide, points while he talks and tugs at his tight shirt collar every few minutes.',
      moments: <String>[
        'Asked if he approved the second payment → points at her, tugs his collar: "Nope. Not me."',
        'Asked about the vendor → leans back, arms wide, and loudly calls them "total amateurs."',
        'Asked when he last spoke to the vendor → puffs out his cheeks and slowly exhales first.',
        'Asked if he\'d take a polygraph → laughs loudly, arms wide: "Bring it. Any day."',
        'Asked about the budget → coughs hard, takes a long drink of water, then booms on as usual.',
      ],
      answer: 2,
      insight: 'Collar tugging is Victor\'s baseline (tight shirts), so the "Nope" with a tug means nothing. The new behavior is the cheek-puff exhale, a stress release, on when he last spoke to the vendor. The coughing fit and drink of water had an outside cause.',
    ),

    // ── LEVEL 2 · MICRO-EXPRESSIONS & ASYMMETRY ────────────────────────────
    Challenge.micro(
      id: 'm1',
      flag: Flag.contempt,
      card: 'The LEFT corner of the mouth tightens and pulls up and back for half a second. '
          'The right side of the face stays completely neutral.',
      emotions: <String>['Happiness', 'Contempt', 'Disgust', 'Surprise'],
      answer: 1,
      insight: 'Contempt is the only universal expression that appears on one side of the face. It signals moral '
          'superiority ("I\'m better than you"), often toward the person asking the questions.',
    ),
    Challenge.micro(
      id: 'm2',
      flag: Flag.fear,
      card: 'Eyebrows shoot up AND pull together. Upper eyelids rise, exposing white above the iris. '
          'Lips stretch sideways toward the ears.',
      emotions: <String>['Surprise', 'Anger', 'Fear', 'Sadness'],
      answer: 2,
      insight: 'Fear vs. surprise: both raise the brows, but fear pulls them together and stretches the lips '
          'horizontally. In surprise the brows stay curved and the jaw drops loosely. Fear prepares the body to flee.',
    ),
    Challenge.micro(
      id: 'm3',
      flag: Flag.disgust,
      card: 'The nose wrinkles and the upper lip rises, flashing for about 0.3 seconds before the face returns '
          'to neutral.',
      emotions: <String>['Disgust', 'Anger', 'Contempt', 'Sadness'],
      answer: 0,
      insight: 'Disgust wrinkles the nose and raises the upper lip, an ancient reflex for rejecting bad food that we '
          'extend to people and ideas. A disgust flash when a name is mentioned shows how the person really feels.',
    ),
    Challenge.micro(
      id: 'm4',
      flag: Flag.anger,
      card: 'Brows pull down and together. Lips press tightly and narrow. Lower eyelids tense into a hard stare.',
      emotions: <String>['Fear', 'Sadness', 'Disgust', 'Anger'],
      answer: 3,
      insight: 'Anger lowers and knits the brows, tenses the lower lids and narrows the lips. Narrowing of the red '
          'margin of the lips is one of the earliest signs, often before the person knows they\'re angry.',
    ),
    Challenge.micro(
      id: 'm5',
      flag: Flag.surprise,
      card: 'Brows rise into high curved arches, eyes widen and the jaw drops open loosely. It\'s gone in under '
          'a second.',
      emotions: <String>['Surprise', 'Fear', 'Happiness', 'Contempt'],
      answer: 0,
      insight: 'Genuine surprise is the briefest emotion, under one second. Surprise that lingers is usually performed. '
          'Watch for "fake surprise" when someone hears news they already knew.',
    ),
    Challenge.micro(
      id: 'm6',
      flag: Flag.sadness,
      card: 'The inner corners of the eyebrows angle upward. Lip corners pull down and the chin pushes up slightly.',
      emotions: <String>['Contempt', 'Sadness', 'Anger', 'Fear'],
      answer: 1,
      insight: 'The inner-brow raise of sadness uses a "reliable muscle": very few people can make it on purpose. '
          'That makes it hard to fake, and its absence during claimed grief is worth noting.',
    ),
    // High Cognitive Load · Level 2
    Challenge.micro(
      id: 'm7',
      flag: Flag.dupingDelight,
      highLoad: true,
      card: 'A suspect says: "I feel terrible about what happened to the shop." Mid-sentence, both lip corners '
          'flicker upward for 0.2 seconds, then are quickly pressed flat.',
      emotions: <String>['Sadness', 'Duping Delight', 'Contempt', 'Fear'],
      answer: 1,
      insight: 'Duping delight, the thrill of getting away with a lie, leaks as a suppressed smile at a moment that '
          'calls for distress. The quick pressing-flat shows the person trying to control it.',
    ),
    Challenge.micro(
      id: 'm8',
      flag: Flag.contempt,
      highLoad: true,
      card: 'A witness smiles warmly while saying, "Of course, happy to help." Both lip corners rise, but the RIGHT '
          'corner pulls higher and holds longer, with a dimple forming only on that side.',
      emotions: <String>['Happiness', 'Duping Delight', 'Contempt', 'Disgust'],
      answer: 2,
      insight: 'A smile can mask contempt. The tell is asymmetry: one corner pulled tighter and higher, with a '
          'one-sided dimple. Genuine happiness is symmetrical and crinkles the eyes (the Duchenne marker).',
    ),
    Challenge.micro(
      id: 'm9',
      flag: Flag.fear,
      highLoad: true,
      card: 'An applicant answers calmly behind a fixed smile. For a split second the brows draw up and together and '
          'the lower lip stretches sideways, while the smile never leaves the mouth.',
      emotions: <String>['Surprise', 'Happiness', 'Fear', 'Sadness'],
      answer: 2,
      insight: 'Masking: the mouth is easy to control, the forehead is not. Brows pulled up and together plus a '
          'horizontal lip stretch is fear leaking through a social smile.',
    ),
    Challenge.micro(
      id: 'm10',
      flag: Flag.anger,
      highLoad: true,
      card: 'An employee says pleasantly, "No problem at all, I\'m happy to cover the weekend shift." As he '
          'finishes, the red of his lips thins for 0.4 seconds and his lower eyelids tighten.',
      emotions: <String>['Anger', 'Disgust', 'Contempt', 'Sadness'],
      answer: 0,
      insight: 'The words say "happy", the face says "angry". Lip thinning and lower-lid tightening are anger leaks. '
          'When words and face conflict, trust the face, then ask about the conflict.',
    ),

    // ── LEVEL 3 · CLUSTER DECODING ─────────────────────────────────────────
    Challenge.cluster(
      id: 'c1',
      profile: 'Jordan, a warehouse supervisor, is questioned about missing inventory. During small talk he\'s '
          'relaxed and chatty. Then he\'s asked about the night shift log.',
      indicators: <String>[
        'Arms crossed, as they\'ve been since he sat down in the cold room',
        'Starts repeating each question back before answering',
        'Rubs his neck and collarbone',
        'Wears a company hoodie',
        'Feet swivel toward the exit, only during this topic',
        'Scratched his nose once during small talk',
      ],
      answers: <int>{1, 2, 4},
      insight: 'A cluster is 3+ indicators that (1) break from baseline, (2) appear together and (3) follow the same '
          'question. Repeating questions buys thinking time, neck rubbing self-soothes and the feet show a wish to '
          'leave. Crossed arms in a cold room and a single nose scratch are noise.',
    ),
    Challenge.cluster(
      id: 'c2',
      profile: 'Lena, an accountant, is asked about a wire transfer nobody approved. She was calm and smiling '
          'through the warm-up questions.',
      indicators: <String>[
        'Lips compress into a thin line right after the question',
        'Writes notes with her left hand, as she has all meeting',
        'Blink rate triples while she answers',
        'Drinks coffee, as she did all morning',
        'Voice pitch rises noticeably',
        'Smiled when greeted at the door',
      ],
      answers: <int>{0, 2, 4},
      insight: 'Lip compression, a blink-rate surge and a pitch rise all appear at the same trigger and all break '
          'baseline. Habits she showed all morning (coffee, note-taking, a greeting smile) carry no information.',
    ),
    Challenge.cluster(
      id: 'c3',
      profile: 'Marco, a college applicant, is asked whether he wrote his admission essay himself. In the warm-up '
          'he tapped his foot constantly and chatted easily.',
      indicators: <String>[
        'Keeps tapping his foot, just as he did in the warm-up',
        'Covers his mouth with his hand while answering',
        'Is wearing a borrowed suit that\'s slightly too big',
        'Leans his whole torso away from the interviewer',
        'Clears his throat repeatedly, only on this topic',
        'Holds eye contact steadily while he answers',
      ],
      answers: <int>{1, 3, 4},
      insight: 'Mouth covering (blocking the words), torso distancing and topic-linked throat clearing form the '
          'cluster. Foot tapping is his baseline, and eye contact proves nothing either way: "liars look away" is a myth.',
    ),
    Challenge.cluster(
      id: 'c4',
      profile: 'Hannah, a babysitter, is asked about a broken antique vase. She\'s a fast talker who gestures a lot '
          'and fidgeted with her phone in the waiting room.',
      indicators: <String>[
        'Hands freeze mid-gesture',
        'Looks up and to the left while remembering',
        'Lips pull inward until they disappear',
        'Talks quickly',
        'Answers after a 4-second pause (her baseline is about 1 second)',
        'Fidgets with her phone',
      ],
      answers: <int>{0, 2, 4},
      insight: 'Gesture freezing, lip disappearance and a big jump in response time are the cluster. "Looking up-left '
          'means lying" comes from NLP eye-accessing claims that research does not support. Fast talk and phone '
          'fidgeting are her baseline.',
    ),
    Challenge.cluster(
      id: 'c5',
      profile: 'Greg is asked whether he threw the first punch in a bar fight. The interview room is hot and he\'s '
          'been sweating lightly since he arrived.',
      indicators: <String>[
        'Visible jaw clenching',
        'Light sweat on his forehead',
        'Nostrils flare',
        'He is tall and broad-shouldered',
        'His hand moves to cover the dip at the base of his throat',
        'Says "um" about as often as during small talk',
      ],
      answers: <int>{0, 2, 4},
      insight: 'Jaw clenching and nostril flaring are arousal signals; covering the suprasternal notch (the dip at the '
          'base of the neck) is a protective pacifier. The sweat has an environmental cause, and filler words at '
          'baseline rate tell you nothing.',
    ),
    // High Cognitive Load · Level 3
    Challenge.cluster(
      id: 'c6',
      highLoad: true,
      profile: 'Detective: "So how was the commute?" Ava laughs, touches her hair and checks her phone (she\'s done '
          'all three repeatedly since she arrived). "Brutal, as always!"\n\n'
          'Detective: "Were you at the office after 9 PM on the 14th?" Ava\'s laughter cuts off. "Me? At the office? '
          'No." She touches her hair, lifts her water bottle and holds it in front of her chest, and her blinking '
          'speeds up sharply. She glances at her phone.',
      indicators: <String>[
        'Her laughter stops abruptly',
        'She touches her hair',
        'She holds the water bottle in front of her chest',
        'She checks her phone',
        'Her blink rate surges',
        'She says the word "No"',
      ],
      answers: <int>{0, 2, 4},
      insight: 'In a noisy, fidgety baseline the cluster hides among habits. The cut-off laugh, the bottle used as a '
          'barrier (object blocking) and the blink surge are all new and all triggered by the 9 PM question. Hair '
          'touching and phone checks were there all along, and a denial alone is not a stress signal.',
    ),
    Challenge.cluster(
      id: 'c7',
      highLoad: true,
      profile: 'Ben has a head cold and coughs every few minutes. The room is cold, so he\'s kept his arms crossed '
          'since he sat down, and he looks away whenever he thinks.\n\n'
          'Asked whether he signed his manager\'s name on the expense form, Ben looks away, coughs, then swallows '
          'hard twice. He pulls his shirt collar away from his neck, and his voice cracks on the word "never."',
      indicators: <String>[
        'Arms crossed',
        'Swallows hard twice',
        'Coughs',
        'Pulls his collar away from his neck',
        'Looks away to think',
        'Voice cracks',
      ],
      answers: <int>{1, 3, 5},
      insight: 'Hard swallowing (stress dries the mouth), collar ventilation and a cracking voice are the cluster. '
          'The cough has a medical cause, the arms are a temperature response, and looking away to think is his baseline.',
    ),
    Challenge.cluster(
      id: 'c8',
      highLoad: true,
      profile: 'Claire is interviewed over video. The connection lags now and then, and she glances down at her notes '
          'often, as she did from the very first minute.\n\n'
          'Asked if she shared the unreleased product specs, Claire\'s smile drops for half a second and snaps back. '
          'Her shoulders rise toward her ears, and she touches her nose and upper lip twice. The audio lags briefly '
          'as she answers.',
      indicators: <String>[
        'Her smile drops, then snaps back',
        'Her audio lags for a second mid-answer',
        'Shoulders rise toward her ears',
        'She glances down at her notes again',
        'Touches her nose and upper lip',
        'She is wearing a headset microphone',
      ],
      answers: <int>{0, 2, 4},
      insight: 'The faltering smile is a masked reaction breaking through, raised shoulders ("turtling") signal a wish '
          'to hide, and nose and lip touching is a pacifier. On video, rule out lag and screen habits before reading '
          'meaning into them.',
    ),
    Challenge.cluster(
      id: 'c9',
      highLoad: true,
      profile: 'Raj, a gate agent, taps his pen, talks with his hands and smiles constantly. Describing his shift, he '
          'taps the pen and sketches the gate layout in the air.\n\n'
          'Asked about the missing passenger manifest, the pen stops dead. His feet tuck under the chair and his '
          'ankles lock together. His lips press into a thin line before he says, "I filed it like always."',
      indicators: <String>[
        'Smiles when greeting the investigator',
        'Pen tapping stops dead',
        'Talks with his hands about the gate layout',
        'Feet tuck under the chair, ankles locked',
        'Taps his pen while describing his shift',
        'Lips press into a thin line',
      ],
      answers: <int>{1, 3, 5},
      insight: 'Stopping a baseline habit is as meaningful as starting a new one. The frozen pen, ankle locking (a '
          'freeze posture) and lip compression form the cluster, all triggered by the manifest question.',
    ),

    // ── LEVEL 4 · STATEMENT ANALYSIS ───────────────────────────────────────
    Challenge.statement(
      id: 's1',
      flag: Flag.pronounDrop,
      question: 'Tell me what you did after work on Tuesday.',
      sentences: <String>[
        'Left the office around 5:30 and took the long way home.',
        'I made pasta for dinner and watched half a movie with my roommate.',
        'I went to bed early because I had a 7 AM meeting the next day.',
      ],
      answer: 0,
      insight: 'Pronoun drop. Sentence 1 has no "I": nobody owns leaving the office or the drive. In truthful '
          'accounts people usually own their actions. Here the speaker commits fully to the evening at home but not '
          'to the drive, so that\'s the stretch to probe ("Why the long way? Where did you stop?").',
    ),
    Challenge.statement(
      id: 's2',
      flag: Flag.temporalGap,
      question: 'Walk me through Saturday morning.',
      sentences: <String>[
        'I woke up around seven, fed the dog and took him out for a short walk.',
        'After that, I drove over to the hardware store for some paint.',
        'I got there right when they opened at eleven and grabbed two gallons.',
      ],
      answer: 1,
      insight: 'Temporal gap. The walk ends around 7:30, but they reach the store at eleven: about three hours vanish '
          'behind "After that". Phrases like "after that", "later on" and "the next thing I knew" can mark '
          'withheld information. Ask what happened in between.',
    ),
    Challenge.statement(
      id: 's3',
      flag: Flag.tenseShift,
      question: 'What happened when you got to the parking garage?',
      sentences: <String>[
        'I parked on level two because the lower levels were completely full.',
        'I\'m walking back to my car and a guy grabs my bag from behind.',
        'I yelled for help and he ran off toward the stairwell with it.',
      ],
      answer: 1,
      insight: 'Verb tense shift. "Parked" and "yelled" are past tense, but the key moment ("I\'m walking", '
          '"grabs") is told in the present. Memories are usually recalled in the past tense; a switch at the critical '
          'moment can mean the speaker is constructing rather than remembering. A flag to probe, not proof.',
    ),
    Challenge.statement(
      id: 's4',
      flag: Flag.nonAnswer,
      question: 'Did you take the money from the register?',
      sentences: <String>[
        'Look, I\'ve worked here six years and never had a single complaint.',
        'I opened the drawer at nine and counted it with Maria, like always.',
        'At close I counted it again, logged the total and locked the safe.',
      ],
      answer: 0,
      insight: 'Non-answer assertion. The question was yes or no, and the only sentence aimed at it is a character '
          'reference ("six years, no complaints"). "No, I didn\'t take it" never appears. Truthful denials tend to '
          'be short, direct and on topic.',
    ),
    Challenge.statement(
      id: 's5',
      flag: Flag.tenseShift,
      question: 'How did you lose your wallet?',
      sentences: <String>[
        'I was at the coffee shop on Fifth Street.',
        'I set my wallet on the counter while I paid.',
        'I turn around and it\'s just gone.',
      ],
      answer: 2,
      insight: 'Tense shift at the key moment: "was" and "set" are past; "turn" and "is gone" are present. The part of '
          'the story that matters most is the part told in the wrong tense. Make it the focus of your next questions.',
    ),
    Challenge.statement(
      id: 's6',
      flag: Flag.temporalGap,
      question: 'What did you do after the budget meeting?',
      sentences: <String>[
        'I went back to my desk and returned a few calls.',
        'Later on, I noticed the laptop was missing.',
        'I reported it to security right away.',
      ],
      answer: 1,
      insight: '"Later on" hides an unknown stretch of time between returning calls and discovering the theft, exactly '
          'the window when the laptop disappeared. A gap right before the key event deserves a timeline question.',
    ),
    // High Cognitive Load · Level 4
    Challenge.statement(
      id: 's7',
      flag: Flag.tenseShift,
      highLoad: true,
      question: 'Tell me about the night of the break-in.',
      sentences: <String>[
        'So we\'d been at my sister\'s for dinner. She makes this incredible lasagna.',
        'We got home around ten, maybe ten-fifteen, because the game was still on.',
        'My husband went up to bed and I stayed downstairs to finish the dishes.',
        'And I go to lock the back door and the glass is already broken.',
        'I called 911 right away and waited in the car with my phone.',
      ],
      answer: 3,
      insight: 'Buried in a friendly, detailed past-tense story ("had been", "got", "went", "stayed"), the single most '
          'important sentence slips into present tense ("go", "is"). Find where the tense breaks, not where the story '
          'feels emotional.',
    ),
    Challenge.statement(
      id: 's8',
      flag: Flag.temporalGap,
      highLoad: true,
      question: 'What did you do between leaving the bar and getting home?',
      sentences: <String>[
        'I said goodbye to Mike and Tasha out front. They were heading for pizza.',
        'I walked to my car, which was on Elm because the lot was totally full.',
        'Eventually I got home and went straight to bed.',
        'I\'d only had two beers, maybe, over like three hours, so I was fine.',
        'My roommate can tell you I was home by midnight.',
      ],
      answer: 2,
      insight: 'The question asked about exactly one window, the drive home, and "Eventually" squeezes it into one '
          'word. Sentence 4 over-justifies and sentence 5 borrows a witness; both are worth noting, but they are '
          'decoys. The structural gap is in sentence 3.',
    ),
    Challenge.statement(
      id: 's9',
      flag: Flag.pronounDrop,
      highLoad: true,
      question: 'Describe what you did when you opened the store this morning.',
      sentences: <String>[
        'I got in at 6:45, which is early for me, but we had a big delivery coming.',
        'Turned off the alarm, then moved some boxes in the back room.',
        'I counted the safe, which I do every morning, and it was all there.',
        'I flipped on the lights out front and started the coffee machine.',
        'I opened the doors at seven on the dot, same as every other day.',
      ],
      answer: 1,
      insight: 'Every sentence owns its actions with "I" except the alarm and the back room. A pronoun drop inside '
          'an otherwise committed story pinpoints the part the speaker is least willing to own.',
    ),
    Challenge.statement(
      id: 's10',
      flag: Flag.nonAnswer,
      highLoad: true,
      question: 'Did you send the pricing email to the competitor?',
      sentences: <String>[
        'I saw that thread on Monday. The subject line was Q3 pricing.',
        'Honestly, I\'m just not the kind of person who\'d sell out my team.',
        'I forwarded it to my manager because she asked me for it that morning.',
        'I replied to Karen in accounting about the invoice numbers after lunch.',
        'I logged off around six and went to my kid\'s soccer game.',
      ],
      answer: 1,
      insight: 'Every other sentence is a concrete, checkable action, which makes the answer feel cooperative. But '
          'the only sentence that touches the actual question is a character assertion; "I did not send it" never '
          'appears. Words like "honestly" often prop up a claim the speaker doesn\'t trust to stand alone.',
    ),

    // ── ADDED COURSES & EXTRA PRACTICE ─────────────────────────────────────
    Challenge.baseline(
      id: 'b10',
      flag: Flag.gestureShift,
      context: 'Leo is asked about a dent in the company van.\n\nBASELINE: Leo talks with small, steady hand movements and nods along while he listens.',
      moments: <String>[
        'Asked how the van got dented → small gestures, nods: "No idea. It was fine Friday."',
        'Asked where he parked it overnight → shrugs one shoulder only, hands stay down.',
        'Asked if he drove it Friday → hands move steadily: "Twice, for supply runs."',
        'Asked who was with him → small gestures, nods along, names two coworkers.',
        'Asked about his schedule → stops gesturing to scratch a mosquito bite, then carries on.',
      ],
      answer: 1,
      insight: 'A one-shoulder shrug shows someone doesn\'t fully believe what they\'re saying. It came on where the van was parked overnight, the likely scene of the dent, while the direct question stayed on baseline. Scratching a mosquito bite had an outside cause.',
    ),
    Challenge.baseline(
      id: 'b11',
      flag: Flag.ocularShift,
      context: 'Grace is asked about a missing tip jar at the café.\n\nBASELINE: Grace\'s eyes roam the room while she talks, and she rubs them now and then. She just worked a double shift.',
      moments: <String>[
        'Asked if she took the tip jar → glances around, rubs her eyes: "No. I didn\'t touch it."',
        'Asked who closed with her → eyes lock on one spot on the table until she\'s done.',
        'Asked when her shift started → glances at the counter, then the door: "Around six."',
        'Asked about her coworker Jen → looks around the café: "She\'s great. Always on time."',
        'Asked about the café owner → a customer drops a tray; she jumps and stares at the noise.',
      ],
      answer: 1,
      insight: 'Roaming eyes and eye rubbing are her baseline after a double shift. The gaze freeze came when asked who closed with her. That person may matter more than the denial does. Staring at a dropped tray had an outside cause, unlike the gaze freeze.',
    ),
    Challenge.baseline(
      id: 'b12',
      flag: Flag.pacifying,
      context: 'Nate is asked about a fight outside the gym.\n\nBASELINE: Nate sits back with his forearms on his legs. He doesn\'t touch his face at all during small talk.',
      moments: <String>[
        'Asked if he threw a punch → forearms on his legs, calm: "No. I walked away."',
        'Asked what time he left the gym → rubs his forehead with two fingers, then answers.',
        'Asked about his bruised knuckles → calmly, arms on his legs: "Punching bag. No gloves."',
        'Asked if he knows the other guy → arms resting: "Seen him around. Never talked."',
        'Asked about his workout → winces and rubs his sore shoulder, then sits back again.',
      ],
      answer: 1,
      insight: 'Forehead rubbing is a pacifier, and it\'s new for Nate. It came on the timeline question, not the accusation or the bruised knuckles. Evidence isn\'t behavior: judge the change, not how guilty an answer sounds. Rubbing a sore shoulder after a workout has an obvious cause; the forehead rub doesn\'t.',
    ),
    Challenge.micro(
      id: 'm11',
      flag: Flag.happiness,
      card: 'Both lip corners rise evenly, the cheeks lift, and crow\'s-feet wrinkles appear at the outer corners of the eyes.',
      emotions: <String>[
        'Contempt',
        'Happiness',
        'Duping Delight',
        'Surprise',
      ],
      answer: 1,
      insight: 'The Duchenne smile: genuine happiness involves the muscle around the eyes, which is hard to fire on purpose. A smile that stops at the mouth is usually social or masking.',
    ),
    Challenge.micro(
      id: 'm12',
      flag: Flag.disgust,
      card: 'When a coworker\'s name comes up, the upper lip curls up on BOTH sides and the nose crinkles for under half a second.',
      emotions: <String>[
        'Contempt',
        'Anger',
        'Disgust',
        'Sadness',
      ],
      answer: 2,
      insight: 'Disgust is two-sided: upper lip raised, nose wrinkled. Contempt is one-sided. A flash of disgust at a name tells you how the person really feels about them.',
    ),
    Challenge.micro(
      id: 'm13',
      flag: Flag.surprise,
      card: 'The eyebrows lift in a smooth curve, the forehead wrinkles horizontally and the mouth falls open in a relaxed oval.',
      emotions: <String>[
        'Fear',
        'Surprise',
        'Happiness',
        'Sadness',
      ],
      answer: 1,
      insight: 'Surprise: curved raised brows and a relaxed, dropped jaw. If the brows were also pulled together and the lips stretched sideways, it would be fear.',
    ),
    Challenge.cluster(
      id: 'c10',
      profile: 'Rosa, a nurse, is asked about missing pain medication. She was chatty during small talk, clicks her pen constantly and tucks her hair behind her ear every few minutes.',
      indicators: <String>[
        'Clicks her pen while describing her rounds',
        'Her voice drops almost to a whisper',
        'Tucks her hair behind her ear again',
        'She swallows hard before answering',
        'She mentions she\'s worked nights for years',
        'Her hands grip the edge of the table',
      ],
      answers: <int>{1, 3, 5},
      insight: 'A voice drop, a hard swallow and white-knuckle gripping all appear at the key question. The pen and hair habits were there from the start, and her work history is just background.',
    ),
    Challenge.cluster(
      id: 'c11',
      profile: 'Derek, a landlord, is asked whether he entered a tenant\'s apartment without notice. He\'s soft-spoken and rubs his beard whenever he thinks.',
      indicators: <String>[
        'Rubs his beard while recalling dates',
        'Blinks rapidly for several seconds',
        'His neck flushes bright red',
        'Speaks softly, as he has all along',
        'Turns his chair a quarter-turn away',
        'Owns four other rental buildings',
      ],
      answers: <int>{1, 2, 4},
      insight: 'A blink surge, neck flushing (blood rushing under stress) and turning his body away form the cluster. Beard rubbing and soft speech are his baseline, and owning other buildings is just a fact.',
    ),
    Challenge.cluster(
      id: 'c12',
      profile: 'Tasha is asked if she copied answers during an online exam. Since sitting down she has bounced her knee constantly and sipped water every few minutes.',
      indicators: <String>[
        'Her knee keeps bouncing under the desk',
        'Her lips press into a tight line',
        'She takes another sip from her water bottle',
        'She touches the side of her neck',
        'She is wearing her school hoodie',
        'She answers "Why would I cheat?" before denying',
      ],
      answers: <int>{1, 3, 5},
      insight: 'Lip compression, neck touching and answering a question with a question cluster at the key moment. The knee bouncing and water sipping were constant from the start.',
    ),
    Challenge.statement(
      id: 's11',
      flag: Flag.pronounDrop,
      question: 'Where were you when the fire alarm went off?',
      sentences: <String>[
        'I was in the break room heating up my lunch in the microwave.',
        'I heard the alarm and I grabbed my jacket off the chair.',
        'Went down the back stairs and out to the parking lot.',
      ],
      answer: 2,
      insight: 'The speaker owns being in the break room and grabbing the jacket, but the route out has no "I". That\'s the stretch to ask about: which stairs, who did you see, how long did it take?',
    ),
    Challenge.statement(
      id: 's12',
      flag: Flag.nonAnswer,
      question: 'Did you post that video of your coworker online?',
      sentences: <String>[
        'I was home all weekend with my kids, so my phone was barely on.',
        'Why would I want to embarrass someone I work with?',
        'I checked my email Sunday night and went to bed around ten.',
      ],
      answer: 1,
      insight: 'A yes-or-no question answered with a rhetorical question is a non-answer: it invites you to argue about motive instead of hearing a denial. "No, I didn\'t post it" never appears.',
    ),
    Challenge.statement(
      id: 's13',
      flag: Flag.temporalGap,
      question: 'What did you do after you closed the shop on Friday?',
      sentences: <String>[
        'I locked the front door at nine and set the alarm like I always do.',
        'I counted the drawer, put the deposit bag in the safe and turned off the lights.',
        'Next thing I knew, it was Saturday morning and my manager was calling.',
      ],
      answer: 2,
      insight: '"Next thing I knew" jumps from closing time to the next morning and skips the whole night. Ask what happened right after the lights went off.',
    ),
    Challenge.statement(
      id: 'v1',
      flag: Flag.qualifier,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'Did you see who took the laptop?',
      sentences: <String>[
        'I was at my desk the whole afternoon, working on the budget report.',
        'To be perfectly honest with you, I didn\'t see anybody near it.',
        'Kim from marketing stopped by around three to ask about the meeting.',
      ],
      answer: 1,
      insight: 'Credibility qualifiers ("to be honest", "frankly", "I swear") try to make a statement sound true instead of letting it stand alone. Truthful people usually assume they\'ll be believed. Notice where it lands: on the one sentence that answers the question.',
    ),
    Challenge.statement(
      id: 'v2',
      flag: Flag.distancing,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'What\'s your relationship with Ms. Carter?',
      sentences: <String>[
        'We were in the same department for about two years, on the same floor.',
        'We went to a few team lunches together, mostly with other people.',
        'I never had any kind of personal relationship with that woman.',
      ],
      answer: 2,
      insight: 'Distancing language. Switching from a name to "that woman" or "that person" pushes the subject away psychologically. It often appears when someone wants to separate themselves from a person or an event.',
    ),
    Challenge.statement(
      id: 'v3',
      flag: Flag.minimizing,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'What happened with the company credit card?',
      sentences: <String>[
        'I just used it a couple of times for small personal stuff.',
        'Finance flagged the charges during their monthly review last week.',
        'I met with my manager on Tuesday and we went through the statement.',
      ],
      answer: 0,
      insight: 'Minimizing language ("just", "a couple", "small") shrinks the act. It\'s common when people admit part of something and hope the rest stays small. Ask for exact numbers.',
    ),
    Challenge.statement(
      id: 'v4',
      flag: Flag.stalling,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'Were you at the warehouse on Sunday night?',
      sentences: <String>[
        'Was I at the warehouse Sunday night? Why would you ask me that?',
        'I was at my mom\'s place across town for dinner until about ten.',
        'My brother drove me home after, so you can check with him if you want.',
      ],
      answer: 0,
      insight: 'Repeating the question back buys time to build an answer, and "Why would you ask?" tries to find out what you know. Neither is a denial.',
    ),
    Challenge.statement(
      id: 'v5',
      flag: Flag.qualifier,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'Did you leave the gate unlocked?',
      sentences: <String>[
        'I closed up the yard at six, same as every other weekday.',
        'I walked the fence line and checked the padlock on the side gate.',
        'I swear on my kids I locked the front gate behind me.',
      ],
      answer: 2,
      insight: 'Oaths ("I swear on my kids", "God as my witness") are credibility boosters. Truthful speakers rarely need an oath to back a simple fact, and here it shows up only on the key claim.',
    ),
    Challenge.statement(
      id: 'v6',
      flag: Flag.distancing,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'Tell me about the argument with your brother.',
      sentences: <String>[
        'Danny and I have always fought about money, ever since we were kids.',
        'That guy came over Saturday and started yelling about the loan.',
        'Danny left after about twenty minutes and I haven\'t heard from him.',
      ],
      answer: 1,
      insight: 'He calls his brother "Danny" twice but "that guy" at the moment of the argument. A switch to distancing language at one point in the story shows where the emotion, or the problem, is.',
    ),
    Challenge.statement(
      id: 'v7',
      flag: Flag.minimizing,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'How did the client data end up on your personal laptop?',
      sentences: <String>[
        'We were swamped that quarter, everyone was taking work home at night.',
        'IT never told us there was a rule about personal devices, as far as I knew.',
        'I was trying to finish the Hendricks report before the Monday deadline.',
        'I only copied over a few files, nothing anyone would really care about.',
        'As soon as I heard there was a problem I deleted everything myself.',
      ],
      answer: 3,
      insight: '"Only", "a few" and "nothing anyone would care about" shrink the act. The excuses in sentences 1–3 and the self-cleanup in sentence 5 are worth noting, but the minimizing tell is in sentence 4. Ask: how many files, exactly?',
    ),
    Challenge.statement(
      id: 'v8',
      flag: Flag.stalling,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'Did you change the numbers in the inventory report?',
      sentences: <String>[
        'I\'ve been doing inventory for this store for almost four years now.',
        'Every count goes through the scanner and then into the system automatically.',
        'That\'s a good question, and I can see why it would look that way.',
        'Sometimes the scanner double-counts boxes, and we fix those by hand.',
        'Marcus and I usually do the corrections together on Monday mornings.',
      ],
      answer: 2,
      insight: '"That\'s a good question" is a stall: it compliments the question while buying time, and it\'s followed by explanation instead of "No." Stalling phrases ("good question", "let me think", "what do you mean by changed?") show the question landed.',
    ),
    Challenge.statement(
      id: 'v9',
      flag: Flag.distancing,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'Walk me through the night your roommate\'s car was damaged.',
      sentences: <String>[
        'Jess and I got back from the movies around eleven and made some tea.',
        'Jess went to bed first because she had an early shift the next morning.',
        'I stayed up watching TV in the living room until probably one.',
        'I heard a bang outside but figured it was just the neighbors again.',
        'In the morning, the girl was screaming about her car in the driveway.',
      ],
      answer: 4,
      insight: 'Jess is "Jess" all night until the damage is discovered, then becomes "the girl". Distancing at the moment of the incident is the tell, buried under four ordinary sentences. "Figured it was just the neighbors" also pre-explains the bang.',
    ),
    Challenge.statement(
      id: 'v10',
      flag: Flag.qualifier,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'Did you take money from the church collection?',
      sentences: <String>[
        'Frankly, I barely even handled the collection plates that day.',
        'Pastor Jim asked me to help count after the eleven o\'clock service.',
        'We counted it in the office with the door open, like we always do.',
        'Linda wrote the totals on the deposit slip and sealed the envelope.',
        'I went straight home after because my daughter had a recital at two.',
      ],
      answer: 0,
      insight: '"Frankly" props up a claim that the rest of the statement undercuts: they helped count the money. Qualifiers often attach to the weakest claim. ("Barely" is minimizing too.)',
    ),
    Challenge.cluster(
      id: 't1',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A witness describes a robbery at a corner store:\n\n"I was in line, um, no wait, I was by the chips when he came in. He had this weird yellow scarf, like a soccer scarf. I honestly don\'t remember his shoes at all. I swear to God I\'m telling you everything. It all happened in exactly the order I\'m saying. I\'m a very observant person."',
      indicators: <String>[
        'Corrects herself mid-sentence ("no wait")',
        'Mentions an odd detail: the yellow soccer scarf',
        'Admits she doesn\'t remember his shoes',
        'Swears to God she\'s telling everything',
        'Insists it happened in exactly that order',
        'Says she is a very observant person',
      ],
      answers: <int>{0, 1, 2},
      insight: 'Real memory is messy: people self-correct, admit gaps and include odd details that serve no purpose. Liars avoid "I don\'t remember" because it sounds weak, and they lean on oaths, perfect order and claims about their own reliability.',
    ),
    Challenge.cluster(
      id: 't2',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'Ben explains why he was late to a client meeting:\n\n"Traffic on 5th was a nightmare, a bus was stalled in the right lane. I remember being really annoyed, I was gripping the wheel. Actually, it might have been 6th, not 5th. I can\'t remember if I texted my boss before or after I parked. I\'m a very punctual person, and my record speaks for itself."',
      indicators: <String>[
        'Describes his annoyance and gripping the wheel',
        'Calls the traffic "a nightmare"',
        'Corrects the street name on his own',
        'Stresses that he\'s a very punctual person',
        'Admits he can\'t recall when he texted his boss',
        'Says his record speaks for itself',
      ],
      answers: <int>{0, 2, 4},
      insight: 'Memories of real events carry feelings and body sensations, and people correct themselves without being asked. Admitting a small gap is a strong truth marker. Pointing to character ("I\'m punctual", "my record speaks for itself") is about credibility, not about what happened.',
    ),
    Challenge.cluster(
      id: 't3',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A teenager explains a dent in the family car:\n\n"I backed out slow, I was checking the mirror, and this cat ran behind me. I jammed the brakes and my phone flew off the seat. I think I hit the mailbox, but honestly I\'m not 100% sure, it was dark. I would never lie to you guys. You can trust me on this."',
      indicators: <String>[
        'Mentions his phone flying off the seat',
        'Says he would never lie to his parents',
        'Admits he isn\'t 100% sure what he hit',
        'Asks his parents to trust him on this',
        'Includes a cat darting behind the car',
        'Stresses that he backed out slowly',
      ],
      answers: <int>{0, 2, 4},
      insight: 'Unexpected complications (a cat, a phone flying off the seat) and admitted uncertainty are typical of real memories; fabricated stories tend to be clean. "I would never lie" and "trust me" add nothing about the event, and stressing he drove slowly is self-serving.',
    ),
    Challenge.cluster(
      id: 't4',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A coworker describes finding the server room door open:\n\n"I came in at 7:40, early because of the audit. The door was propped open with a fire extinguisher, which was weird, and the room smelled like burnt coffee. I don\'t know who was in there. I called Raj, wait, no, I texted him first, then called. To be clear, I followed every single protocol perfectly."',
      indicators: <String>[
        'Notes the odd smell of burnt coffee',
        'Says she followed every protocol perfectly',
        'Self-corrects: texted Raj before calling',
        'Explains why she came in early',
        'Says "to be clear" before her claim',
        'Mentions the fire extinguisher propping the door',
      ],
      answers: <int>{0, 2, 5},
      insight: 'Sensory details (the smell), unusual details (the fire extinguisher) and spontaneous self-correction are truth markers. "To be clear" plus "every single protocol perfectly" is a credibility pitch. Explaining why she was early is normal context either way.',
    ),
    Challenge.cluster(
      id: 't5',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A man describes being mugged:\n\n"He came from the left, I think. He smelled like cigarettes and had a chipped front tooth. He said \'wallet, now\' and I just froze, my legs felt like jelly. I couldn\'t tell you what color his jacket was. Obviously I\'m a pretty observant guy in general. It all happened in like five seconds."',
      indicators: <String>[
        'Describes his legs feeling like jelly',
        'Admits he can\'t recall the jacket color',
        'Says he\'s a pretty observant guy',
        'Remembers the smell of cigarettes',
        'Says it all happened in five seconds',
        'Says "obviously" before describing himself',
      ],
      answers: <int>{0, 1, 3},
      insight: 'Body sensations (jelly legs), smells and admitted gaps (the jacket) are what real memories contain. Calling himself observant contradicts the gap he just admitted and adds nothing about the event.',
    ),
    Challenge.cluster(
      id: 't6',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A babysitter explains how a child got a scrape:\n\n"We were at the park, Mia was on the monkey bars, and I was maybe ten feet away. She slipped on the third bar, I remember because she was counting out loud. She cried, but honestly she calmed down fast once I gave her a sticker. I\'m extremely careful with kids. I have years of experience and great references."',
      indicators: <String>[
        'Remembers Mia counting the bars out loud',
        'Mentions years of experience and references',
        'Admits she was about ten feet away',
        'Says she is extremely careful with kids',
        'Includes the sticker that calmed her down',
        'Says "honestly" before the crying part',
      ],
      answers: <int>{0, 2, 4},
      insight: 'Admitting something unflattering (being ten feet away) is a strong truth marker: liars rarely volunteer details that hurt them. Small specific memories (counting out loud, the sticker) fit real events. Credentials describe her, not what happened.',
    ),
    Challenge.cluster(
      id: 't7',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      highLoad: true,
      profile: 'An employee explains \$200 missing from petty cash:\n\n"I opened the box around noon to pay the pizza guy, Tony, the one with the neck tattoo. I counted it then, and I\'m positive it was all there, every single bill. After that I put it back in the top drawer, or maybe the second drawer, I go back and forth on that. I remember feeling rushed because the phones kept ringing. I want to stress I\'ve never had a cash issue in nine years here. I followed the procedure exactly, to the letter."',
      indicators: <String>[
        'Names the pizza guy and his neck tattoo',
        'Is "positive" every single bill was there',
        'Isn\'t sure which drawer it went into',
        'Mentions feeling rushed by ringing phones',
        'Stresses nine years without a cash issue',
        'Says he followed procedure to the letter',
      ],
      answers: <int>{0, 2, 3},
      insight: 'Certainty about the part that matters ("positive", "every single bill") and stressing a perfect record are credibility pitches. The truth markers are the incidental detail (the tattoo), the honest uncertainty about the drawer, and a feeling tied to a concrete cause.',
    ),
    Challenge.cluster(
      id: 't8',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      highLoad: true,
      profile: 'A driver describes a crash at an intersection:\n\n"So the light was green, definitely green, I\'m 100 percent on that. I was humming along to some song, I can\'t even tell you which one. The other car came out of nowhere, and the airbag smelled like gunpowder, which I didn\'t expect. My first thought, weirdly, was that I\'d be late picking up my dry cleaning. I\'m a very safe driver. I\'ve never had so much as a parking ticket."',
      indicators: <String>[
        'Insists the light was "definitely" green',
        'Can\'t remember which song he was humming',
        'Notes the airbag smelled like gunpowder',
        'Says the car came "out of nowhere"',
        'Admits an odd first thought about dry cleaning',
        'Mentions never getting a parking ticket',
      ],
      answers: <int>{1, 2, 4},
      insight: 'Odd, irrelevant thoughts (the dry cleaning) and unexpected sensations (the gunpowder smell) are hard to invent, and admitting he forgot a trivial detail adds credibility. Notice the certainty sits on the one fact that decides fault: the light.',
    ),
    Challenge.cluster(
      id: 't9',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      highLoad: true,
      profile: 'A student explains how a lab sample got contaminated:\n\n"I prepped the slides Tuesday after lunch. Dr. Hale stopped by and joked that my gloves looked two sizes too big, which, fair, they were. I may have touched the bench edge before sealing slide four, I genuinely can\'t rule that out. I logged everything in the notebook exactly on time. Everyone in the lab knows I\'m meticulous. There is no possible way the mistake came from my station."',
      indicators: <String>[
        'Recounts Dr. Hale\'s joke about his gloves',
        'Admits he may have touched the bench edge',
        'Says he logged everything exactly on time',
        'Says everyone knows he\'s meticulous',
        'Agrees, unprompted, that the gloves were too big',
        'Claims there\'s "no possible way" it was him',
      ],
      answers: <int>{0, 1, 4},
      insight: 'The account contradicts itself: he admits he may have touched the bench, then claims "no possible way". The truthful parts are the reproduced conversation and the concessions against his own interest; the absolutes are the pitch.',
    ),
    Challenge.cluster(
      id: 't10',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      highLoad: true,
      profile: 'A neighbor describes an argument next door:\n\n"It was around 10:30, maybe a bit later, the news had just ended. I heard a man shout something like \'you always do this,\' and a door slammed so hard my picture frame rattled. I didn\'t call anyone, and honestly I feel bad about that now. I want to be very clear that I am a reliable witness. I have absolutely perfect hearing, I\'ve been tested."',
      indicators: <String>[
        'Feels bad, unprompted, about not calling anyone',
        'Says she has "absolutely perfect" hearing',
        'Notes her picture frame rattled',
        'Gives the time as "maybe a bit later" than 10:30',
        'Calls herself a very reliable witness',
        'Says she wants to be very clear',
      ],
      answers: <int>{0, 2, 3},
      insight: 'Admitting a feeling that makes her look bad, a small physical detail (the rattling frame) and an approximate, self-corrected time are truth markers. Claims of perfect hearing and reliability are about her credibility, not the event. Note that "honestly" appears in a truthful sentence: one qualifier alone proves nothing.',
    ),
    Challenge.scenario(
      id: 'i1',
      flag: Flag.openQuestion,
      context: 'You\'re interviewing a warehouse worker about a missing pallet of electronics. You want his full account of Thursday\'s shift before anything else.',
      moves: <String>[
        'Ask: "Did you load any pallets onto trucks on Thursday?"',
        'Ask: "Walk me through Thursday, start to finish."',
        'Ask: "You were on the loading dock Thursday, weren\'t you?"',
        'Ask: "Why do you think the pallet went missing on your shift?"',
      ],
      answer: 1,
      insight: 'Start wide. An open "walk me through it" question gets a free narrative before you shape it. Yes/no and leading questions ("weren\'t you?") hand over your theory and give you one word to judge.',
    ),
    Challenge.scenario(
      id: 'i2',
      flag: Flag.contamination,
      context: 'A witness to a hit-and-run says she "didn\'t really see the car." Police already know it was a red pickup with a dented tailgate.',
      moves: <String>[
        'Ask: "Was it a red pickup? Maybe with a dented tailgate?"',
        'Ask: "Any small thing at all? A color, a sound, a shape?"',
        'Ask: "Most witnesses remember the color. Can you try harder?"',
        'Tell her the details so she knows what to look for in a lineup.',
      ],
      answer: 1,
      insight: 'Never feed details you know. Once she hears "red pickup" you can\'t separate her memory from your suggestion, and the detail is useless as a check. Prompt across senses instead, and don\'t pressure ("try harder"): it invites guessing.',
    ),
    Challenge.scenario(
      id: 'i3',
      flag: Flag.probeHotSpot,
      context: 'A suspect\'s pitch rose and he touched his neck when you asked about the parking garage. Everything else matched his baseline.',
      moves: <String>[
        'Accuse him: "Your body just told me you\'re lying about the garage."',
        'Move on and come back to the garage later with open questions.',
        'Ask him directly why he touched his neck just now.',
        'Write it off, since a single topic isn\'t a pattern worth chasing.',
      ],
      answer: 1,
      insight: 'A hot spot is a place to dig, not a verdict. Accusing ends cooperation, and pointing out body language teaches people to control it. Note it, keep rapport, and return with open questions to see if the reaction repeats.',
    ),
    Challenge.scenario(
      id: 'i4',
      flag: Flag.rapport,
      context: 'A nervous 19-year-old intern sits down for an interview about a data leak. She\'s shaking and hasn\'t made eye contact.',
      moves: <String>[
        'Start with easy questions about her studies and first weeks here.',
        'Open by telling her the evidence against her is already very strong.',
        'Skip small talk, since nervous people crack faster under pressure.',
        'Read her the company\'s policy on leaks so she knows what\'s at stake.',
      ],
      answer: 0,
      insight: 'Rapport first, and it also gives you a baseline. Nervousness isn\'t guilt: innocent people are often scared in interviews. Pressure now and you can\'t tell fear of the situation from fear of being caught.',
    ),
    Challenge.scenario(
      id: 'i5',
      flag: Flag.probeHotSpot,
      context: 'A suspect says: "I fed the dog at seven. After that I went to the store around noon." You want to explore the gap.',
      moves: <String>[
        'Ask: "So you did absolutely nothing at all between seven and noon?"',
        'Ask: "What happened after you fed the dog?"',
        'Ask: "Were you over at the Miller house sometime between seven and noon?"',
        'Point out that five hours is a long time to leave unexplained.',
      ],
      answer: 1,
      insight: 'Probe a gap with an open, neutral question that starts from the last thing they told you. "So you did nothing?" invites a quick yes, naming the Miller house reveals what you know, and pointing out the gap puts them on guard before you learn anything.',
    ),
    Challenge.scenario(
      id: 'i6',
      flag: Flag.contamination,
      context: 'Mid-statement, the suspect pauses and asks: "Do you guys already know who was in the office that night?"',
      moves: <String>[
        'Say yes, and that cameras caught everything, to see how he reacts.',
        'Tell him who you suspect so he understands the situation clearly.',
        'Say "We\'re still putting it together. Tell me what you know."',
        'Answer that you can\'t share anything and end the interview.',
      ],
      answer: 2,
      insight: 'He\'s fishing for what you know so he can fit his story to it. Don\'t reveal evidence or theories, and don\'t bluff about cameras: a false claim can wreck your credibility. Calmly turn it back to his account.',
    ),
    Challenge.scenario(
      id: 'i7',
      flag: Flag.probeHotSpot,
      highLoad: true,
      context: 'Your suspect gave a detailed, confident timeline for the whole evening except one line: "Then I drove around for a while to clear my head." He\'s been cooperative and friendly.',
      moves: <String>[
        'Thank him and wrap up, since the timeline is detailed and checks out.',
        'Ask him to tell the whole evening again, but backwards from midnight.',
        'Tell him "driving around" sounds made up and ask what he\'s hiding.',
        'Ask: "Did you drive past the victim\'s street while you were out?"',
      ],
      answer: 1,
      insight: 'Reverse-order recall raises cognitive load: a rehearsed story is easy forward and hard backward, while real memories hold up. It also forces detail into the vague "drove around" stretch without accusing him or leaking that you care about the victim\'s street.',
    ),
    Challenge.scenario(
      id: 'i8',
      flag: Flag.rapport,
      highLoad: true,
      context: 'Two hours in, the suspect snaps: "This is a joke! I\'ve given you three hours of my life!" Until now he\'s answered everything.',
      moves: <String>[
        'Match his energy so he knows you won\'t be pushed around in here.',
        'Acknowledge it: "It\'s been long, I get it. A few more questions."',
        'Treat the outburst as proof he\'s hiding something and press harder.',
        'Stop immediately and schedule a new interview for some other day.',
      ],
      answer: 1,
      insight: 'Frustration after hours of questions is normal fatigue, not a confession. Escalating ends cooperation, and reading guilt into it is confirmation bias. Acknowledging the feeling lowers the temperature and keeps the conversation going.',
    ),
    Challenge.scenario(
      id: 'i9',
      flag: Flag.openQuestion,
      highLoad: true,
      context: 'A witness gave a vague account of a fight: "Some guys argued and then it got physical." You want more detail without leading her.',
      moves: <String>[
        'Ask: "Was the guy in the red hoodie the one who started it?"',
        'Ask: "Close your eyes and picture the spot. What do you see?"',
        'Ask: "Did someone throw a punch, or was it more like shoving?"',
        'Ask: "How many guys were there? Three? Four?"',
      ],
      answer: 1,
      insight: 'Mentally reinstating the scene is a core Cognitive Interview technique: it unlocks detail without suggesting anything. "Red hoodie" leaks a detail, and offering choices ("punch or shoving", "three or four") limits her to your options.',
    ),
    Challenge.scenario(
      id: 'i10',
      flag: Flag.contamination,
      highLoad: true,
      context: 'Two witnesses saw the same robbery and are waiting together in the lobby. You only have time to interview one right now.',
      moves: <String>[
        'Let them chat so they feel relaxed and remember more for you later.',
        'Interview them together so their stories can fill in each other\'s gaps.',
        'Separate them now and ask them not to discuss what they saw.',
        'Have them write one summary together while you finish paperwork.',
      ],
      answer: 2,
      insight: 'Witnesses who talk blend their memories (memory conformity): one person\'s detail becomes the other\'s "memory". Separate them early and interview each one alone to keep the accounts independent.',
    ),
    Challenge.statement(
      id: 'd1',
      flag: Flag.nonAnswer,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'You text your roommate: "Did you eat my leftover pizza?"',
      sentences: <String>[
        'hey! just got home from work, so tired, long day lol',
        'u know im not the type to take ppl\'s food',
        'also we\'re out of paper towels and dish soap btw',
      ],
      answer: 1,
      insight: 'A yes/no question answered with a character claim ("I\'m not the type") is a non-answer, in texts just like in interviews. The small talk around it makes it feel normal.',
    ),
    Challenge.statement(
      id: 'd2',
      flag: Flag.distancing,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'An email from a manager to HR after a complaint from an employee named Jordan.',
      sentences: <String>[
        'Jordan has been on my team for two years and is usually a strong performer.',
        'I have always tried to treat every person on my team fairly and equally.',
        'The individual in question has been difficult ever since the review.',
      ],
      answer: 2,
      insight: '"Jordan" becomes "the individual in question" exactly where the manager describes the conflict. A formal, distancing label in an otherwise personal email shows where the writer wants emotional distance.',
    ),
    Challenge.statement(
      id: 'd3',
      flag: Flag.minimizing,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'Your partner texts after your joint bank account is overdrawn.',
      sentences: <String>[
        'it was just a little online shopping, nothing major',
        'i paid the electric bill on tuesday like we talked about',
        'also the car payment came out early this month for some reason',
      ],
      answer: 0,
      insight: '"Just", "a little" and "nothing major" shrink something they won\'t put a number on. Ask for the amount.',
    ),
    Challenge.statement(
      id: 'd4',
      flag: Flag.tenseShift,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'A customer\'s message to an airline about a "lost" bag.',
      sentences: <String>[
        'I checked my blue suitcase at the desk in Denver at about 6 a.m.',
        'The agent printed the tag and I watched it disappear down the belt.',
        'At baggage claim in Boston I wait an hour and it never comes out.',
      ],
      answer: 2,
      insight: 'Past tense ("checked", "printed", "watched") switches to present ("wait", "comes") at the key moment. Tense shifts show up in writing too, often where the story is being constructed.',
    ),
    Challenge.statement(
      id: 'd5',
      flag: Flag.qualifier,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'An online review of a mattress, posted from a brand-new account.',
      sentences: <String>[
        'I bought this mattress three weeks ago after my old one finally gave out.',
        'Trust me, this is literally the best sleep I have had in my entire life.',
        'Delivery took about five days and the box fit through our front door.',
      ],
      answer: 1,
      insight: '"Trust me" and "literally the best ... in my entire life" are persuasion, not description. Fake reviews lean on superlatives and credibility boosters; real ones mention specifics, including small negatives.',
    ),
    Challenge.statement(
      id: 'd6',
      flag: Flag.temporalGap,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'Your teen texts at 2 a.m. after missing curfew.',
      sentences: <String>[
        'we left the movie at like 10:30 and got food at the diner on main',
        'then we were hanging out for a while and lost track of time',
        'jake drove me home and dropped me off right at the corner',
      ],
      answer: 1,
      insight: '"For a while" covers about three hours between the diner and getting home, the part a parent most wants to know. Everything else is specific.',
    ),
    Challenge.statement(
      id: 'd7',
      flag: Flag.pronounDrop,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'A coworker\'s Slack message explaining why a client folder disappeared.',
      sentences: <String>[
        'Morning! So I was cleaning up the shared drive yesterday like Pat asked.',
        'I archived the old Q1 folders and renamed the templates to the new format.',
        'I also merged the duplicate contact sheets, there were like six of them.',
        'Moved the Benson folder into temp storage while sorting everything out.',
        'I\'ll double check the backups this afternoon and let you know what I find.',
      ],
      answer: 3,
      insight: 'Every action is owned with "I" except the one involving the missing client folder. In a long, cheerful, cooperative message, the dropped pronoun is the only structural change.',
    ),
    Challenge.statement(
      id: 'd8',
      flag: Flag.nonAnswer,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'A dating-app match replies after you ask: "Are you still seeing anyone else?"',
      sentences: <String>[
        'haha I had such a good time with you on Saturday night',
        'you know how much I hate drama, I\'m an open book with you',
        'I deleted the app on Sunday actually, it was getting so annoying',
        'work has been crazy this week but I\'m free Thursday night if you are',
        'there\'s that new thai place on 4th we should try',
      ],
      answer: 1,
      insight: 'The question was yes or no. Line 2 swaps the answer for a character claim ("I\'m an open book"). Deleting the app (line 3) sounds like an answer but isn\'t one: you can stop using an app and still be seeing someone. Then the subject changes.',
    ),
    Challenge.statement(
      id: 'd9',
      flag: Flag.distancing,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'A business partner\'s email about money missing from your shared account.',
      sentences: <String>[
        'Hi Sam, thanks for flagging this so quickly, I know it\'s stressful.',
        'I pulled the statements for March and April and went through each line.',
        'Most of the transfers match invoices from our usual suppliers, Sam.',
        'There are three I want to look into more before I say anything final.',
        'Those particular transactions were not something I authorized.',
      ],
      answer: 4,
      insight: '"Those particular transactions" and the passive "were not something I authorized" create distance: the writer never says "I didn\'t make those transfers." Everything before it is warm and direct, which makes the shift easy to miss.',
    ),
    Challenge.statement(
      id: 'd10',
      flag: Flag.qualifier,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'A contractor replies after you ask why the job is two weeks late.',
      sentences: <String>[
        'Thanks for checking in, I know the timeline has been frustrating.',
        'The tile supplier pushed back our delivery twice, which I sent you.',
        'Honestly, my crew has been on your house every single day.',
        'We\'re finishing grout tomorrow and the fixtures go in on Thursday.',
        'I\'ll send updated photos tonight so you can see where things are.',
      ],
      answer: 2,
      insight: '"Honestly" plus an absolute ("every single day") boosts the one claim you could easily check with a neighbor. The specific, checkable details elsewhere (supplier delays, photos) don\'t need a boost.',
    ),

    // ── CLEAN CASES: the right answer is "nothing here" ───────────────────
    Challenge.baseline(
      id: 'bc1',
      flag: Flag.cleanBaseline,
      context: 'Maya is asked about a missing delivery.\n\nBASELINE: Maya talks fast, gestures with both hands and laughs a lot, even about frustrating things.',
      moments: <String>[
        'Asked where she was at noon → fast, both hands moving: "Lunch run! Tacos, obviously."',
        'Asked if she signed for the box → laughs, hands wide: "Nope, I wasn\'t even here!"',
        'Asked who was at the front desk → rapid-fire, gesturing, names Kevin and laughs.',
        'Asked if the questions annoy her → laughs, hands up: "A little bit, yeah!"',
        'Asked about the delivery driver → stops mid-laugh to answer a text from her boss.',
      ],
      answer: Challenge.clean,
      insight: 'Every answer matches her baseline: fast, gesturing, laughing. "Nope, I wasn\'t even here" is a direct denial, and admitting she\'s a little annoyed is normal. Calling a lie here would be a false alarm, the most common mistake new analysts make. Even the pause to answer her boss had an outside cause, so nothing here counts.',
    ),
    Challenge.baseline(
      id: 'bc2',
      flag: Flag.cleanBaseline,
      context: 'Omar is asked about a cracked office window.\n\nBASELINE: Omar is quiet, sits very still, speaks slowly and looks down when he thinks.',
      moments: <String>[
        'Asked when he arrived → still, slow: "Around eight-fifteen. The bus was late."',
        'Asked if he saw the crack → looks down, pauses, slowly: "Not until Lisa pointed it out."',
        'Asked if he broke it → still, eyes down for a moment, then: "No. I didn\'t touch it."',
        'Asked who else was in early → slow and quiet, names two people, hands still.',
        'Asked about the window repair → a siren passes outside; he looks up at it, then back down.',
      ],
      answer: Challenge.clean,
      insight: 'Looking down before answering is Omar\'s normal thinking pattern, and the pause before "No" matches his slow baseline. Without a change, there\'s no signal: behavior means nothing on its own, only change does. Even looking up at a passing siren had an outside cause.',
    ),
    Challenge.baseline(
      id: 'bc3',
      flag: Flag.cleanBaseline,
      highLoad: true,
      context: 'Hannah is interviewed about expense fraud.\n\nBASELINE: Hannah twists her rings, crosses and uncrosses her legs, and clears her throat every minute or so. She\'s been like this since she sat down.',
      moments: <String>[
        'Asked about the hotel bill → twists a ring, clears her throat: "That was the conference."',
        'Asked if she added personal charges → uncrosses her legs, ring in hand: "No, never."',
        'Asked who approved the trip → crosses her legs, clears her throat, names her manager.',
        'Asked about the taxi receipts → twists her ring and explains each ride by date.',
        'Asked about the conference → her water glass tips; she catches it, then twists her ring.',
      ],
      answer: Challenge.clean,
      insight: 'She looks like a nervous wreck, but every behavior was there from the moment she sat down. Restless people don\'t become liars by staying restless. Being able to say "nothing here" is part of mastering baselines. Even catching the tipping glass had an outside cause.',
    ),
    Challenge.statement(
      id: 'sc1',
      flag: Flag.cleanStatement,
      level: 4,
      question: 'What did you do after work yesterday?',
      sentences: <String>[
        'I left the office at five-thirty and stopped at the gym for about an hour.',
        'I got home around seven, made dinner and called my sister for twenty minutes.',
        'I watched a show with my roommate and went to bed around eleven.',
      ],
      answer: Challenge.clean,
      insight: 'Clean: consistent "I", past tense throughout, and every stretch of time accounted for with rough times. Truthful accounts don\'t need to be perfect, just committed and continuous.',
    ),
    Challenge.statement(
      id: 'sc2',
      flag: Flag.cleanStatement,
      level: 4,
      question: 'Did you take the cash from the register?',
      sentences: <String>[
        'No, I didn\'t take it.',
        'I counted the drawer at close and it was short forty dollars, so I wrote it on the sheet.',
        'I told my manager about it when she came in the next morning.',
      ],
      answer: Challenge.clean,
      insight: 'A direct, past-tense denial ("No, I didn\'t take it") followed by specific, checkable actions. Reporting the shortage herself fits innocence too. Not every statement hides a flaw.',
    ),
    Challenge.statement(
      id: 'sc3',
      flag: Flag.cleanStatement,
      level: 4,
      highLoad: true,
      question: 'Walk me through the night of the party.',
      sentences: <String>[
        'We got to Ana\'s place around nine, I think, maybe a little after.',
        'I had two drinks over the night and spent most of it on the back porch talking with Chris.',
        'Around eleven-thirty I heard yelling inside, so I went in to see what was going on.',
        'I saw Ana and her boyfriend arguing by the kitchen, and I left about ten minutes later.',
        'I texted Chris when I got home, around midnight, to say I made it back.',
      ],
      answer: Challenge.clean,
      insight: '"I think, maybe a little after" sounds like hedging, but admitting uncertainty about a minor time is a truth marker, not a tell. The "I" never drops, the tense stays past, and the times connect from nine to midnight. High-load statements can be clean too.',
    ),
    Challenge.statement(
      id: 'vc1',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'Did you tell anyone about the layoffs before the announcement?',
      sentences: <String>[
        'No, I didn\'t tell anyone.',
        'I found out in the managers\' meeting on Tuesday, along with the rest of the team.',
        'My wife asked me that night why I seemed stressed, and I said it was a work thing I couldn\'t discuss.',
      ],
      answer: Challenge.clean,
      insight: 'A direct denial, no qualifiers, no distancing, and an unflattering detail (seeming stressed) volunteered unprompted. It reads as a committed, truthful account.',
    ),
    Challenge.statement(
      id: 'vc2',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'How do you know Mr. Ellis?',
      sentences: <String>[
        'Robert and I worked together at the bank for about six years.',
        'We had lunch every few weeks, and I went to his daughter\'s wedding in June.',
        'I haven\'t talked to Robert since he moved to Denver in the fall.',
      ],
      answer: Challenge.clean,
      insight: 'He uses the name "Robert" consistently, with no switch to "that man" or "that guy". Specific shared history and a clear timeline: no verbal tells here.',
    ),
    Challenge.statement(
      id: 'vc3',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'Did you damage the rental car?',
      sentences: <String>[
        'Yes, I scraped the back bumper on a parking post on Saturday.',
        'I was backing out of a tight spot at the grocery store on Elm.',
        'I took photos right away and sent them to the rental company that afternoon.',
        'The agent told me to report it again when I returned the car, so I did.',
        'I have the email and the photos on my phone if you want to see them.',
      ],
      answer: Challenge.clean,
      insight: 'An admission, not a denial: "Yes, I scraped the bumper." Owned actions, past tense, a checkable timeline and evidence offered. Offering proof isn\'t a tell when it\'s specific and checkable.',
    ),
    Challenge.statement(
      id: 'dc1',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'You text a friend: "Did you finish the last of my coffee?"',
      sentences: <String>[
        'yes sorry!! I had the last cup this morning',
        'I\'ll grab a new bag on my way home tonight',
        'the dark roast one right?',
      ],
      answer: Challenge.clean,
      insight: 'A direct admission and a concrete fix. Short, casual texts can be completely clean.',
    ),
    Challenge.statement(
      id: 'dc2',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'A coworker replies after you ask why the report is late.',
      sentences: <String>[
        'That\'s on me, I underestimated how long the data cleanup would take.',
        'I finished the charts yesterday and I\'m writing the summary now.',
        'You\'ll have it by 3 p.m. today, and I\'ll flag anything that looks off.',
      ],
      answer: Challenge.clean,
      insight: 'Ownership ("that\'s on me"), specifics and a checkable deadline. No minimizing, no qualifiers, no blame-shifting.',
    ),
    Challenge.statement(
      id: 'dc3',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'An online review of a local plumber.',
      sentences: <String>[
        'I called on Tuesday morning about a leak under our kitchen sink.',
        'They gave me a two-hour window and showed up about twenty minutes late.',
        'The plumber, Dave, replaced a corroded fitting and explained what had happened.',
        'The bill was a bit more than the quote because of an extra part, which he showed me.',
        'Overall I\'d use them again, but I wish they had called about running late.',
      ],
      answer: Challenge.clean,
      insight: 'Real reviews mix positives with small negatives (late arrival, a higher bill), name specifics and skip the superlatives. No "trust me", no "best ever". This one is clean.',
    ),

    // ── MORE CLEAN CASES ───────────────────────────────────────────────────
    Challenge.baseline(
      id: 'bc4',
      flag: Flag.cleanBaseline,
      context: 'Jamal is asked about a missing laptop.\n\nBASELINE: Jamal tugs his collar and rubs his eyes a lot (he says the office air is dry). He speaks in a steady, medium voice.',
      moments: <String>[
        'Asked if he took the laptop → tugs his collar, rubs his eyes: "No. I never even saw it."',
        'Asked where he sat that day → rubs his eyes, steady voice: "By the window, like always."',
        'Asked who left the office last → steady and even, names Carla and the cleaner.',
        'Asked if he\'d agree to a bag search → tugs his collar, shrugs: "Sure, go ahead."',
        'Asked about the cleaners → the lights flicker; he looks up, then answers in his steady voice.',
      ],
      answer: Challenge.clean,
      insight: 'This is the classic trap: a "No" with a collar tug and eye rubbing looks guilty, but both are Jamal\'s baseline. With no change from normal, there\'s no signal. Even looking up at the flickering lights had an outside cause.',
    ),
    Challenge.baseline(
      id: 'bc5',
      flag: Flag.cleanBaseline,
      context: 'Lucy is asked about a dented rental car.\n\nBASELINE: Lucy speaks softly, avoids eye contact and picks at her nails. She has done this since she sat down.',
      moments: <String>[
        'Asked if she dented the car → looks down, picks at a nail: "No. It was there when I got it."',
        'Asked where she parked it → soft voice, eyes down: "Hotel garage, level three."',
        'Asked if she took photos at pickup → picks at her nails: "No, I didn\'t think to."',
        'Asked when she returned it → glances away, softly: "Sunday, around noon."',
        'Asked about the rental desk → her phone alarm goes off; she fumbles to stop it, apologizing.',
      ],
      answer: Challenge.clean,
      insight: 'Looking down and fidgeting feel guilty, but they\'re Lucy\'s normal. Admitting she didn\'t take photos, which doesn\'t help her case, is consistent with honesty. Even fumbling with her phone alarm had an outside cause.',
    ),
    Challenge.baseline(
      id: 'bc6',
      flag: Flag.cleanBaseline,
      highLoad: true,
      context: 'Owen, 15, is questioned about a fire alarm pulled as a prank.\n\nBASELINE: Owen bounces his knee, laughs nervously after every answer and touches his neck whenever the topic is personal.',
      moments: <String>[
        'Asked if he pulled the alarm → knee bouncing, nervous laugh: "No way, I was in class."',
        'Asked about his parents → touches his neck, laughs: "My mom will kill me for being here."',
        'Asked which class he was in → bounces his knee, laughs: "Chemistry. Mr. Patel."',
        'Asked who might have done it → knee bouncing, a shrug, nervous laugh: "No clue."',
        'Asked about lunch → the school bell rings; he jumps, laughs, keeps bouncing his knee.',
      ],
      answer: Challenge.clean,
      insight: 'A nervous teenager in the principal\'s office: everything here matched his baseline, including touching his neck on a personal topic. Nervous isn\'t guilty, even in high-load cases. Even jumping at the bell had an outside cause.',
    ),
    Challenge.baseline(
      id: 'bc7',
      flag: Flag.cleanBaseline,
      highLoad: true,
      context: 'Diane is asked about a missing deposit bag.\n\nBASELINE: Diane is precise and calm. She pauses before every answer, speaks in full sentences and keeps her hands folded.',
      moments: <String>[
        'Asked if she took the deposit → pauses, hands folded: "No, I did not take it."',
        'Asked when she last saw it → pauses: "At 5:10, when I put it in the drop safe."',
        'Asked who has the safe code → pauses, then names herself and the manager.',
        'Asked if she\'s ever been short before → pauses: "Once, in 2019, by twelve dollars."',
        'Asked about her drive home → she sneezes, excuses herself, then pauses and answers.',
      ],
      answer: Challenge.clean,
      insight: 'Pauses can feel like stalling, but Diane pauses before everything. Precise answers and volunteering an old shortage against herself fit honesty. Even the sneeze had an outside cause.',
    ),
    Challenge.statement(
      id: 'sc4',
      flag: Flag.cleanStatement,
      level: 4,
      question: 'Where were you on Saturday night?',
      sentences: <String>[
        'I was at my cousin\'s birthday dinner at Rosa\'s on Fifth from about seven to ten.',
        'After dinner, around ten, I drove my cousin home because she\'d had a few drinks.',
        'I got back to my place around eleven and went to sleep.',
      ],
      answer: Challenge.clean,
      insight: 'Trap: "After dinner" isn\'t a temporal gap here, because the time is given and the next step connects. Phrases like "after that" are only a flag when they hide time.',
    ),
    Challenge.statement(
      id: 'sc5',
      flag: Flag.cleanStatement,
      level: 4,
      question: 'Did you break the window?',
      sentences: <String>[
        'No, I didn\'t break it.',
        'I heard the glass go while I was in the garage, and I came out and found a baseball on the floor.',
        'I think it was the kids next door, but I didn\'t see who threw it.',
      ],
      answer: Challenge.clean,
      insight: 'A direct denial, and "I think… but I didn\'t see" is honest uncertainty instead of an accusation dressed up as fact. Clean.',
    ),
    Challenge.statement(
      id: 'sc6',
      flag: Flag.cleanStatement,
      level: 4,
      highLoad: true,
      question: 'Tell me about the morning the van was stolen.',
      sentences: <String>[
        'I got to the lot at 6:30 and the van was parked in its usual spot.',
        'I went inside, made coffee and checked the schedule with Pete.',
        'Around seven I went back out to load it, and it was gone.',
        'I remember I actually laughed, because I thought Pete was messing with me.',
        'Then I called the owner and the police, in that order, a few minutes after seven.',
      ],
      answer: Challenge.clean,
      insight: 'Past tense throughout, a consistent "I", connected times and an odd, unflattering detail (laughing). That last part is a truth marker, not a red flag.',
    ),
    Challenge.statement(
      id: 'sc7',
      flag: Flag.cleanStatement,
      level: 4,
      highLoad: true,
      question: 'Did you take the client\'s files home?',
      sentences: <String>[
        'Yes, I took two folders home on Thursday night.',
        'I know it\'s against policy, and I should have asked first.',
        'I needed to finish the Ramirez summary before Friday morning.',
        'I brought them back Friday at eight and put them in the cabinet.',
        'Lisa saw me put them back, if you want to check.',
      ],
      answer: Challenge.clean,
      insight: 'An admission that hurts the speaker plus specific, checkable details. Offering a named witness is fine when it\'s specific. No flaw here.',
    ),
    Challenge.statement(
      id: 'vc4',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'Did you use the company card for personal purchases?',
      sentences: <String>[
        'No, I didn\'t.',
        'I only used it for the client dinner in March and the hotel in Denver.',
        'Both receipts are in the expense system with the client names on them.',
      ],
      answer: Challenge.clean,
      insight: 'Trap: "only" isn\'t minimizing here. It limits the list to two specific, checkable charges. Minimizing shrinks an admitted act ("just a little"); this narrows facts.',
    ),
    Challenge.statement(
      id: 'vc5',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      question: 'What happened between you and Ms. Lopez?',
      sentences: <String>[
        'Maria and I disagreed in the budget meeting about the hiring plan.',
        'I raised my voice, which I regret, and I apologized to her afterward.',
        'Maria and I talked again on Friday and we\'re fine now.',
      ],
      answer: Challenge.clean,
      insight: 'He uses "Maria" throughout with no switch to distancing language, and admits something unflattering. Clean.',
    ),
    Challenge.statement(
      id: 'vc6',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'Did you tell the client about the merger before it was announced?',
      sentences: <String>[
        'No, I didn\'t tell them anything about the merger.',
        'They asked me on the phone if something big was coming, and I said I couldn\'t comment.',
        'I wrote that call up in my notes the same day, around four.',
        'Looking back, "I can\'t comment" might have sounded like a yes.',
        'You can check my notes and the call log from that afternoon.',
      ],
      answer: Challenge.clean,
      insight: 'A direct denial, then a worry that works against him (it might have sounded like a yes). Honest second-guessing isn\'t a verbal tell.',
    ),
    Challenge.statement(
      id: 'vc7',
      flag: Flag.cleanStatement,
      level: 5,
      prompt: 'Tap the sentence with the verbal tell, if there is one.',
      highLoad: true,
      question: 'Were you at the warehouse on Sunday?',
      sentences: <String>[
        'Yes, I stopped by for about twenty minutes around two.',
        'I forgot my lunch cooler on Friday and needed it back.',
        'I let myself in with my key, grabbed the cooler from the break room and left.',
        'I didn\'t see anyone else there, but the loading door was already open.',
        'I texted my supervisor about the open door when I got home.',
      ],
      answer: Challenge.clean,
      insight: 'He admits being there, gives a reason and a time, and volunteers a detail that could cast suspicion on him (the open door). Clean.',
    ),
    Challenge.statement(
      id: 'dc4',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'Your roommate texts after you ask who left the stove on.',
      sentences: <String>[
        'that was me, sorry!! I was making eggs and got distracted by a call',
        'I\'ll be more careful from now on',
        'want me to grab dinner tonight to make up for it?',
      ],
      answer: Challenge.clean,
      insight: 'Direct ownership and a concrete apology. Short, casual texts can be completely clean.',
    ),
    Challenge.statement(
      id: 'dc5',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      question: 'An online review of a barber shop.',
      sentences: <String>[
        'I got a fade here on Tuesday afternoon, about a 15 minute wait.',
        'Marco took his time and asked how short I wanted the sides.',
        'It was \$35, a bit pricey, but I\'d go back.',
      ],
      answer: Challenge.clean,
      insight: 'Specific, mixed and measured: a wait time, a name, a mild complaint. No superlatives and no "trust me".',
    ),
    Challenge.statement(
      id: 'dc6',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'A coworker\'s email after you ask why the client got the wrong price.',
      sentences: <String>[
        'Hi! That one\'s my mistake, I pulled the price from last year\'s sheet.',
        'I noticed it this morning when the client replied with a question.',
        'I\'ve already sent them a corrected quote and copied you on it.',
        'I also added a note to the template so it doesn\'t happen again.',
        'Sorry for the hassle, and let me know if you want to talk it through.',
      ],
      answer: Challenge.clean,
      insight: 'Ownership in the first line, a specific cause and specific fixes. A long, friendly message can be completely clean.',
    ),
    Challenge.statement(
      id: 'dc7',
      flag: Flag.cleanStatement,
      level: 8,
      prompt: 'Tap the line with the red flag, if there is one.',
      highLoad: true,
      question: 'A friend replies after you ask if they told anyone your secret.',
      sentences: <String>[
        'No, I didn\'t tell anyone.',
        'Sam asked me if something was going on with you, and I told him to ask you.',
        'I think Sam noticed you were upset at the party, that\'s probably why.',
        'I\'m sorry if that made things weird.',
        'Let me know if you want me to say anything to Sam.',
      ],
      answer: Challenge.clean,
      insight: 'A direct denial, then a detail that could look bad for them (Sam asked). Volunteering it is a sign of honesty.',
    ),
  ];
}

// ════════════════════════════════════════════════════════════════════════════
//  GAME STATE (gamification + adaptive engine), all in memory
// ════════════════════════════════════════════════════════════════════════════

class QuestReward {
  const QuestReward({
    required this.bonusIp,
    required this.flawless,
    required this.healedHeart,
    required this.streakExtended,
  });

  final int bonusIp;
  final bool flawless;
  final bool healedHeart;
  final bool streakExtended;
}

class GameState extends ChangeNotifier {
  GameState({AppStore? store}) : _store = store ?? AppStore.memoryOnly() {
    _restore(_store.load());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final AppStore _store;
  bool _dirty = false;

  /// Memory Gym progress, saved with everything else.
  final MemoryState memory = MemoryState();

  /// Practice hub: best scores, questions to review, daily case.
  final Map<String, int> practiceBest = <String, int>{};
  final Set<String> mistakes = <String>{};
  int? dailyDoneDay;

  int get highestUnlockedLevel => Curriculum.nodes[math.min(unlockedIndex, Curriculum.nodes.length - 1)].level;

  void _trackMistake(Challenge c, bool correct) {
    if (!Curriculum.byId.containsKey(c.id)) return; // generated cases can't be replayed
    if (correct) {
      mistakes.remove(c.id);
    } else {
      mistakes.add(c.id);
    }
  }

  /// Practice answers train the profile and earn IP, but never cost hearts.
  void recordPractice(Challenge c, {required bool correct, required int ip}) {
    totalAnswered++;
    flagAttempts[c.flag] = flagAttempts[c.flag]! + 1;
    _recentResults.add(correct);
    if (_recentResults.length > rollingWindow) _recentResults.removeAt(0);
    if (correct) {
      totalCorrect++;
    } else {
      flagMisses[c.flag] = flagMisses[c.flag]! + 1;
      typeMisses[c.type] = typeMisses[c.type]! + 1;
    }
    insightPoints += ip;
    _trackMistake(c, correct);
    _changed();
  }

  /// Returns true for a new personal best.
  bool reportPracticeScore(String key, int value) {
    if (value <= (practiceBest[key] ?? 0)) return false;
    practiceBest[key] = value;
    _changed();
    return true;
  }

  /// Returns true if today's bonus was awarded.
  bool completeDaily(int bonus) {
    _touchStreak();
    final today = dayIndex();
    if (dailyDoneDay == today) {
      _changed();
      return false;
    }
    dailyDoneDay = today;
    insightPoints += bonus;
    _changed();
    return true;
  }

  void touchPracticeStreak() {
    _touchStreak();
    _changed();
  }

  static const int maxHearts = 3;
  static const Duration heartRegenInterval = Duration(minutes: 2);
  static const int refillCost = 30;
  static const int ipCorrect = 10;
  static const int ipCorrectHighLoad = 20;
  static const int ipCorrectRetry = 5;
  static const int completionBonus = 20;
  static const int flawlessBonus = 15;

  /// Difficulty scaling looks at the last [rollingWindow] answers.
  static const int rollingWindow = 10;
  static const int minSamplesForScaling = 4;
  static const double highLoadThreshold = 0.7;

  int hearts = maxHearts;
  int insightPoints = 0;
  int streak = 0;
  int? _lastActiveDay;

  /// Index of the furthest unlocked node. Every node before it is completed.
  int unlockedIndex = 0;
  final Set<String> completedNodeIds = <String>{};

  int totalAnswered = 0;
  int totalCorrect = 0;
  final List<bool> _recentResults = <bool>[];

  /// Weakness calibration profile.
  final Map<Flag, int> flagAttempts = <Flag, int>{for (final f in Flag.values) f: 0};
  final Map<Flag, int> flagMisses = <Flag, int>{for (final f in Flag.values) f: 0};
  final Map<ChallengeType, int> typeMisses = <ChallengeType, int>{for (final t in ChallengeType.values) t: 0};

  DateTime? _nextHeartAt;
  Timer? _ticker;

  // ── Derived values ──────────────────────────────────────────────────────

  double get rollingAccuracy {
    if (_recentResults.isEmpty) return 0;
    return _recentResults.where((r) => r).length / _recentResults.length;
  }

  double get lifetimeAccuracy => totalAnswered == 0 ? 0 : totalCorrect / totalAnswered;

  /// Above 80% recent accuracy, new questions swap to High Cognitive Load.
  bool get highLoadActive =>
      _recentResults.length >= minSamplesForScaling && rollingAccuracy > highLoadThreshold;

  Duration? get timeToNextHeart {
    final next = _nextHeartAt;
    if (next == null || hearts >= maxHearts) return null;
    final remaining = next.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get canAffordRefill => insightPoints >= refillCost;

  /// The flag missed most often (ties go to the lower accuracy).
  Flag? get weakestFlag {
    Flag? worst;
    var worstMisses = 0;
    var worstAccuracy = 2.0;
    for (final flag in Flag.values) {
      final misses = flagMisses[flag]!;
      if (misses == 0) continue;
      final attempts = flagAttempts[flag]!;
      final accuracy = attempts == 0 ? 0.0 : (attempts - misses) / attempts;
      if (misses > worstMisses || (misses == worstMisses && accuracy < worstAccuracy)) {
        worst = flag;
        worstMisses = misses;
        worstAccuracy = accuracy;
      }
    }
    return worst;
  }

  NodeStatus statusOf(int index) {
    final node = Curriculum.nodes[index];
    if (completedNodeIds.contains(node.id)) return NodeStatus.completed;
    if (index <= unlockedIndex) return NodeStatus.current;
    return NodeStatus.locked;
  }

  // ── Mutations ───────────────────────────────────────────────────────────

  /// Records an answer and returns the IP earned for it.
  int recordAnswer(Challenge challenge, {required bool correct, required bool isRetry}) {
    totalAnswered++;
    flagAttempts[challenge.flag] = flagAttempts[challenge.flag]! + 1;
    _recentResults.add(correct);
    if (_recentResults.length > rollingWindow) _recentResults.removeAt(0);

    var gain = 0;
    if (correct) {
      totalCorrect++;
      gain = isRetry ? ipCorrectRetry : (challenge.highLoad ? ipCorrectHighLoad : ipCorrect);
      insightPoints += gain;
    } else {
      flagMisses[challenge.flag] = flagMisses[challenge.flag]! + 1;
      typeMisses[challenge.type] = typeMisses[challenge.type]! + 1;
      if (hearts > 0) hearts--;
      _nextHeartAt ??= DateTime.now().add(heartRegenInterval);
    }
    _trackMistake(challenge, correct);
    _changed();
    return gain;
  }

  QuestReward completeQuest({required int nodeIndex, required bool flawless}) {
    final node = Curriculum.nodes[nodeIndex];
    final bonus = completionBonus + (flawless ? flawlessBonus : 0);
    insightPoints += bonus;

    final firstClear = completedNodeIds.add(node.id);
    if (firstClear && nodeIndex >= unlockedIndex) {
      unlockedIndex = nodeIndex + 1;
    }

    final streakExtended = _touchStreak();

    var healed = false;
    if (hearts < maxHearts) {
      hearts++;
      healed = true;
      if (hearts >= maxHearts) _nextHeartAt = null;
    }

    _changed();
    return QuestReward(
      bonusIp: bonus,
      flawless: flawless,
      healedHeart: healed,
      streakExtended: streakExtended,
    );
  }

  bool refillHearts() {
    if (!canAffordRefill || hearts >= maxHearts) return false;
    insightPoints -= refillCost;
    hearts = maxHearts;
    _nextHeartAt = null;
    _changed();
    return true;
  }

  bool _touchStreak() {
    final today = dayIndex();
    final last = _lastActiveDay;
    if (last == today) return false;
    streak = (last != null && today - last == 1) ? streak + 1 : 1;
    _lastActiveDay = today;
    return true;
  }

  // ── Memory Gym ──────────────────────────────────────────────────────────

  void recordMemoryTrial(MemoryDrill drill, {required bool passed, required int levelDelta, required int ip}) {
    memory.applyTrial(drill, passed: passed, delta: levelDelta);
    insightPoints += ip;
    _changed();
  }

  /// Returns true if this session extended the day streak.
  bool completeMemorySession(MemoryDrill drill) {
    memory.finishSession(drill, dayIndex());
    final extended = _touchStreak();
    _changed();
    return extended;
  }

  void reviewCard(String id, {required bool knew}) {
    memory.review(id, knew: knew, today: dayIndex());
    if (knew) insightPoints += 1;
    _changed();
  }

  // ── Saving ──────────────────────────────────────────────────────────────

  void _changed() {
    _dirty = true;
    notifyListeners();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'hearts': hearts,
        'ip': insightPoints,
        'streak': streak,
        'lastDay': _lastActiveDay,
        'unlocked': unlockedIndex,
        'completed': completedNodeIds.toList(),
        'answered': totalAnswered,
        'correct': totalCorrect,
        'recent': _recentResults,
        'attempts': <String, int>{for (final e in flagAttempts.entries) e.key.name: e.value},
        'misses': <String, int>{for (final e in flagMisses.entries) e.key.name: e.value},
        'typeMisses': <String, int>{for (final e in typeMisses.entries) e.key.name: e.value},
        'nextHeart': _nextHeartAt?.millisecondsSinceEpoch,
        'memory': memory.toJson(),
        'practiceBest': practiceBest,
        'mistakes': mistakes.toList(),
        'dailyDone': dailyDoneDay,
      };

  @visibleForTesting
  void restoreFrom(Map<String, dynamic> data) => _restore(data);

  void _restore(Map<String, dynamic>? data) {
    if (data == null) return;
    try {
      hearts = _readInt(data['hearts'], maxHearts).clamp(0, maxHearts);
      insightPoints = math.max(0, _readInt(data['ip'], 0));
      streak = math.max(0, _readInt(data['streak'], 0));
      final last = data['lastDay'];
      _lastActiveDay = last is int ? last : null;
      if (_lastActiveDay == null || dayIndex() - _lastActiveDay! > 1) streak = 0;
      unlockedIndex = _readInt(data['unlocked'], 0).clamp(0, Curriculum.nodes.length);
      final nodeIds = Curriculum.nodes.map((n) => n.id).toSet();
      final completed = data['completed'];
      if (completed is List) completedNodeIds.addAll(completed.whereType<String>().where(nodeIds.contains));
      totalAnswered = _readInt(data['answered'], 0);
      totalCorrect = _readInt(data['correct'], 0);
      final recent = data['recent'];
      if (recent is List) _recentResults.addAll(recent.whereType<bool>().take(rollingWindow));
      final flags = Flag.values.asNameMap();
      _readCounts(data['attempts'], flagAttempts, flags);
      _readCounts(data['misses'], flagMisses, flags);
      _readCounts(data['typeMisses'], typeMisses, ChallengeType.values.asNameMap());
      final next = data['nextHeart'];
      if (next is int && hearts < maxHearts) _nextHeartAt = DateTime.fromMillisecondsSinceEpoch(next);
      final mem = data['memory'];
      if (mem is Map<String, dynamic>) memory.restore(mem);
      _readCounts(data['practiceBest'], practiceBest, <String, String>{for (final m in PracticeMode.values) m.name: m.name});
      final saved = data['mistakes'];
      if (saved is List) mistakes.addAll(saved.whereType<String>().where(Curriculum.byId.containsKey));
      final daily = data['dailyDone'];
      dailyDoneDay = daily is int ? daily : null;
    } catch (_) {
      // A damaged save keeps whatever loaded cleanly; the rest stays default.
    }
  }

  void _persist() {
    _dirty = false;
    _store.save(toJson());
  }

  void _tick() {
    if (_dirty) _persist();
    if (hearts >= maxHearts) {
      _nextHeartAt = null;
      return;
    }
    final now = DateTime.now();
    _nextHeartAt ??= now.add(heartRegenInterval);
    if (!now.isBefore(_nextHeartAt!)) {
      hearts++;
      _nextHeartAt = hearts < maxHearts ? now.add(heartRegenInterval) : null;
      _dirty = true;
    }
    notifyListeners(); // keeps the regen countdown live
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_dirty) _persist();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  QUEST ENGINE
// ════════════════════════════════════════════════════════════════════════════

class QuestItem {
  QuestItem(this.challenge, {this.isRetry = false});
  final Challenge challenge;
  final bool isRetry;
}

class QuestSession {
  QuestSession({required this.nodeIndex, required List<QuestItem> items, this.calibratedFlag})
      : queue = items,
        baseCount = items.length,
        usedIds = items.map((i) => i.challenge.id).toSet();

  final int nodeIndex;
  final List<QuestItem> queue;
  final int baseCount;
  final Set<String> usedIds;

  /// For review nodes: the weakness this session was built to drill.
  final Flag? calibratedFlag;

  int position = 0;
  int cleared = 0;
  int answers = 0;
  int correctAnswers = 0;
  int answerIp = 0;
  int bonusIp = 0;
  int highLoadServed = 0;

  SkillNode get node => Curriculum.nodes[nodeIndex];
  QuestItem get current => queue[position];
  bool get isFinished => position >= queue.length;
  bool get flawless => answers > 0 && answers == correctAnswers;
  double get progress => baseCount == 0 ? 1 : cleared / baseCount;
  double get accuracy => answers == 0 ? 0 : correctAnswers / answers;
  int get totalIp => answerIp + bonusIp;

  void registerAnswer(QuestItem item, {required bool correct, required int gain, required math.Random rng}) {
    answers++;
    answerIp += gain;
    if (correct) {
      correctAnswers++;
      cleared++;
    } else {
      // Missed challenges repeat at the end of the loop.
      queue.add(QuestItem(item.challenge.shuffled(rng), isRetry: true));
    }
  }

  /// Difficulty scaling: if the player is above 70% accuracy, swap the
  /// upcoming standard question for a High Cognitive Load variant of the same
  /// level (same flag when possible). Returns true if a swap happened.
  bool escalateCurrentIfNeeded(GameState game, math.Random rng) {
    final item = current;
    if (item.isRetry || item.challenge.highLoad || !game.highLoadActive) return false;

    if (item.challenge.type == ChallengeType.baseline) {
      queue[position] = QuestItem(BaselineGenerator.generate(rng, hard: true, focus: item.challenge.flag).shuffled(rng));
      highLoadServed++;
      return true;
    }

    final candidates = Curriculum.challenges
        .where((c) => c.highLoad && c.level == item.challenge.level && !usedIds.contains(c.id))
        .toList();
    if (candidates.isEmpty) return false;

    final sameFlag = candidates.where((c) => c.flag == item.challenge.flag).toList();
    final pool = sameFlag.isNotEmpty ? sameFlag : candidates;
    final pick = pool[rng.nextInt(pool.length)];

    usedIds.add(pick.id);
    queue[position] = QuestItem(pick.shuffled(rng));
    highLoadServed++;
    return true;
  }
}

class QuestBuilder {
  QuestBuilder._();

  static QuestSession build(int nodeIndex, GameState game, math.Random rng) {
    final node = Curriculum.nodes[nodeIndex];
    if (!node.isReview) {
      final pool = Curriculum.challenges.where((c) => !c.highLoad && c.level == node.level).toList()..shuffle(rng);
      return QuestSession(
        nodeIndex: nodeIndex,
        items: pool.take(node.questLength).map((c) => QuestItem(BaselineGenerator.live(c, rng).shuffled(rng))).toList(),
      );
    }

    // Review node: weakness-calibrated.
    final pool = Curriculum.challenges.where((c) => !c.highLoad && c.level <= node.level).toList();
    var focus = game.weakestFlag;
    if (focus != null && !pool.any((c) => c.flag == focus)) focus = null;

    final picks = <Challenge>[];
    if (focus != null) {
      // Guarantee extra reps on the weakest flag.
      final drills = pool.where((c) => c.flag == focus).toList()..shuffle(rng);
      picks.addAll(drills.take(2));
    }
    final remaining = pool.where((c) => !picks.contains(c)).toList();
    picks.addAll(_weightedSample<Challenge>(
      remaining,
      node.questLength - picks.length,
      (c) => _weaknessWeight(c, game, focus),
      rng,
    ));
    picks.shuffle(rng);

    return QuestSession(
      nodeIndex: nodeIndex,
      items: picks.map((c) => QuestItem(BaselineGenerator.live(c, rng).shuffled(rng))).toList(),
      calibratedFlag: focus,
    );
  }

  /// Weight grows with misses on the flag and on the question layout.
  static double _weaknessWeight(Challenge c, GameState game, Flag? focus) {
    var weight = 1.0 + 3.0 * game.flagMisses[c.flag]! + 1.0 * game.typeMisses[c.type]!;
    if (focus != null && c.flag == focus) weight += 4;
    return weight;
  }

  static List<T> _weightedSample<T>(List<T> pool, int count, double Function(T) weightOf, math.Random rng) {
    final remaining = List<T>.of(pool);
    final result = <T>[];
    while (result.length < count && remaining.isNotEmpty) {
      final weights = remaining.map(weightOf).toList();
      final total = weights.fold<double>(0, (sum, w) => sum + w);
      var roll = rng.nextDouble() * total;
      var chosen = remaining.length - 1;
      for (var i = 0; i < remaining.length; i++) {
        roll -= weights[i];
        if (roll <= 0) {
          chosen = i;
          break;
        }
      }
      result.add(remaining.removeAt(chosen));
    }
    return result;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  APP ROOT
// ════════════════════════════════════════════════════════════════════════════

class ColdReadingApp extends StatefulWidget {
  const ColdReadingApp({super.key, required this.store});
  final AppStore store;

  @override
  State<ColdReadingApp> createState() => _ColdReadingAppState();
}

class _ColdReadingAppState extends State<ColdReadingApp> {
  late final GameState _game = GameState(store: widget.store);

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Reading',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Palette.green,
          brightness: Brightness.dark,
          surface: Palette.surface,
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Palette.surface,
          indicatorColor: Palette.blue.withAlpha(60),
        ),
      ),
      home: HomeShell(game: _game),
    );
  }
}

/// Two sections: the Cold Reading tree and the Memory Gym.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.game});
  final GameState game;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          MindTreeScreen(game: widget.game),
          PracticeHubScreen(game: widget.game),
          MemoryGymScreen(game: widget.game),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Cold Reading',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Practice',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: 'Memory',
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MIND TREE DASHBOARD
// ════════════════════════════════════════════════════════════════════════════

class MindTreeScreen extends StatefulWidget {
  const MindTreeScreen({super.key, required this.game});
  final GameState game;

  @override
  State<MindTreeScreen> createState() => _MindTreeScreenState();
}

class _MindTreeScreenState extends State<MindTreeScreen> {
  static const List<double> _zigzag = <double>[0, 56, 84, 56, 0, -56, -84, -56];

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    game.removeListener(_onGameChanged);
    super.dispose();
  }

  void _onGameChanged() {
    if (mounted) setState(() {});
  }

  void _openNode(int index) {
    final node = Curriculum.nodes[index];
    final status = game.statusOf(index);
    if (status == NodeStatus.locked) {
      HapticFeedback.heavyImpact();
      final previous = Curriculum.nodes[index - 1];
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: Palette.surfaceHigh,
          content: Text('🔒 Complete "${previous.title}" to unlock this node.',
              style: const TextStyle(color: Palette.textPrimary)),
        ));
      return;
    }
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => NodePreviewSheet(
        node: node,
        status: status,
        game: game,
        onStart: () {
          Navigator.of(sheetContext).pop();
          _startQuest(index);
        },
      ),
    );
  }

  Future<void> _startQuest(int index) async {
    if (game.hearts <= 0) {
      final ready = await _showNoHeartsDialog();
      if (!ready || !mounted) return;
    }
    final unlockedBefore = game.unlockedIndex;
    final completed = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => QuestScreen(game: game, nodeIndex: index),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (completed == true &&
        game.unlockedIndex > unlockedBefore &&
        game.unlockedIndex < Curriculum.nodes.length) {
      final next = Curriculum.nodes[game.unlockedIndex];
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          backgroundColor: Palette.surfaceHigh,
          content: Text('🔓 Unlocked: ${next.title}', style: const TextStyle(color: Palette.textPrimary)),
        ));
    }
  }

  Future<bool> _showNoHeartsDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final wait = game.timeToNextHeart;
        return AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('💔 Out of hearts', style: TextStyle(color: Palette.textPrimary)),
          content: Text(
            wait == null
                ? 'Rest up before your next quest.'
                : 'Your next heart regenerates in ${formatDuration(wait)}.\n\n'
                    'Or spend ${GameState.refillCost} IP to refill all hearts now.',
            style: const TextStyle(color: Palette.textMuted),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('WAIT'),
            ),
            TextButton(
              onPressed: game.canAffordRefill
                  ? () {
                      game.refillHearts();
                      Navigator.of(dialogContext).pop(true);
                    }
                  : null,
              child: Text('REFILL (${GameState.refillCost} IP)'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _openProfile() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => CalibrationProfileSheet(game: game),
    );
  }

  List<Widget> _buildTree() {
    final widgets = <Widget>[
      const _HeroTitle(),
      if (game.highLoadActive)
        const InfoBanner(
          icon: Icons.bolt,
          color: Palette.purple,
          text: 'High Cognitive Load is ON. Your accuracy is above 70%, so new questions bury the flags deeper.',
          padding: EdgeInsets.only(top: 12),
        ),
    ];

    int? lastLevel;
    for (var i = 0; i < Curriculum.nodes.length; i++) {
      final node = Curriculum.nodes[i];
      if (node.level != lastLevel) {
        lastLevel = node.level;
        final levelIndices = <int>[
          for (var j = 0; j < Curriculum.nodes.length; j++)
            if (Curriculum.nodes[j].level == node.level) j,
        ];
        final cleared = levelIndices.where((j) => game.statusOf(j) == NodeStatus.completed).length;
        widgets.add(LevelBanner(
          level: Curriculum.level(node.level),
          cleared: cleared,
          total: levelIndices.length,
          unlocked: game.statusOf(levelIndices.first) != NodeStatus.locked,
        ));
      }
      final color = node.isReview ? Palette.gold : Curriculum.level(node.level).color;
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Transform.translate(
            offset: Offset(_zigzag[i % _zigzag.length], 0),
            child: SkillNodeTile(
              node: node,
              status: game.statusOf(i),
              color: color,
              onTap: () => _openNode(i),
            ),
          ),
        ),
      ));
    }

    final allDone = game.completedNodeIds.length == Curriculum.nodes.length;
    widgets.add(Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Text(
        allDone
            ? '🎓 Certified Cold Reader.\nReplay any node to keep your edge sharp.'
            : 'Climb the tree to unlock the Master Class.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Palette.textMuted, fontSize: 14, height: 1.4),
      ),
    ));
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            StatsHeader(game: game, onProfileTap: _openProfile),
            const Divider(height: 1, thickness: 1, color: Palette.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                children: _buildTree(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Cold Reading',
          style: TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 4),
        Text(
          'Read people. Spot deception. Master the statement.',
          style: TextStyle(color: Palette.textMuted, fontSize: 14),
        ),
      ],
    );
  }
}

// ── Persistent header ─────────────────────────────────────────────────────

class StatsHeader extends StatelessWidget {
  const StatsHeader({super.key, required this.game, required this.onProfileTap});
  final GameState game;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.background,
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      child: Row(
        children: <Widget>[
          StatPill(
            emoji: '🔥',
            label: '${game.streak}',
            color: Palette.orange,
            tooltip: 'Day streak',
          ),
          const SizedBox(width: 8),
          TweenAnimationBuilder<int>(
            tween: IntTween(end: game.insightPoints),
            duration: const Duration(milliseconds: 700),
            builder: (context, value, _) => StatPill(
              emoji: '💡',
              label: '$value IP',
              color: Palette.blue,
              tooltip: 'Insight Points',
            ),
          ),
          const Spacer(),
          HeartsMeter(hearts: game.hearts, nextHeartIn: game.timeToNextHeart),
          IconButton(
            tooltip: 'Calibration profile',
            onPressed: onProfileTap,
            icon: const Icon(Icons.insights, color: Palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.emoji, required this.label, required this.color, required this.tooltip});
  final String emoji;
  final String label;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(36),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class HeartsMeter extends StatelessWidget {
  const HeartsMeter({super.key, required this.hearts, this.nextHeartIn});
  final int hearts;
  final Duration? nextHeartIn;

  @override
  Widget build(BuildContext context) {
    final countdown = nextHeartIn;
    return Tooltip(
      message: 'Hearts: lose one per wrong answer',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < GameState.maxHearts; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: AnimatedScale(
                    scale: i < hearts ? 1 : 0.82,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      i < hearts ? Icons.favorite : Icons.favorite_border,
                      color: i < hearts ? Palette.red : Palette.lockedIcon,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
          if (countdown != null)
            Text(
              '+1 in ${formatDuration(countdown)}',
              style: const TextStyle(color: Palette.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

// ── Tree pieces ───────────────────────────────────────────────────────────

class LevelBanner extends StatelessWidget {
  const LevelBanner({
    super.key,
    required this.level,
    required this.cleared,
    required this.total,
    required this.unlocked,
  });

  final LevelInfo level;
  final int cleared;
  final int total;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? level.color : Palette.locked;
    return Container(
      margin: const EdgeInsets.only(top: 22, bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[BoxShadow(color: darken(color, 0.15), offset: const Offset(0, 4))],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'LEVEL ${level.number}',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  level.title,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(level.subtitle, style: TextStyle(color: Colors.white.withAlpha(225), fontSize: 13.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: <Widget>[
              Icon(unlocked ? Icons.menu_book : Icons.lock, color: Colors.white, size: 28),
              const SizedBox(height: 4),
              Text('$cleared/$total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class SkillNodeTile extends StatelessWidget {
  const SkillNodeTile({
    super.key,
    required this.node,
    required this.status,
    required this.color,
    required this.onTap,
  });

  final SkillNode node;
  final NodeStatus status;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = status == NodeStatus.locked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (status == NodeStatus.current)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Palette.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 2),
            ),
            child: Text(
              'START',
              style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1.2),
            ),
          ),
        SkillNodeButton(node: node, status: status, color: color, onTap: onTap),
        const SizedBox(height: 8),
        SizedBox(
          width: 150,
          child: Text(
            node.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: locked ? Palette.lockedIcon : Palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class SkillNodeButton extends StatefulWidget {
  const SkillNodeButton({
    super.key,
    required this.node,
    required this.status,
    required this.color,
    required this.onTap,
  });

  final SkillNode node;
  final NodeStatus status;
  final Color color;
  final VoidCallback onTap;

  @override
  State<SkillNodeButton> createState() => _SkillNodeButtonState();
}

class _SkillNodeButtonState extends State<SkillNodeButton> with SingleTickerProviderStateMixin {
  static const double _size = 78;
  static const double _depth = 7;

  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant SkillNodeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.status == NodeStatus.current) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.status == NodeStatus.locked;
    final face = locked ? Palette.locked : widget.color;
    final edge = darken(face, locked ? 0.08 : 0.18);

    final button = GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: SizedBox(
        width: _size,
        height: _size + _depth,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _size,
              child: DecoratedBox(decoration: BoxDecoration(color: edge, shape: BoxShape.circle)),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 80),
              left: 0,
              right: 0,
              top: _pressed ? _depth : 0,
              height: _size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: face,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withAlpha(locked ? 10 : 45), width: 3),
                ),
                child: Icon(
                  locked ? Icons.lock : widget.node.icon,
                  color: locked ? Palette.lockedIcon : Colors.white,
                  size: 34,
                ),
              ),
            ),
            if (widget.status == NodeStatus.completed)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Palette.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.background, width: 3),
                  ),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.07 * Curves.easeInOut.transform(_pulse.value),
        child: child,
      ),
      child: button,
    );
  }
}

class NodePreviewSheet extends StatelessWidget {
  const NodePreviewSheet({
    super.key,
    required this.node,
    required this.status,
    required this.game,
    required this.onStart,
  });

  final SkillNode node;
  final NodeStatus status;
  final GameState game;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final level = Curriculum.level(node.level);
    final color = node.isReview ? Palette.gold : level.color;
    final weakest = game.weakestFlag;
    final type = level.type;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SheetHandle(),
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 26,
                  backgroundColor: color,
                  child: Icon(node.icon, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        node.isReview
                            ? (node.id == 'exam' ? 'FINAL EXAM · ALL LEVELS' : 'REVIEW · LEVELS 1–${node.level}')
                            : 'LEVEL ${level.number} · ${level.title.toUpperCase()}',
                        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        node.title,
                        style: const TextStyle(color: Palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(node.description, style: const TextStyle(color: Palette.textMuted, fontSize: 15, height: 1.4)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _Chip(icon: Icons.bolt, text: '${node.questLength} challenges'),
                _Chip(
                  icon: node.isReview ? Icons.shuffle : type.icon,
                  text: node.isReview ? 'Mixed layouts' : type.label,
                ),
                if (status == NodeStatus.completed) const _Chip(icon: Icons.replay, text: 'Replay'),
                if (game.highLoadActive) const _Chip(icon: Icons.psychology, text: 'High load active'),
              ],
            ),
            if (node.isReview && weakest != null) ...<Widget>[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.track_changes,
                color: Palette.gold,
                text: 'Calibrated: this review drills your weakest flag, ${weakest.label}.',
              ),
            ],
            const SizedBox(height: 20),
            ChunkyButton(
              label: status == NodeStatus.completed ? 'Practice again' : 'Start quest',
              color: color,
              onPressed: onStart,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: Palette.textMuted),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Palette.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(3)),
      ),
    );
  }
}

// ── Calibration profile ───────────────────────────────────────────────────

class CalibrationProfileSheet extends StatelessWidget {
  const CalibrationProfileSheet({super.key, required this.game});
  final GameState game;

  String _pct(double value) => '${(value * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final weakest = game.weakestFlag;
    final anyData = game.totalAnswered > 0;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const _SheetHandle(),
              const Text(
                'Calibration Profile',
                style: TextStyle(color: Palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your weakness map. Review nodes automatically drill the flags you miss most.',
                style: TextStyle(color: Palette.textMuted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(child: _MiniStat(label: 'Lifetime', value: anyData ? _pct(game.lifetimeAccuracy) : '–')),
                  const SizedBox(width: 10),
                  Expanded(child: _MiniStat(label: 'Last 10', value: anyData ? _pct(game.rollingAccuracy) : '–')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: 'Mode',
                      value: game.highLoadActive ? '⚡ High' : 'Standard',
                      color: game.highLoadActive ? Palette.purple : Palette.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (weakest != null)
                InfoBanner(
                  icon: Icons.track_changes,
                  color: Palette.red,
                  text: 'Weakest flag: ${weakest.label} (missed ${game.flagMisses[weakest]}×). '
                      'It will show up more often in review nodes.',
                ),
              if (!anyData)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No data yet. Finish a quest to start calibrating.',
                    style: TextStyle(color: Palette.textMuted, fontSize: 15),
                  ),
                ),
              for (final type in ChallengeType.values)
                if (Flag.values.any((f) => f.family == type && game.flagAttempts[f]! > 0)) ...<Widget>[
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Icon(type.icon, size: 18, color: Palette.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        type.label.toUpperCase(),
                        style: const TextStyle(
                          color: Palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final flag in Flag.values)
                    if (flag.family == type && game.flagAttempts[flag]! > 0)
                      _FlagRow(
                        flag: flag,
                        attempts: game.flagAttempts[flag]!,
                        misses: game.flagMisses[flag]!,
                        isWeakest: flag == weakest,
                      ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color = Palette.textPrimary});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.border),
      ),
      child: Column(
        children: <Widget>[
          FittedBox(
            child: Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Palette.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.flag, required this.attempts, required this.misses, required this.isWeakest});
  final Flag flag;
  final int attempts;
  final int misses;
  final bool isWeakest;

  @override
  Widget build(BuildContext context) {
    final accuracy = attempts == 0 ? 0.0 : (attempts - misses) / attempts;
    final barColor = accuracy >= 0.8 ? Palette.green : (accuracy >= 0.5 ? Palette.orange : Palette.red);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  isWeakest ? '🎯 ${flag.label}' : flag.label,
                  style: TextStyle(
                    color: isWeakest ? Palette.red : Palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Text(
                '${attempts - misses}/$attempts · $misses missed',
                style: const TextStyle(color: Palette.textMuted, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: accuracy,
              minHeight: 8,
              backgroundColor: Palette.background,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  QUEST SCREEN
// ════════════════════════════════════════════════════════════════════════════

enum QuestPhase { answering, feedback, complete, outOfHearts }

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key, required this.game, required this.nodeIndex});
  final GameState game;
  final int nodeIndex;

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> with SingleTickerProviderStateMixin {
  final math.Random _rng = math.Random();
  late final QuestSession _session;
  late final AnimationController _sheetController;
  late final Animation<Offset> _sheetOffset;

  QuestPhase _phase = QuestPhase.answering;
  Set<int> _selection = <int>{};
  bool _lastCorrect = false;
  int _lastGain = 0;
  bool _justEscalated = false;
  int _itemSerial = 0;
  QuestReward? _reward;

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _sheetOffset = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
    );
    _session = QuestBuilder.build(widget.nodeIndex, game, _rng);
    _justEscalated = _session.escalateCurrentIfNeeded(game, _rng);
    game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    game.removeListener(_onGameChanged);
    _sheetController.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    if (mounted) setState(() {});
  }

  Color get _accent {
    final node = _session.node;
    return node.isReview ? Palette.gold : Curriculum.level(node.level).color;
  }

  bool get _canCheck =>
      _phase == QuestPhase.answering && _selection.length == _session.current.challenge.requiredSelections;

  // ── Interaction ─────────────────────────────────────────────────────────

  void _onOptionTap(int index) {
    if (_phase != QuestPhase.answering) return;
    final challenge = _session.current.challenge;
    if (challenge.isMultiSelect) {
      if (_selection.contains(index)) {
        setState(() => _selection = <int>{..._selection}..remove(index));
      } else if (_selection.length < challenge.requiredSelections) {
        setState(() => _selection = <int>{..._selection, index});
      } else {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 1400),
            backgroundColor: Palette.surfaceHigh,
            content: Text('Pick exactly 3. Deselect one first.',
                style: TextStyle(color: Palette.textPrimary)),
          ));
        return;
      }
    } else {
      setState(() => _selection = <int>{index});
    }
    HapticFeedback.selectionClick();
  }

  void _checkAnswer() {
    if (!_canCheck) return;
    final item = _session.current;
    final correct = setEquals(_selection, item.challenge.correct);
    final gain = game.recordAnswer(item.challenge, correct: correct, isRetry: item.isRetry);
    _session.registerAnswer(item, correct: correct, gain: gain, rng: _rng);
    if (correct) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _lastCorrect = correct;
      _lastGain = gain;
      _phase = QuestPhase.feedback;
    });
    _sheetController.forward(from: 0);
  }

  Future<void> _continueFromFeedback() async {
    await _sheetController.reverse();
    if (!mounted) return;
    if (game.hearts <= 0) {
      setState(() => _phase = QuestPhase.outOfHearts);
      return;
    }
    _advance();
  }

  void _advance() {
    _session.position++;
    if (_session.isFinished) {
      final reward = game.completeQuest(nodeIndex: widget.nodeIndex, flawless: _session.flawless);
      _session.bonusIp = reward.bonusIp;
      setState(() {
        _reward = reward;
        _phase = QuestPhase.complete;
      });
      return;
    }
    final escalated = _session.escalateCurrentIfNeeded(game, _rng);
    setState(() {
      _selection = <int>{};
      _justEscalated = escalated;
      _itemSerial++;
      _phase = QuestPhase.answering;
    });
  }

  void _refillAndResume() {
    if (game.refillHearts()) _advance();
  }

  Future<void> _handleBack() async {
    if (_phase == QuestPhase.complete) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_phase == QuestPhase.outOfHearts) {
      Navigator.of(context).pop(false);
      return;
    }
    final quit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Abandon this quest?', style: TextStyle(color: Palette.textPrimary)),
        content: const Text(
          'IP you\'ve already earned is kept, but this node won\'t be marked complete.',
          style: TextStyle(color: Palette.textMuted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('KEEP GOING'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('QUIT', style: TextStyle(color: Palette.red)),
          ),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop(false);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (_phase) {
      QuestPhase.answering || QuestPhase.feedback => _buildChallengeBody(),
      QuestPhase.complete => QuestCompleteView(
          session: _session,
          reward: _reward!,
          game: game,
          onContinue: () => Navigator.of(context).pop(true),
        ),
      QuestPhase.outOfHearts => OutOfHeartsView(
          game: game,
          onRefill: _refillAndResume,
          onResume: _advance,
          onQuit: () => Navigator.of(context).pop(false),
        ),
    };

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Palette.background,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: KeyedSubtree(key: ValueKey<QuestPhase>(_phaseGroup), child: body),
          ),
        ),
      ),
    );
  }

  /// Answering and feedback share one layout, so they share a switcher key.
  QuestPhase get _phaseGroup => _phase == QuestPhase.feedback ? QuestPhase.answering : _phase;

  Widget _buildChallengeBody() {
    final item = _session.current;
    final challenge = item.challenge;
    final revealed = _phase == QuestPhase.feedback;
    final calibrated = _session.calibratedFlag;
    final screenHeight = MediaQuery.of(context).size.height;

    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            _QuestTopBar(
              progress: _session.progress,
              hearts: game.hearts,
              color: _accent,
              onClose: _handleBack,
            ),
            if (item.isRetry)
              const InfoBanner(
                icon: Icons.replay,
                color: Palette.orange,
                text: 'Second look: you missed this one earlier.',
                padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              )
            else if (challenge.highLoad)
              InfoBanner(
                icon: Icons.bolt,
                color: Palette.purple,
                text: _justEscalated
                    ? 'HIGH COGNITIVE LOAD: accuracy above 70%. Flags are now buried in ordinary dialogue.'
                    : 'High Cognitive Load scenario',
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              ),
            if (calibrated != null && challenge.flag == calibrated && !item.isRetry)
              InfoBanner(
                icon: Icons.track_changes,
                color: Palette.gold,
                text: 'Calibration drill: one of your weak spots',
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[...previousChildren, if (currentChild != null) currentChild],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.12, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: SingleChildScrollView(
                  key: ValueKey<int>(_itemSerial),
                  padding: EdgeInsets.fromLTRB(16, 12, 16, revealed ? screenHeight * 0.55 : 24),
                  child: ChallengeView(
                    challenge: challenge,
                    selection: _selection,
                    revealed: revealed,
                    onOptionTap: _onOptionTap,
                  ),
                ),
              ),
            ),
            if (_phase == QuestPhase.answering)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ChunkyButton(
                  label: _checkLabel(challenge),
                  color: Palette.green,
                  onPressed: _canCheck ? _checkAnswer : null,
                ),
              ),
          ],
        ),
        if (_phase == QuestPhase.feedback)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _sheetOffset,
              child: FeedbackSheet(
                correct: _lastCorrect,
                challenge: challenge,
                ipGain: _lastGain,
                heartsLeft: game.hearts,
                onContinue: _continueFromFeedback,
              ),
            ),
          ),
      ],
    );
  }

  String _checkLabel(Challenge challenge) {
    if (challenge.isMultiSelect && _selection.length < challenge.requiredSelections) {
      return 'Select ${challenge.requiredSelections - _selection.length} more';
    }
    return 'Check answer';
  }
}

class _QuestTopBar extends StatelessWidget {
  const _QuestTopBar({required this.progress, required this.hearts, required this.color, required this.onClose});
  final double progress;
  final int hearts;
  final Color color;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Quit quest',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Palette.textMuted, size: 28),
          ),
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 14,
                  backgroundColor: Palette.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.favorite, color: Palette.red, size: 26),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Text(
              '$hearts',
              key: ValueKey<int>(hearts),
              style: const TextStyle(color: Palette.red, fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CHALLENGE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

enum OptionVisual { idle, selected, correct, wrong, missed }

class OptionStyle {
  const OptionStyle(this.fill, this.border, this.text, this.trailing);
  final Color fill;
  final Color border;
  final Color text;
  final IconData? trailing;

  static OptionStyle of(OptionVisual visual, {bool highlighter = false}) {
    return switch (visual) {
      OptionVisual.idle => const OptionStyle(Palette.surface, Palette.border, Palette.textPrimary, null),
      OptionVisual.selected => highlighter
          ? OptionStyle(Palette.highlight.withAlpha(55), Palette.highlight, const Color(0xFFFFF2B3), null)
          : OptionStyle(Palette.blue.withAlpha(45), Palette.blue, const Color(0xFF9EDFFF), null),
      OptionVisual.correct =>
        OptionStyle(Palette.green.withAlpha(50), Palette.green, const Color(0xFFB4F07F), Icons.check_circle),
      OptionVisual.wrong => OptionStyle(Palette.red.withAlpha(50), Palette.red, const Color(0xFFFFB0B0), Icons.cancel),
      OptionVisual.missed =>
        const OptionStyle(Palette.background, Palette.green, Color(0xFFB4F07F), Icons.check_circle_outline),
    };
  }
}

class ChallengeView extends StatelessWidget {
  const ChallengeView({
    super.key,
    required this.challenge,
    required this.selection,
    required this.revealed,
    required this.onOptionTap,
  });

  final Challenge challenge;
  final Set<int> selection;
  final bool revealed;
  final ValueChanged<int> onOptionTap;

  OptionVisual _visual(int i) {
    final selected = selection.contains(i);
    if (!revealed) return selected ? OptionVisual.selected : OptionVisual.idle;
    final isAnswer = challenge.correct.contains(i);
    if (isAnswer && selected) return OptionVisual.correct;
    if (isAnswer) return OptionVisual.missed;
    if (selected) return OptionVisual.wrong;
    return OptionVisual.idle;
  }

  VoidCallback? _tap(int i) => revealed ? null : () => onOptionTap(i);

  Widget _cleanTile() {
    final visual = _visual(Challenge.clean);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OptionTile(
        visual: visual,
        onTap: _tap(Challenge.clean),
        leading: Icon(
          Icons.verified_user,
          color: visual == OptionVisual.idle ? Palette.teal : OptionStyle.of(visual).border,
        ),
        text: challenge.cleanLabel,
        bold: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> body = switch (challenge.type) {
      ChallengeType.baseline => _baselineBody(),
      ChallengeType.microExpression => _microBody(),
      ChallengeType.cluster => _clusterBody(),
      ChallengeType.statement => _statementBody(),
      ChallengeType.scenario => _scenarioBody(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TypeTag(challenge: challenge),
        const SizedBox(height: 10),
        Text(
          challenge.prompt,
          style: const TextStyle(color: Palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25),
        ),
        const SizedBox(height: 16),
        ...body,
      ],
    );
  }

  List<Widget> _baselineBody() {
    return <Widget>[
      ContextCard(
        label: 'SUBJECT FILE',
        icon: Icons.person_search,
        text: challenge.context,
        accent: Palette.green,
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < challenge.options.length; i++)
        OptionTile(
          visual: _visual(i),
          onTap: _tap(i),
          leading: LetterBadge(letter: String.fromCharCode(65 + i), visual: _visual(i)),
          text: challenge.options[i],
        ),
      _cleanTile(),
    ];
  }

  List<Widget> _scenarioBody() {
    return <Widget>[
      ContextCard(
        label: 'CASE FILE',
        icon: Icons.policy,
        text: challenge.context,
        accent: Curriculum.level(challenge.level).color,
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < challenge.options.length; i++)
        OptionTile(
          visual: _visual(i),
          onTap: _tap(i),
          leading: LetterBadge(letter: String.fromCharCode(65 + i), visual: _visual(i)),
          text: challenge.options[i],
        ),
    ];
  }

  List<Widget> _microBody() {
    final rows = (challenge.options.length + 1) ~/ 2;
    return <Widget>[
      MicroFlashCard(
        description: challenge.context,
        exposure: Duration(seconds: challenge.highLoad ? 3 : 5),
        allowReflash: !challenge.highLoad,
        revealed: revealed,
      ),
      const SizedBox(height: 16),
      for (var r = 0; r < rows; r++)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var c = 0; c < 2; c++) ...<Widget>[
              if (c == 1) const SizedBox(width: 10),
              Expanded(
                child: r * 2 + c < challenge.options.length
                    ? OptionTile(
                        visual: _visual(r * 2 + c),
                        onTap: _tap(r * 2 + c),
                        minHeight: 64,
                        leading: Text(
                          kEmotionEmoji[challenge.options[r * 2 + c]] ?? '🙂',
                          style: const TextStyle(fontSize: 24),
                        ),
                        text: challenge.options[r * 2 + c],
                        bold: true,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
    ];
  }

  List<Widget> _clusterBody() {
    final remaining = challenge.requiredSelections - selection.length;
    final truth = challenge.flag == Flag.truthMarkers;
    return <Widget>[
      ContextCard(
        label: truth ? 'WITNESS ACCOUNT' : 'BEHAVIOR LOG',
        icon: truth ? Icons.record_voice_over : Icons.assignment,
        text: challenge.context,
        accent: Curriculum.level(challenge.level).color,
      ),
      const SizedBox(height: 14),
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              truth ? 'TRUTH MARKERS' : 'STRESS INDICATORS',
              style: const TextStyle(
                color: Palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: remaining == 0 ? Palette.purple.withAlpha(60) : Palette.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${selection.length}/${challenge.requiredSelections} selected',
              style: TextStyle(
                color: remaining == 0 ? Palette.purple : Palette.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < challenge.options.length; i++)
        OptionTile(
          visual: _visual(i),
          onTap: _tap(i),
          leading: CheckBadge(checked: selection.contains(i), visual: _visual(i)),
          text: challenge.options[i],
        ),
    ];
  }

  List<Widget> _statementBody() {
    final digital = challenge.level == 8;
    return <Widget>[
      InterviewerBubble(
        question: challenge.context,
        label: digital ? 'CONTEXT' : 'INTERVIEWER',
        icon: digital ? Icons.sms : Icons.mic,
        accent: Curriculum.level(challenge.level).color,
      ),
      const SizedBox(height: 16),
      Text(
        digital ? 'THE MESSAGE' : 'SUBJECT\'S STATEMENT',
        style: const TextStyle(
          color: Palette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < challenge.options.length; i++)
        OptionTile(
          visual: _visual(i),
          onTap: _tap(i),
          highlighter: true,
          leading: LetterBadge(letter: '${i + 1}', visual: _visual(i), highlighter: true),
          text: '"${challenge.options[i]}"',
          italic: true,
          footer: revealed && challenge.correct.contains(i)
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '🚩 ${challenge.flag.label}',
                    style: const TextStyle(color: Palette.green, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                )
              : null,
        ),
      _cleanTile(),
    ];
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.challenge});
  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final color = Curriculum.level(challenge.level).color;
    return Row(
      children: <Widget>[
        Icon(challenge.type.icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            challenge.type.label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
        ),
        if (challenge.highLoad) ...<Widget>[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Palette.purple, borderRadius: BorderRadius.circular(6)),
            child: const Text(
              '⚡ HIGH LOAD',
              style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ],
    );
  }
}

class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.visual,
    required this.onTap,
    required this.text,
    this.leading,
    this.footer,
    this.minHeight = 56,
    this.highlighter = false,
    this.italic = false,
    this.bold = false,
  });

  final OptionVisual visual;
  final VoidCallback? onTap;
  final String text;
  final Widget? leading;
  final Widget? footer;
  final double minHeight;
  final bool highlighter;
  final bool italic;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = OptionStyle.of(visual, highlighter: highlighter);
    final trailing = style.trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: style.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: style.border, width: 2),
            boxShadow: <BoxShadow>[BoxShadow(color: style.border, offset: const Offset(0, 3))],
          ),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[leading!, const SizedBox(width: 12)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      text,
                      style: TextStyle(
                        color: style.text,
                        fontSize: 15,
                        height: 1.35,
                        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (footer != null) footer!,
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                Icon(trailing, color: style.border, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LetterBadge extends StatelessWidget {
  const LetterBadge({super.key, required this.letter, required this.visual, this.highlighter = false});
  final String letter;
  final OptionVisual visual;
  final bool highlighter;

  @override
  Widget build(BuildContext context) {
    final style = OptionStyle.of(visual, highlighter: highlighter);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: style.border, width: 2),
      ),
      child: Text(letter, style: TextStyle(color: style.text, fontWeight: FontWeight.w900, fontSize: 14)),
    );
  }
}

class CheckBadge extends StatelessWidget {
  const CheckBadge({super.key, required this.checked, required this.visual});
  final bool checked;
  final OptionVisual visual;

  @override
  Widget build(BuildContext context) {
    final style = OptionStyle.of(visual);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: checked ? style.border : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: style.border, width: 2),
      ),
      child: checked ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
    );
  }
}

class ContextCard extends StatelessWidget {
  const ContextCard({
    super.key,
    required this.label,
    required this.icon,
    required this.text,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withAlpha(110), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: Palette.textPrimary, fontSize: 15.5, height: 1.45)),
        ],
      ),
    );
  }
}

class InterviewerBubble extends StatelessWidget {
  const InterviewerBubble({
    super.key,
    required this.question,
    this.label = 'INTERVIEWER',
    this.icon = Icons.mic,
    this.accent = Palette.orange,
  });
  final String question;
  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 22,
          backgroundColor: accent,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
                topLeft: Radius.circular(4),
              ),
              border: Border.all(color: accent.withAlpha(110), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                ),
                const SizedBox(height: 4),
                Text(
                  question,
                  style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w700, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Level 2 flash card: the description is only visible for a short exposure
/// window, like a real micro-expression. One re-flash is allowed.
class MicroFlashCard extends StatefulWidget {
  const MicroFlashCard({
    super.key,
    required this.description,
    required this.exposure,
    required this.revealed,
    this.allowReflash = true,
  });
  final String description;
  final Duration exposure;
  final bool revealed;
  final bool allowReflash;

  @override
  State<MicroFlashCard> createState() => _MicroFlashCardState();
}

class _MicroFlashCardState extends State<MicroFlashCard> with SingleTickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(vsync: this, duration: widget.exposure);
  late bool _reflashUsed = !widget.allowReflash;

  @override
  void initState() {
    super.initState();
    _timer.forward();
  }

  @override
  void didUpdateWidget(covariant MicroFlashCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed && _timer.isAnimating) _timer.stop();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _reflash() {
    if (_reflashUsed) return;
    HapticFeedback.selectionClick();
    setState(() => _reflashUsed = true);
    _timer.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _timer,
      builder: (context, _) {
        final hidden = _timer.isCompleted && !widget.revealed;
        final secondsLeft = ((1 - _timer.value) * widget.exposure.inMilliseconds / 1000).ceil();
        final text = Text(
          widget.description,
          style: const TextStyle(color: Palette.textPrimary, fontSize: 16.5, height: 1.45, fontWeight: FontWeight.w600),
        );

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Palette.blue.withAlpha(130), width: 2),
            boxShadow: <BoxShadow>[BoxShadow(color: Palette.blue.withAlpha(70), offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.flash_on, color: Palette.blue, size: 18),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'FLASH CARD',
                      style: TextStyle(color: Palette.blue, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2),
                    ),
                  ),
                  Text(
                    widget.revealed ? 'revealed' : (hidden ? 'faded' : '${secondsLeft}s'),
                    style: const TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: widget.revealed ? 1 : 1 - _timer.value,
                  minHeight: 5,
                  backgroundColor: Palette.background,
                  valueColor: const AlwaysStoppedAnimation<Color>(Palette.blue),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('🧑', style: TextStyle(fontSize: 34)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        if (hidden)
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                            child: text,
                          )
                        else
                          text,
                        if (hidden)
                          Positioned.fill(
                            child: Center(
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: Palette.surfaceHigh,
                                  foregroundColor: Palette.blue,
                                ),
                                onPressed: _reflashUsed ? null : _reflash,
                                icon: Icon(_reflashUsed ? Icons.visibility_off : Icons.replay),
                                label: Text(_reflashUsed ? 'Signal gone. Trust your read.' : 'Re-flash (1 left)'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  FEEDBACK SHEET
// ════════════════════════════════════════════════════════════════════════════

class FeedbackSheet extends StatelessWidget {
  const FeedbackSheet({
    super.key,
    required this.correct,
    required this.challenge,
    required this.ipGain,
    required this.heartsLeft,
    required this.onContinue,
    this.practice = false,
  });

  final bool correct;
  final Challenge challenge;
  final int ipGain;
  final int heartsLeft;
  final bool practice;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final background = correct ? Palette.feedbackGreen : Palette.feedbackRed;
    final maxInsightHeight = MediaQuery.of(context).size.height * 0.26;

    return Material(
      color: background,
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Icon(correct ? Icons.check : Icons.close, color: background, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    correct ? 'Sharp read!' : 'Signal missed',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(45), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    correct ? '+$ipGain IP' : (practice ? 'No heart lost' : '−1 ❤️'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!correct) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withAlpha(50), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'CORRECT ANSWER',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      challenge.correctAnswerText,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '${challenge.isClean ? '✅' : '🚩'} ${challenge.flag.label}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxInsightHeight),
              child: SingleChildScrollView(
                child: Text(
                  '🧠 ${challenge.insight}',
                  style: TextStyle(color: Colors.white.withAlpha(240), fontSize: 14.5, height: 1.45),
                ),
              ),
            ),
            if (!correct && !practice) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                heartsLeft > 0
                    ? '↻ Queued to repeat at the end of this quest · $heartsLeft ❤️ left'
                    : '↻ Queued to repeat · no hearts left',
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 16),
            ChunkyButton(
              label: 'Continue',
              color: Colors.white,
              textColor: background,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  QUEST COMPLETE & OUT OF HEARTS
// ════════════════════════════════════════════════════════════════════════════

class QuestCompleteView extends StatefulWidget {
  const QuestCompleteView({
    super.key,
    required this.session,
    required this.reward,
    required this.game,
    required this.onContinue,
  });

  final QuestSession session;
  final QuestReward reward;
  final GameState game;
  final VoidCallback onContinue;

  @override
  State<QuestCompleteView> createState() => _QuestCompleteViewState();
}

class _QuestCompleteViewState extends State<QuestCompleteView> with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _badge;
  late final Animation<double> _card;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _badge = CurvedAnimation(parent: _intro, curve: const Interval(0, 0.65, curve: Curves.elasticOut));
    _card = CurvedAnimation(parent: _intro, curve: const Interval(0.3, 1, curve: Curves.easeOutCubic));
    _intro.forward();
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final reward = widget.reward;
    final weakest = widget.game.weakestFlag;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 20),
                  ScaleTransition(
                    scale: _badge,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Palette.gold,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: darken(Palette.gold, 0.2), offset: const Offset(0, 6)),
                          BoxShadow(color: Palette.gold.withAlpha(90), blurRadius: 40, spreadRadius: 6),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('🏆', style: TextStyle(fontSize: 58)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Quest Complete!',
                    style: TextStyle(color: Palette.gold, fontSize: 30, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(session.node.title, style: const TextStyle(color: Palette.textMuted, fontSize: 16)),
                  const SizedBox(height: 22),
                  FadeTransition(
                    opacity: _card,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(_card),
                      child: _summaryCard(session, reward, weakest),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(label: 'Continue', color: Palette.green, onPressed: widget.onContinue),
        ],
      ),
    );
  }

  Widget _summaryCard(QuestSession session, QuestReward reward, Flag? weakest) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.border, width: 2),
      ),
      child: Column(
        children: <Widget>[
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: session.totalIp),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              '+$value IP',
              style: const TextStyle(color: Palette.blue, fontSize: 42, fontWeight: FontWeight.w900),
            ),
          ),
          const Text(
            'INSIGHT POINTS EARNED',
            style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(child: _StatTile(emoji: '🎯', value: '${(session.accuracy * 100).round()}%', label: 'Accuracy')),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(emoji: '❤️', value: '${widget.game.hearts}/${GameState.maxHearts}', label: 'Hearts'),
              ),
              const SizedBox(width: 10),
              Expanded(child: _StatTile(emoji: '⚡', value: '${session.highLoadServed}', label: 'High load')),
            ],
          ),
          const SizedBox(height: 16),
          _BreakdownLine(label: 'Correct answers', value: '+${session.answerIp} IP'),
          const _BreakdownLine(label: 'Completion bonus', value: '+${GameState.completionBonus} IP'),
          if (reward.flawless) const _BreakdownLine(label: 'Flawless bonus', value: '+${GameState.flawlessBonus} IP'),
          if (reward.healedHeart) const _BreakdownLine(label: 'Heart restored', value: '+1 ❤️'),
          if (reward.streakExtended) _BreakdownLine(label: 'Day streak', value: '🔥 ${widget.game.streak}'),
          if (weakest != null) ...<Widget>[
            const SizedBox(height: 10),
            InfoBanner(
              icon: Icons.track_changes,
              color: Palette.gold,
              text: 'Calibration: your most-missed flag is ${weakest.label}. Review nodes will drill it more often.',
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.emoji, required this.value, required this.label});
  final String emoji;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: Palette.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: <Widget>[
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Palette.textMuted, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(color: Palette.textMuted, fontSize: 14.5))),
          Text(value, style: const TextStyle(color: Palette.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class OutOfHeartsView extends StatelessWidget {
  const OutOfHeartsView({
    super.key,
    required this.game,
    required this.onRefill,
    required this.onResume,
    required this.onQuit,
  });

  final GameState game;
  final VoidCallback onRefill;
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final wait = game.timeToNextHeart;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: <Widget>[
          const Spacer(),
          const Text('💔', style: TextStyle(fontSize: 84)),
          const SizedBox(height: 12),
          const Text(
            'Out of Hearts',
            style: TextStyle(color: Palette.red, fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            'Every analyst hits overload. Your missed challenges are still queued for this quest. '
            'Wait for a heart or refill to keep going.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.textMuted, fontSize: 15, height: 1.45),
          ),
          const SizedBox(height: 16),
          if (game.hearts == 0 && wait != null)
            Text(
              'Next heart in ${formatDuration(wait)}',
              style: const TextStyle(color: Palette.orange, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          const Spacer(),
          if (game.hearts > 0)
            ChunkyButton(label: 'Resume quest', color: Palette.green, onPressed: onResume)
          else
            ChunkyButton(
              label: game.canAffordRefill
                  ? 'Refill for ${GameState.refillCost} IP'
                  : 'Need ${GameState.refillCost} IP to refill',
              color: Palette.blue,
              onPressed: game.canAffordRefill ? onRefill : null,
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onQuit,
            child: const Text(
              'BACK TO MIND TREE',
              style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MEMORY GYM: MODEL
// ════════════════════════════════════════════════════════════════════════════

enum MemoryDrill {
  digits('Number Span', 'Chunking', Icons.dialpad, Palette.blue, 7, 4, 20, 'digits'),
  words('Story Chain', 'The link method', Icons.link, Palette.purple, 7, 4, 20, 'words'),
  palace('Memory Palace', 'Method of loci', Icons.account_balance, Palette.gold, 7, 4, 12, 'items'),
  faces('Names & Faces', 'Name hooks', Icons.badge, Palette.pink, 4, 3, 10, 'people'),
  kim("Kim's Game", 'Visual attention', Icons.grid_view, Palette.teal, 2, 1, 7, ''),
  snapshot('Person Snapshot', 'Observation recall', Icons.person_search, Palette.orange, 2, 1, 7, ''),
  review('Spaced Review', 'Retrieval & spacing', Icons.style, Palette.green, 0, 0, 0, '');

  const MemoryDrill(
    this.title,
    this.technique,
    this.icon,
    this.color,
    this.startLevel,
    this.minLevel,
    this.maxLevel,
    this.unit,
  );

  final String title;
  final String technique;
  final IconData icon;
  final Color color;
  final int startLevel;
  final int minLevel;
  final int maxLevel;
  final String unit;

  bool get leveled => maxLevel > 0;
  String levelLabel(int level) => unit.isEmpty ? 'Level $level' : '$level $unit';
}

class ReviewProgress {
  ReviewProgress(this.box, this.dueDay);
  final int box;
  final int dueDay;
}

class MemoryState {
  /// Days until the next review for each Leitner box.
  static const List<int> intervals = <int>[1, 1, 3, 7, 14, 30];
  static const int newCardsPerDay = 6;

  final Map<MemoryDrill, int> level = <MemoryDrill, int>{for (final d in MemoryDrill.values) d: d.startLevel};
  final Map<MemoryDrill, int> best = <MemoryDrill, int>{for (final d in MemoryDrill.values) d: 0};
  final Map<MemoryDrill, int> sessions = <MemoryDrill, int>{for (final d in MemoryDrill.values) d: 0};
  final Map<MemoryDrill, int> lastDoneDay = <MemoryDrill, int>{};
  final Map<String, ReviewProgress> cards = <String, ReviewProgress>{};
  int newCardsDay = -1;
  int newCardsToday = 0;

  bool doneToday(MemoryDrill d, int today) => lastDoneDay[d] == today;

  int newCardsLeft(int today) => math.max(0, newCardsPerDay - (newCardsDay == today ? newCardsToday : 0));

  List<StudyCard> reviewQueue(int today) {
    final due = MemoryContent.cards.where((c) {
      final p = cards[c.id];
      return p != null && p.dueDay <= today;
    }).toList()
      ..sort((a, b) => cards[a.id]!.dueDay.compareTo(cards[b.id]!.dueDay));
    final fresh = MemoryContent.cards.where((c) => !cards.containsKey(c.id)).take(newCardsLeft(today));
    return <StudyCard>[...due, ...fresh];
  }

  int learnedCards() => cards.values.where((p) => p.box >= 2).length;

  void applyTrial(MemoryDrill d, {required bool passed, required int delta}) {
    if (!d.leveled) return;
    final current = level[d]!;
    if (passed && current > best[d]!) best[d] = current;
    level[d] = (current + delta).clamp(d.minLevel, d.maxLevel);
  }

  void finishSession(MemoryDrill d, int today) {
    sessions[d] = sessions[d]! + 1;
    lastDoneDay[d] = today;
  }

  void review(String id, {required bool knew, required int today}) {
    final previous = cards[id];
    if (previous == null) {
      if (newCardsDay != today) {
        newCardsDay = today;
        newCardsToday = 0;
      }
      newCardsToday++;
    }
    final box = knew ? math.min((previous?.box ?? 0) + 1, intervals.length - 1) : 0;
    cards[id] = ReviewProgress(box, today + intervals[box]);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'level': <String, int>{for (final e in level.entries) e.key.name: e.value},
        'best': <String, int>{for (final e in best.entries) e.key.name: e.value},
        'sessions': <String, int>{for (final e in sessions.entries) e.key.name: e.value},
        'lastDone': <String, int>{for (final e in lastDoneDay.entries) e.key.name: e.value},
        'cards': <String, List<int>>{for (final e in cards.entries) e.key: <int>[e.value.box, e.value.dueDay]},
        'newDay': newCardsDay,
        'newCount': newCardsToday,
      };

  void restore(Map<String, dynamic> data) {
    final drills = MemoryDrill.values.asNameMap();
    _readCounts(data['level'], level, drills);
    _readCounts(data['best'], best, drills);
    _readCounts(data['sessions'], sessions, drills);
    _readCounts(data['lastDone'], lastDoneDay, drills);
    for (final d in MemoryDrill.values) {
      if (d.leveled) level[d] = level[d]!.clamp(d.minLevel, d.maxLevel);
    }
    final known = MemoryContent.cards.map((c) => c.id).toSet();
    final raw = data['cards'];
    if (raw is Map) {
      raw.forEach((Object? key, Object? value) {
        if (key is String && known.contains(key) && value is List && value.length == 2) {
          final box = value[0];
          final due = value[1];
          if (box is int && due is int) {
            cards[key] = ReviewProgress(box.clamp(0, intervals.length - 1), due);
          }
        }
      });
    }
    newCardsDay = _readInt(data['newDay'], -1);
    newCardsToday = _readInt(data['newCount'], 0);
  }
}

class LessonPage {
  const LessonPage(this.title, this.body, [this.example]);
  final String title;
  final String body;
  final String? example;
}

class StudyCard {
  const StudyCard(this.id, this.front, this.back);
  final String id;
  final String front;
  final String back;
}

class SnapshotCase {
  const SnapshotCase(this.place, this.text, this.questions);
  final String place;
  final String text;
  final List<SnapshotQuestion> questions;
}

/// The first option is the correct one; options are shuffled when shown.
class SnapshotQuestion {
  const SnapshotQuestion(this.question, this.options, this.explain);
  final String question;
  final List<String> options;
  final String explain;
}

class PalaceStop {
  const PalaceStop(this.emoji, this.name);
  final String emoji;
  final String name;
}

// ════════════════════════════════════════════════════════════════════════════
//  MEMORY GYM: CONTENT
// ════════════════════════════════════════════════════════════════════════════

class MemoryContent {
  MemoryContent._();

  static const Map<MemoryDrill, List<LessonPage>> lessons = <MemoryDrill, List<LessonPage>>{
    MemoryDrill.digits: <LessonPage>[
      LessonPage('Your working memory is small',
          'Most people can hold about four "chunks" in mind at once. Raw digits fill those slots fast, which is why 7 to 9 digits is where most people top out.'),
      LessonPage('Chunking',
          'Group digits into bigger units. Eight separate digits become three chunks. Phone numbers use the same trick.',
          '4 1 9 7 2 0 0 1  →  41 · 97 · 2001'),
      LessonPage('Make chunks mean something',
          'Turn chunks into things you already know: a year (1984), a famous number (911, 365), an age, a jersey number. Say them in a rhythm in your head.',
          '1 9 8 4 0 7 2 3  →  1984 (the book) · 07 (Bond) · 23 (Jordan)'),
      LessonPage('How the drill works',
          'A number flashes up, then you type it. Get it right and the next one is a digit longer; miss and it gets a digit shorter. Your level climbs as the skill sticks.'),
    ],
    MemoryDrill.words: <LessonPage>[
      LessonPage('Lists are hard, stories are easy',
          'Memory evolved for events, not lists. Linking items into one vivid story turns a list into a single event you can replay.'),
      LessonPage('Make it vivid',
          'Exaggerate size, add movement, sound and emotion, and make it absurd. A boring image fades; a ridiculous one sticks.'),
      LessonPage('Example',
          'Each item does something to the next one, so each word pulls up the one after it.',
          'piano, banana, rocket, sock  →  A PIANO crashes onto a giant BANANA, which blasts off like a ROCKET and lands in a smelly SOCK.'),
      LessonPage('How the drill works',
          'Study the words and build your story, then tap them in the right order from a mix that includes decoys.'),
    ],
    MemoryDrill.palace: <LessonPage>[
      LessonPage('The oldest memory technique',
          'Greek and Roman speakers memorized whole speeches by walking through a building in their mind. Memory champions still use it, and studies show it can greatly improve recall of lists.'),
      LessonPage('Your route',
          'Use your own home. The drill uses the same 12 stops every time, in this order: front door, coat hook, couch, TV, plant, dining table, kitchen sink, fridge, stove, bathroom mirror, bathtub, bed. Picture YOUR versions of each one.'),
      LessonPage('Place it, don\'t just see it',
          'At each stop, put the item there in a strange, vivid way. Make it interact with the spot.',
          'A giraffe stuck in your front door. A guitar on fire on your couch.'),
      LessonPage('Walk it back',
          'To recall, walk the route again in your mind and look at each stop. The items will be waiting. The same route can hold a new list every day.'),
    ],
    MemoryDrill.faces: <LessonPage>[
      LessonPage('Why names slip',
          'Usually the name was never stored: you were busy thinking about what to say next. The fix is attention plus a hook.'),
      LessonPage('Focus, repeat, hook',
          'Look at the face, say the name back ("Nice to meet you, Dana"), then link the name to an image tied to the face or the person.',
          'Dana → a Dalmatian. Mark → a marker behind his ear. Rosa → a rose in her hair.'),
      LessonPage('Hook the detail too',
          'Hang the fact on the same image, so one picture holds the face, the name and the detail.',
          'Dana the nurse: a Dalmatian in scrubs taking your pulse.'),
      LessonPage('How the drill works',
          'Meet a few people, then match faces to names and names to what you learned about them. More people join as you improve.'),
    ],
    MemoryDrill.kim: <LessonPage>[
      LessonPage("Kim's Game",
          'From Rudyard Kipling\'s novel Kim, where a spy in training memorizes trays of objects. Scouts, soldiers and police still use it to sharpen observation.'),
      LessonPage('Scan with a system',
          'Don\'t stare at random. Sweep each row left to right, name every item in your head, and notice patterns.',
          'Top row: two animals and a fruit. Middle: everything is round.'),
      LessonPage('How the drill works',
          'Study the grid, then spot what changed or what went missing. The grids grow as you improve.'),
    ],
    MemoryDrill.snapshot: <LessonPage>[
      LessonPage('Observation is memory',
          'You can\'t remember what you never noticed. Investigators train themselves to log specific details: clothing, hands, shoes, objects and posture.'),
      LessonPage('Head to toe, every time',
          'Use one fixed order so nothing gets skipped: face and hair → hands → clothing → shoes → objects and setting.'),
      LessonPage('Facts versus guesses',
          'Keep what you saw separate from what you infer. Mud on the shoes is a fact; "been walking off-road" is a guess. Questions test both, which is the core of cold reading.'),
      LessonPage('How the drill works',
          'Read the snapshot before it disappears, then answer from memory. Higher levels give you less time.'),
    ],
    MemoryDrill.review: <LessonPage>[
      LessonPage('The forgetting curve',
          'We forget most new information within days unless we review it, but each well-timed review makes the memory last much longer.'),
      LessonPage('Testing beats rereading',
          'Trying to recall an answer strengthens memory far more than reading it again. That\'s why you always see the question first.'),
      LessonPage('Spacing',
          'Cards you know come back after longer and longer gaps: 1, 3, 7, 14, then 30 days. Cards you miss come back tomorrow. A few minutes a day is enough.'),
      LessonPage('Be honest',
          'Only tap "Knew it" if you recalled the answer before flipping. Fooling the schedule only fools you.'),
    ],
  };

  static const List<String> words = <String>[
    'apple', 'anchor', 'balloon', 'banana', 'barrel', 'basket', 'bell', 'bicycle', 'blanket', 'boot',
    'bottle', 'bridge', 'broom', 'bucket', 'cactus', 'camel', 'candle', 'canoe', 'carrot', 'castle',
    'cat', 'chain', 'cheese', 'chimney', 'clock', 'cloud', 'coconut', 'comb', 'cookie', 'crown',
    'cup', 'diamond', 'dinosaur', 'dolphin', 'donut', 'drum', 'duck', 'eagle', 'egg', 'elephant',
    'envelope', 'feather', 'fence', 'flag', 'flashlight', 'fork', 'frog', 'ghost', 'giraffe', 'glove',
    'guitar', 'hammer', 'harp', 'helmet', 'honey', 'horse', 'igloo', 'iron', 'jacket', 'jellyfish',
    'kangaroo', 'kettle', 'key', 'kite', 'ladder', 'lamp', 'lemon', 'lion', 'lobster', 'magnet',
    'mirror', 'monkey', 'moon', 'mushroom', 'needle', 'nest', 'octopus', 'onion', 'owl', 'paddle',
    'parrot', 'peanut', 'pencil', 'penguin', 'piano', 'pillow', 'pineapple', 'pizza', 'pumpkin', 'rabbit',
    'robot', 'rocket', 'rope', 'saddle', 'scissors', 'shark', 'shovel', 'skateboard', 'snail', 'snowman',
    'sock', 'spider', 'spoon', 'statue', 'sword', 'tiger', 'toaster', 'tractor', 'trumpet', 'turtle',
    'umbrella', 'vase', 'violin', 'volcano', 'wagon', 'whale', 'whistle', 'window', 'zebra', 'tornado',
  ];

  static const List<PalaceStop> palaceRoute = <PalaceStop>[
    PalaceStop('🚪', 'front door'),
    PalaceStop('🧥', 'coat hook'),
    PalaceStop('🛋️', 'couch'),
    PalaceStop('📺', 'TV'),
    PalaceStop('🪴', 'plant'),
    PalaceStop('🍽️', 'dining table'),
    PalaceStop('🚰', 'kitchen sink'),
    PalaceStop('🧊', 'fridge'),
    PalaceStop('🔥', 'stove'),
    PalaceStop('🪞', 'bathroom mirror'),
    PalaceStop('🛁', 'bathtub'),
    PalaceStop('🛏️', 'bed'),
  ];

  static const List<PalaceStop> palaceItems = <PalaceStop>[
    PalaceStop('🎸', 'guitar'), PalaceStop('🦒', 'giraffe'), PalaceStop('🍕', 'pizza'), PalaceStop('🚀', 'rocket'),
    PalaceStop('🐙', 'octopus'), PalaceStop('🎈', 'balloon'), PalaceStop('🔨', 'hammer'), PalaceStop('🍌', 'banana'),
    PalaceStop('🐧', 'penguin'), PalaceStop('⏰', 'alarm clock'), PalaceStop('🧀', 'cheese'), PalaceStop('🎺', 'trumpet'),
    PalaceStop('🦈', 'shark'), PalaceStop('🌋', 'volcano'), PalaceStop('🧲', 'magnet'), PalaceStop('🥥', 'coconut'),
    PalaceStop('🐸', 'frog'), PalaceStop('👑', 'crown'), PalaceStop('🕯️', 'candle'), PalaceStop('🍩', 'donut'),
    PalaceStop('🐢', 'turtle'), PalaceStop('🔑', 'key'), PalaceStop('🥁', 'drum'), PalaceStop('🦉', 'owl'),
    PalaceStop('🍍', 'pineapple'), PalaceStop('⚓', 'anchor'), PalaceStop('🐘', 'elephant'), PalaceStop('🧸', 'teddy bear'),
    PalaceStop('🌵', 'cactus'), PalaceStop('🍉', 'watermelon'), PalaceStop('🦞', 'lobster'), PalaceStop('🛹', 'skateboard'),
    PalaceStop('🎃', 'pumpkin'), PalaceStop('🐝', 'bee'), PalaceStop('🦄', 'unicorn'), PalaceStop('🍦', 'ice cream'),
    PalaceStop('🐍', 'snake'), PalaceStop('🪁', 'kite'), PalaceStop('🦖', 'dinosaur'), PalaceStop('🎻', 'violin'),
    PalaceStop('🥚', 'egg'), PalaceStop('🐌', 'snail'), PalaceStop('💎', 'diamond'), PalaceStop('🦜', 'parrot'),
    PalaceStop('🚲', 'bicycle'), PalaceStop('☂️', 'umbrella'), PalaceStop('🧯', 'fire extinguisher'), PalaceStop('🪕', 'banjo'),
  ];

  static const List<String> palacePrompts = <String>[
    'Picture a giant {item} jammed into the {stop}.',
    'The {item} is on fire at the {stop}. Smell the smoke.',
    'Dozens of tiny copies of the {item} pour out of the {stop}.',
    'The {item} is dancing and singing at the {stop}.',
    'Your {stop} is made entirely out of {item}.',
    'The {item} explodes all over the {stop}. What a mess.',
    'A {item} the size of a car is sleeping on the {stop}.',
  ];

  static const List<String> faces = <String>[
    '👩‍🦰', '👨‍🦱', '👵', '👴', '🧔', '👩‍🦳', '👱‍♀️', '👨‍🦲', '🧑‍🦱', '👩‍🦱',
    '👱‍♂️', '🧓', '👨‍🦰', '👩‍🦲', '🧕', '🧑‍🦰', '👲', '👳', '👧', '👦',
  ];

  static const List<String> names = <String>[
    'Dana', 'Marcus', 'Priya', 'Leo', 'Grace', 'Omar', 'Hannah', 'Victor', 'Elena', 'Kenji',
    'Sofia', 'Ray', 'Tasha', 'Derek', 'Rosa', 'Nate', 'Maya', 'Ben', 'Claire', 'Raj',
    'Luis', 'Ava', 'Jordan', 'Kim', 'Tom', 'Nina', 'Sam', 'Iris', 'Felix', 'Mona',
    'Hugo', 'Zara', 'Owen', 'Lena', 'Paul', 'Ruby', 'Theo', 'Jade', 'Carl', 'Vera',
  ];

  static const List<String> jobs = <String>[
    'nurse', 'firefighter', 'chef', 'pilot', 'teacher', 'mechanic', 'lawyer', 'barista', 'dentist', 'carpenter',
    'photographer', 'accountant', 'florist', 'paramedic', 'librarian', 'plumber', 'architect', 'farmer', 'DJ', 'tailor',
  ];

  static const List<String> details = <String>[
    'has a dog named Pepper', 'just moved from Ohio', 'runs marathons', 'collects vinyl records',
    'is afraid of birds', 'speaks four languages', 'grew up on a sailboat', 'has twin daughters',
    'hates pickles', 'plays the cello', 'broke an arm skiing last year', 'is training for a triathlon',
    'bakes sourdough every Sunday', 'rides a vintage motorcycle', 'was on a game show once', 'keeps bees',
    'knits sweaters for a cat', 'volunteers at a food bank', 'climbed Mount Kilimanjaro', 'is learning to surf',
    'restores old clocks', 'has never seen snow', 'grows giant pumpkins', 'loves horror movies',
    "can solve a Rubik's cube", 'writes mystery novels', 'is allergic to cats', 'lived in Japan for two years',
  ];

  static const List<String> kimItems = <String>[
    '🍎', '🍌', '🍇', '🍓', '🥕', '🌽', '🍄', '🥨', '🧀', '🍩', '🍪', '🎂', '☕', '🐶', '🐱',
    '🐭', '🐰', '🦊', '🐻', '🐼', '🐸', '🐵', '🐔', '🐧', '🐙', '🦋', '🐢', '🐍', '🦀', '⚽',
    '🏀', '🎾', '🎲', '🎯', '🎸', '🎺', '🥁', '📷', '💡', '🔑', '🔨', '✂️', '📎', '🧲', '☂️',
    '🎈', '🎁', '👟', '🎩', '👓', '🌵', '🌻', '🌙', '⭐', '❄️', '🚗', '🚲', '✈️', '⛵', '⏰',
  ];

  static const List<SnapshotCase> snapshots = <SnapshotCase>[
    SnapshotCase('Coffee shop',
        'A man in his 40s sits alone by the window. Grey suit jacket, no tie, top button undone. Wedding ring on his left hand and a pale tan line on his right wrist where a watch would go. His laptop is open, but he keeps checking his phone and putting it face down. His paper cup has "DAVE" written on it. There\'s mud on the toe of his left shoe.',
        <SnapshotQuestion>[
          SnapshotQuestion('What name was on the cup?', <String>['Dave', 'Dan', 'Steve', 'Mike'], 'The cup said "DAVE".'),
          SnapshotQuestion('Where was the tan line?', <String>['Right wrist', 'Left wrist', 'Ring finger', 'Neck'],
              'A pale line on his right wrist, where a watch would go.'),
          SnapshotQuestion('Which inference is most reasonable?', <String>[
            'He usually wears a watch but isn\'t today',
            'He is left-handed',
            'He works as a lawyer',
            'He isn\'t married',
          ], 'The tan line is evidence of a habit. Nothing supports his job or handedness, and he wears a wedding ring.'),
        ]),
    SnapshotCase('Train platform',
        'A woman in her 20s carries a large hiking backpack with a rolled yoga mat strapped to the side. Red beanie, green rain jacket, black leggings. Two boarding passes stick out of her jacket pocket. She holds a paperback with the bookmark about three-quarters of the way through. Her right hand is bandaged across the knuckles.',
        <SnapshotQuestion>[
          SnapshotQuestion('What color was her beanie?', <String>['Red', 'Green', 'Black', 'Blue'],
              'Red beanie; the jacket was green.'),
          SnapshotQuestion('Which hand was bandaged?', <String>['Right', 'Left', 'Both', 'Neither'],
              'Her right hand, across the knuckles.'),
          SnapshotQuestion('What can you reasonably infer?', <String>[
            'She is probably traveling with someone',
            'She teaches yoga for a living',
            'She hurt her hand rock climbing',
            'She doesn\'t like her book',
          ], 'Two boarding passes suggest a companion. A yoga mat doesn\'t make her a teacher, and nothing explains the injury.'),
        ]),
    SnapshotCase('Hardware store',
        'An older man, maybe 70, in a faded blue baseball cap with an anchor logo. Flannel shirt with paint flecks on the sleeves. Reading glasses hang from a cord around his neck. His basket holds sandpaper, two paint brushes and wood glue. He pays in cash from a worn brown leather wallet and counts out exact change.',
        <SnapshotQuestion>[
          SnapshotQuestion('What logo was on his cap?', <String>['An anchor', 'An eagle', 'A fish', 'A star'],
              'A faded blue cap with an anchor logo.'),
          SnapshotQuestion('What was NOT in his basket?', <String>['A hammer', 'Sandpaper', 'Wood glue', 'Paint brushes'],
              'He had sandpaper, two brushes and wood glue. No hammer.'),
          SnapshotQuestion('Which inference is most reasonable?', <String>[
            'He\'s working on a painting or woodworking project',
            'He served in the navy',
            'He paints houses for a living',
            'He doesn\'t trust banks',
          ], 'The basket and paint flecks support a project. An anchor cap hints at the navy but doesn\'t establish it, and paying cash isn\'t distrust.'),
        ]),
    SnapshotCase('Clinic waiting room',
        'A teenage boy, about 16, in a soccer jersey with the number 9. Grass stains on both knees. One earbud in. His mother sits beside him filling out a form on a clipboard. He holds an ice pack against his left ankle, with the foot propped on the chair next to him.',
        <SnapshotQuestion>[
          SnapshotQuestion('What number was on his jersey?', <String>['9', '7', '11', '19'], 'Number 9.'),
          SnapshotQuestion('Which ankle had the ice pack?', <String>['Left', 'Right', 'Both', 'Neither'], 'His left ankle.'),
          SnapshotQuestion('Which inference is most reasonable?', <String>[
            'He hurt his ankle playing soccer recently',
            'He is the team captain',
            'He broke his leg',
            'He is skipping school',
          ], 'Jersey, grass stains and an iced ankle point to a recent soccer injury. Nothing shows a break or captaincy.'),
        ]),
    SnapshotCase('Office lobby',
        'A woman in her 30s in a navy blazer, her lanyard badge flipped backwards so the name doesn\'t show. She carries two coffees in a cardboard tray and a rolled-up poster tube under her arm. She\'s wearing white sneakers, but black heels stick out of her tote bag. She watches the elevator display and taps her foot.',
        <SnapshotQuestion>[
          SnapshotQuestion('What was under her arm?', <String>['A poster tube', 'An umbrella', 'A laptop', 'A newspaper'],
              'A rolled-up poster tube.'),
          SnapshotQuestion('What shoes was she wearing?', <String>['White sneakers', 'Black heels', 'Brown boots', 'Sandals'],
              'White sneakers. The heels were in her bag, a classic trap.'),
          SnapshotQuestion('Which inference is most reasonable?', <String>[
            'She plans to change shoes later',
            'She is hiding her identity',
            'She works as an architect',
            'She is late for a job interview',
          ], 'Heels in the bag suggest a change of shoes. Flipped badges usually just spin around, and a poster tube doesn\'t make her an architect.'),
        ]),
    SnapshotCase('Park bench',
        'A man in his 50s feeds pigeons from a paper bag. Brown corduroy jacket with elbow patches. A folded newspaper is open to the crossword, and there\'s a pen behind his right ear. A small dog\'s leash is looped around his wrist, but there\'s no dog in sight. His left shoelace is untied.',
        <SnapshotQuestion>[
          SnapshotQuestion('Where was the pen?', <String>['Behind his right ear', 'Behind his left ear', 'In his jacket pocket', 'On the bench'],
              'Behind his right ear.'),
          SnapshotQuestion('What page was the newspaper open to?', <String>['The crossword', 'Sports', 'Weather', 'Obituaries'],
              'The crossword.'),
          SnapshotQuestion('Which detail most deserves a follow-up question?', <String>[
            'The leash with no dog',
            'The elbow patches',
            'The pigeons',
            'The untied shoelace',
          ], 'Out-of-place details carry the most information. A leash with no dog raises a real question.'),
        ]),
    SnapshotCase('Bus stop at night',
        'A woman around 25 in purple hospital scrubs under an open black puffer jacket. Her ID badge is clipped to the scrubs pocket. She holds a takeout bag from "Golden Dragon" and yawns twice. Her sneakers have reflective strips, and a thermos sticks out of her backpack\'s side pocket.',
        <SnapshotQuestion>[
          SnapshotQuestion('What color were her scrubs?', <String>['Purple', 'Blue', 'Green', 'Pink'], 'Purple scrubs.'),
          SnapshotQuestion('Which restaurant was the takeout from?', <String>['Golden Dragon', 'Jade Garden', 'Lucky Star', 'Red Lantern'],
              '"Golden Dragon".'),
          SnapshotQuestion('Which inference is most reasonable?', <String>[
            'She probably just finished a long shift',
            'She is a surgeon',
            'She doesn\'t like cooking',
            'She lives alone',
          ], 'Scrubs, late hour, yawning and takeout fit the end of a shift. Her exact role and home life aren\'t shown.'),
        ]),
    SnapshotCase('Airport gate',
        'A man in his 30s in a wrinkled white shirt, sleeves rolled up, his tie stuffed into his shirt pocket. Two phones lie on the seat beside him, one in a rugged case. His carry-on has a faded luggage tag from Lisbon. He talks quietly into an earpiece and writes numbers on the back of his boarding pass.',
        <SnapshotQuestion>[
          SnapshotQuestion('Where was his tie?', <String>['Stuffed in his shirt pocket', 'Around his neck', 'In his bag', 'On the seat'],
              'Stuffed into his shirt pocket.'),
          SnapshotQuestion('Which city was on the luggage tag?', <String>['Lisbon', 'Madrid', 'Rome', 'Paris'], 'Lisbon.'),
          SnapshotQuestion('Which inference is most reasonable?', <String>[
            'He has had a long day of travel or work',
            'He is a spy',
            'He lives in Lisbon',
            'He trades stocks',
          ], 'The wrinkled shirt and loosened tie fit a long day. Two phones and numbers don\'t make him a spy or a trader, and a faded tag only shows a past trip.'),
        ]),
  ];

  static const List<StudyCard> cards = <StudyCard>[
    // Memory techniques
    StudyCard('m_chunk', 'What is chunking?',
        'Grouping items into meaningful units (41 · 97 · 2001) so working memory can hold more.'),
    StudyCard('m_link', 'How does the link (story) method work?',
        'Chain the items into one vivid, absurd story so the list becomes a single event.'),
    StudyCard('m_loci', 'How does a memory palace work?',
        'Place each item at a stop along a familiar route, then walk the route in your mind to recall them in order.'),
    StudyCard('m_names', 'What are three steps to remember a name?',
        'Focus on the face, say the name back, and hook it to an image (Dana → Dalmatian).'),
    StudyCard('m_testing', 'What is the testing effect?',
        'Trying to recall information strengthens memory more than rereading it.'),
    StudyCard('m_spacing', 'Why space out reviews?',
        'Reviewing just as you start to forget makes memories last much longer than cramming.'),
    // Cold Reading concepts
    StudyCard('f_vocal', 'What is a vocal shift, and what does it mean?',
        'A change in pitch, speed or volume from the person\'s own baseline, tied to one topic. A hot spot to probe, not proof of a lie.'),
    StudyCard('f_gesture', 'What is gesture suppression?',
        'A normally expressive person suddenly stops gesturing. It can signal cognitive load or the freeze response.'),
    StudyCard('f_pacify', 'What are pacifiers?',
        'Self-soothing touches (neck, collar, face, forehead) the brain uses to calm itself after a stressor.'),
    StudyCard('f_ocular', 'Name two eye-behavior shifts worth noting.',
        'Blink-rate surges and eye blocking. For someone who rarely makes eye contact, a sudden stare counts too.'),
    StudyCard('f_posture', 'What do the feet and torso tell you?',
        'We turn them toward what we like and away from what we want to escape. Suddenly freezing is also a stress response.'),
    StudyCard('f_contempt', 'What makes contempt unique among expressions?',
        'It\'s one-sided: one lip corner tightens and lifts. It signals moral superiority.'),
    StudyCard('f_fear', 'How do you tell fear from surprise?',
        'Fear pulls the raised brows together and stretches the lips sideways. Surprise has curved brows and a loose, dropped jaw.'),
    StudyCard('f_disgust', 'What does disgust look like?', 'A wrinkled nose and raised upper lip, on both sides of the face.'),
    StudyCard('f_anger', 'What is an early sign of anger?',
        'Lips narrowing and pressing together, with lowered, knitted brows and tense lower lids.'),
    StudyCard('f_surprise', 'How long does genuine surprise last?', 'Under a second. Surprise that lingers is usually performed.'),
    StudyCard('f_sadness', 'Which sadness signal is hard to fake?',
        'The inner corners of the eyebrows angling upward, a "reliable muscle" few people can move on purpose.'),
    StudyCard('f_duping', 'What is duping delight?',
        'A quick, suppressed smile of pleasure at getting away with a lie, at a moment that calls for distress.'),
    StudyCard('f_happy', 'What separates a genuine smile from a social one?',
        'The eyes: cheeks lift and crow\'s-feet appear (the Duchenne marker), not just the mouth.'),
    StudyCard('f_cluster', 'What makes a valid behavioral cluster?',
        'Three or more indicators that break baseline, appear together and follow the same question.'),
    StudyCard('f_pronoun', 'What is a pronoun drop?',
        'The "I" disappears from part of a statement ("Went home, made dinner"). The speaker may be distancing from those actions.'),
    StudyCard('f_temporal', 'What is a temporal gap?',
        'A phrase like "after that" or "later on" that skips time. Ask what happened in the gap.'),
    StudyCard('f_tense', 'Why does a verb tense shift matter?',
        'Memories are told in the past tense. A switch to present at the key moment can mean the story is being built.'),
    StudyCard('f_nonanswer', 'What is a non-answer assertion?',
        'Answering a direct question with a character claim ("I would never…") instead of a denial ("No, I didn\'t").'),
    StudyCard('f_qualifier', 'What are credibility qualifiers?',
        '"To be honest", "frankly", "I swear": phrases that try to make a claim sound true. Notice which claim they prop up.'),
    StudyCard('f_distancing', 'What is distancing language?',
        'Switching from a name to "that woman" or "the individual", showing where the speaker wants distance.'),
    StudyCard('f_minimizing', 'What is minimizing language?', '"Just", "only", "a little": words that shrink an act. Ask for exact numbers.'),
    StudyCard('f_stalling', 'Name two stalling tactics.',
        'Repeating the question back, and "That\'s a good question." Both buy time instead of answering.'),
    StudyCard('f_truth', 'Name three markers of a truthful account.',
        'Spontaneous self-corrections, admitted memory gaps, and odd or unflattering details.'),
    StudyCard('f_clean', 'Is a nervous, fidgety person lying?',
        'Not if that\'s their baseline. Only changes from baseline matter; calling a lie without one is a false alarm.'),
    StudyCard('f_open', 'Why start an interview with an open question?',
        'It gets a free narrative before you shape it. Yes/no and leading questions hand over your theory.'),
    StudyCard('f_probe', 'What should you do when you spot a hot spot?',
        'Note it, keep rapport, and come back later with open questions. Don\'t accuse or point out body language.'),
    StudyCard('f_contam', 'What is contamination in an interview?',
        'Leaking details you know, or letting witnesses talk, so you can\'t tell memory from suggestion.'),
    StudyCard('f_rapport', 'Why build rapport first?', 'It lowers fear and gives you a baseline. Nervousness isn\'t guilt.'),
  ];
}

// ════════════════════════════════════════════════════════════════════════════
//  MEMORY GYM: HOME
// ════════════════════════════════════════════════════════════════════════════

void openMemoryDrill(BuildContext context, GameState game, MemoryDrill drill, {bool replace = false}) {
  final Widget screen = switch (drill) {
    MemoryDrill.digits => DigitSpanScreen(game: game),
    MemoryDrill.words => StoryChainScreen(game: game),
    MemoryDrill.palace => MemoryPalaceScreen(game: game),
    MemoryDrill.faces => NamesFacesScreen(game: game),
    MemoryDrill.kim => KimsGameScreen(game: game),
    MemoryDrill.snapshot => SnapshotScreen(game: game),
    MemoryDrill.review => SpacedReviewScreen(game: game),
  };
  final route = MaterialPageRoute<void>(builder: (_) => screen);
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

void openMemoryLesson(BuildContext context, GameState game, MemoryDrill drill) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MemoryLessonScreen(game: game, drill: drill)));
}

class MemoryGymScreen extends StatefulWidget {
  const MemoryGymScreen({super.key, required this.game});
  final GameState game;

  @override
  State<MemoryGymScreen> createState() => _MemoryGymScreenState();
}

class _MemoryGymScreenState extends State<MemoryGymScreen> {
  static const List<MemoryDrill> _rotation = <MemoryDrill>[
    MemoryDrill.words,
    MemoryDrill.palace,
    MemoryDrill.faces,
    MemoryDrill.kim,
    MemoryDrill.snapshot,
  ];

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onChanged);
  }

  @override
  void dispose() {
    game.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final today = dayIndex();
    final memory = game.memory;
    final due = memory.reviewQueue(today).length;
    final drillOfDay = _rotation[today % _rotation.length];

    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Memory Gym',
                        style: TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Real techniques, daily reps, spaced review.',
                        style: TextStyle(color: Palette.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                StatPill(emoji: '🔥', label: '${game.streak}', color: Palette.orange, tooltip: 'Day streak'),
              ],
            ),
            const SizedBox(height: 18),
            _TodayCard(
              rows: <_TodayRow>[
                _TodayRow(
                  drill: MemoryDrill.review,
                  subtitle: due == 0 ? 'All caught up' : '$due cards ready',
                  done: memory.doneToday(MemoryDrill.review, today) || due == 0,
                ),
                _TodayRow(
                  drill: MemoryDrill.digits,
                  subtitle: MemoryDrill.digits.levelLabel(memory.level[MemoryDrill.digits]!),
                  done: memory.doneToday(MemoryDrill.digits, today),
                ),
                _TodayRow(
                  drill: drillOfDay,
                  subtitle: 'Drill of the day · ${drillOfDay.levelLabel(memory.level[drillOfDay]!)}',
                  done: memory.doneToday(drillOfDay, today),
                ),
              ],
              onOpen: (d) => openMemoryDrill(context, game, d),
            ),
            const SizedBox(height: 22),
            const Text(
              'TECHNIQUES & DRILLS',
              style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            for (final drill in MemoryDrill.values)
              _DrillCard(
                drill: drill,
                status: drill == MemoryDrill.review
                    ? '${memory.learnedCards()}/${MemoryContent.cards.length} cards learned'
                    : '${drill.levelLabel(memory.level[drill]!)} · best ${memory.best[drill] == 0 ? '–' : drill.levelLabel(memory.best[drill]!)}',
                onLearn: () => openMemoryLesson(context, game, drill),
                onPractice: () => openMemoryDrill(context, game, drill),
              ),
            const SizedBox(height: 12),
            const _ScienceCard(),
          ],
        ),
      ),
    );
  }
}

class _TodayRow {
  const _TodayRow({required this.drill, required this.subtitle, required this.done});
  final MemoryDrill drill;
  final String subtitle;
  final bool done;
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.rows, required this.onOpen});
  final List<_TodayRow> rows;
  final ValueChanged<MemoryDrill> onOpen;

  @override
  Widget build(BuildContext context) {
    final doneCount = rows.where((r) => r.done).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.blue.withAlpha(120), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.today, color: Palette.blue, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Today's workout",
                  style: TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '$doneCount/${rows.length}',
                style: const TextStyle(color: Palette.blue, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'About 5 minutes. Daily reps beat long sessions.',
            style: TextStyle(color: Palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 10),
          for (final row in rows)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpen(row.drill),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: row.drill.color.withAlpha(row.done ? 255 : 50),
                      child: Icon(
                        row.done ? Icons.check : row.drill.icon,
                        color: row.done ? Colors.white : row.drill.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            row.drill.title,
                            style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          Text(row.subtitle, style: const TextStyle(color: Palette.textMuted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Palette.textMuted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DrillCard extends StatelessWidget {
  const _DrillCard({required this.drill, required this.status, required this.onLearn, required this.onPractice});
  final MemoryDrill drill;
  final String status;
  final VoidCallback onLearn;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 22,
                backgroundColor: drill.color,
                child: Icon(drill.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      drill.title,
                      style: const TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      drill.technique.toUpperCase(),
                      style: TextStyle(color: drill.color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: const TextStyle(color: Palette.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLearn,
                  icon: const Icon(Icons.menu_book, size: 18),
                  label: const Text('Learn'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.textPrimary,
                    side: const BorderSide(color: Palette.border, width: 1.5),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPractice,
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Practice'),
                  style: FilledButton.styleFrom(
                    backgroundColor: drill.color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScienceCard extends StatelessWidget {
  const _ScienceCard();

  static const List<String> _points = <String>[
    'Techniques work. Memory palaces, chunking and story linking can multiply how much you recall, and you can use them anywhere.',
    'Generic brain games mostly make you better at the game. Practice the kind of remembering you actually want to do.',
    'Recall plus spacing: a few minutes of testing yourself every day beats long cramming sessions.',
    'Sleep, exercise and attention matter. Memories are locked in during sleep, and you can\'t remember what you never noticed.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.teal.withAlpha(28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.teal.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.science, color: Palette.teal, size: 20),
              SizedBox(width: 8),
              Text(
                'What actually builds memory',
                style: TextStyle(color: Palette.teal, fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final point in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('•  ', style: TextStyle(color: Palette.teal, fontWeight: FontWeight.w900)),
                  Expanded(
                    child: Text(point, style: const TextStyle(color: Palette.textPrimary, fontSize: 13.5, height: 1.4)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MEMORY GYM: SHARED DRILL WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class DrillScaffold extends StatelessWidget {
  const DrillScaffold({super.key, required this.drill, required this.progress, required this.child, this.label});
  final MemoryDrill drill;
  final double progress;
  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 16, 4),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Palette.textMuted, size: 28),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label ?? drill.title,
                          style: TextStyle(color: drill.color, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 6),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
                          duration: const Duration(milliseconds: 400),
                          builder: (context, value, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 10,
                              backgroundColor: Palette.surfaceHigh,
                              valueColor: AlwaysStoppedAnimation<Color>(drill.color),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// Countdown bar for a study phase. Calls [onDone] when time runs out.
class StudyTimer extends StatefulWidget {
  const StudyTimer({super.key, required this.duration, required this.onDone, required this.color});
  final Duration duration;
  final VoidCallback onDone;
  final Color color;

  @override
  State<StudyTimer> createState() => _StudyTimerState();
}

class _StudyTimerState extends State<StudyTimer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) widget.onDone();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final secondsLeft = ((1 - _controller.value) * widget.duration.inMilliseconds / 1000).ceil();
        return Row(
          children: <Widget>[
            Icon(Icons.timer, color: widget.color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: 1 - _controller.value,
                  minHeight: 8,
                  backgroundColor: Palette.surfaceHigh,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              child: Text(
                '${secondsLeft}s',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }
}

class DrillIntro extends StatelessWidget {
  const DrillIntro({
    super.key,
    required this.drill,
    required this.level,
    required this.tip,
    required this.onStart,
    required this.onLearn,
  });

  final MemoryDrill drill;
  final int level;
  final String tip;
  final VoidCallback onStart;
  final VoidCallback onLearn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: <Widget>[
          const Spacer(),
          CircleAvatar(
            radius: 44,
            backgroundColor: drill.color,
            child: Icon(drill.icon, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 18),
          Text(
            drill.title,
            style: const TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          if (drill.leveled)
            Text(
              drill.levelLabel(level),
              style: TextStyle(color: drill.color, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          const SizedBox(height: 18),
          InfoBanner(icon: Icons.tips_and_updates, color: drill.color, text: tip),
          const Spacer(),
          ChunkyButton(label: 'Start', color: drill.color, onPressed: onStart),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onLearn,
            child: const Text(
              'HOW DOES THIS TECHNIQUE WORK?',
              style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class DrillFeedback extends StatelessWidget {
  const DrillFeedback({
    super.key,
    required this.passed,
    required this.headline,
    required this.levelText,
    required this.child,
    required this.onNext,
    required this.nextLabel,
  });

  final bool passed;
  final String headline;
  final String levelText;
  final Widget child;
  final VoidCallback onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final color = passed ? Palette.green : Palette.red;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(passed ? Icons.check_circle : Icons.cancel, color: color, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          headline,
                          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(levelText, style: const TextStyle(color: Palette.textMuted, fontSize: 14)),
                  const SizedBox(height: 16),
                  child,
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(label: nextLabel, color: color, onPressed: onNext),
        ],
      ),
    );
  }
}

class DrillSummary extends StatelessWidget {
  const DrillSummary({
    super.key,
    required this.drill,
    required this.passed,
    required this.total,
    required this.ip,
    required this.startLevel,
    required this.endLevel,
    required this.streakExtended,
    required this.onAgain,
  });

  final MemoryDrill drill;
  final int passed;
  final int total;
  final int ip;
  final int startLevel;
  final int endLevel;
  final bool streakExtended;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final change = endLevel - startLevel;
    final changeText = !drill.leveled
        ? ''
        : change > 0
            ? 'Level up: ${drill.levelLabel(startLevel)} → ${drill.levelLabel(endLevel)}'
            : change < 0
                ? 'Eased off to ${drill.levelLabel(endLevel)}. That\'s how the training finds your edge.'
                : 'Holding at ${drill.levelLabel(endLevel)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: <Widget>[
          const Spacer(),
          const Text('🧠', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 12),
          const Text(
            'Session complete',
            style: TextStyle(color: Palette.gold, fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '$passed of $total perfect',
            style: const TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Palette.border, width: 1.5),
            ),
            child: Column(
              children: <Widget>[
                _BreakdownLine(label: 'Insight Points', value: '+$ip IP'),
                if (changeText.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(changeText, textAlign: TextAlign.center, style: TextStyle(color: drill.color, fontWeight: FontWeight.w800)),
                ],
                if (streakExtended) const _BreakdownLine(label: 'Day streak', value: '🔥 extended'),
              ],
            ),
          ),
          const Spacer(),
          ChunkyButton(label: 'Done', color: Palette.green, onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onAgain,
            child: const Text(
              'GO AGAIN',
              style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class QuizQuestion {
  const QuizQuestion({required this.prompt, required this.options, required this.correct, this.visual, this.note});
  final String prompt;
  final List<String> options;
  final int correct;
  final String? visual;
  final String? note;
}

/// Multiple-choice recall, one question at a time. Reports results at the end.
class QuizRunner extends StatefulWidget {
  const QuizRunner({super.key, required this.questions, required this.color, required this.onFinished});
  final List<QuizQuestion> questions;
  final Color color;
  final ValueChanged<List<bool>> onFinished;

  @override
  State<QuizRunner> createState() => _QuizRunnerState();
}

class _QuizRunnerState extends State<QuizRunner> {
  int _index = 0;
  int? _chosen;
  final List<bool> _results = <bool>[];

  void _choose(int i) {
    if (_chosen != null) return;
    final correct = i == widget.questions[_index].correct;
    if (correct) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _chosen = i;
      _results.add(correct);
    });
  }

  void _next() {
    if (_index + 1 >= widget.questions.length) {
      widget.onFinished(List<bool>.of(_results));
      return;
    }
    setState(() {
      _index++;
      _chosen = null;
    });
  }

  OptionVisual _visual(int i) {
    final chosen = _chosen;
    if (chosen == null) return OptionVisual.idle;
    final q = widget.questions[_index];
    if (i == q.correct) return i == chosen ? OptionVisual.correct : OptionVisual.missed;
    return i == chosen ? OptionVisual.wrong : OptionVisual.idle;
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_index];
    final chosen = _chosen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'QUESTION ${_index + 1} OF ${widget.questions.length}',
                    style: TextStyle(color: widget.color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
                  ),
                  const SizedBox(height: 12),
                  if (q.visual != null) ...<Widget>[
                    Center(child: Text(q.visual!, style: const TextStyle(fontSize: 64))),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    q.prompt,
                    style: const TextStyle(color: Palette.textPrimary, fontSize: 21, fontWeight: FontWeight.w800, height: 1.3),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < q.options.length; i++)
                    OptionTile(
                      visual: _visual(i),
                      onTap: chosen == null ? () => _choose(i) : null,
                      text: q.options[i],
                      bold: true,
                    ),
                  if (chosen != null && q.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InfoBanner(icon: Icons.lightbulb, color: widget.color, text: q.note!),
                    ),
                ],
              ),
            ),
          ),
          if (chosen != null) ...<Widget>[
            const SizedBox(height: 12),
            ChunkyButton(
              label: _index + 1 >= widget.questions.length ? 'See results' : 'Next',
              color: chosen == q.correct ? Palette.green : Palette.red,
              onPressed: _next,
            ),
          ],
        ],
      ),
    );
  }
}

/// Options for a recall question: the answer plus [count] - 1 distractors.
QuizQuestion buildChoiceQuestion({
  required String prompt,
  required String answer,
  required Iterable<String> pool,
  required math.Random rng,
  String? visual,
  String? note,
  int count = 4,
}) {
  final distractors = pool.where((p) => p != answer).toSet().toList()..shuffle(rng);
  final options = <String>[answer, ...distractors.take(count - 1)]..shuffle(rng);
  return QuizQuestion(prompt: prompt, options: options, correct: options.indexOf(answer), visual: visual, note: note);
}

enum DrillPhase { intro, study, blank, recall, feedback, summary }

/// Shared session bookkeeping for leveled drills.
mixin DrillSession<T extends StatefulWidget> on State<T> {
  final math.Random rng = math.Random();
  DrillPhase phase = DrillPhase.intro;
  int trial = 0;
  int passedTrials = 0;
  int sessionIp = 0;
  int startLevel = 0;
  bool streakExtended = false;
  bool lastPassed = false;
  int lastLevel = 0;

  GameState get game;
  MemoryDrill get drill;
  int get totalTrials;

  int get level => game.memory.level[drill]!;

  double get progress {
    final done = trial + (phase == DrillPhase.feedback || phase == DrillPhase.summary ? 1 : 0);
    return totalTrials == 0 ? 0 : done / totalTrials;
  }

  void initSession() {
    startLevel = level;
  }

  /// Records a trial and moves to feedback.
  void finishTrial({required bool passed, required int levelDelta, required int ip}) {
    lastPassed = passed;
    lastLevel = level;
    game.recordMemoryTrial(drill, passed: passed, levelDelta: levelDelta, ip: ip);
    sessionIp += ip;
    if (passed) passedTrials++;
    if (passed) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() => phase = DrillPhase.feedback);
  }

  String get levelChangeText {
    final now = level;
    if (now > lastLevel) return 'Next round: ${drill.levelLabel(now)} (up from ${drill.levelLabel(lastLevel)})';
    if (now < lastLevel) return 'Next round: ${drill.levelLabel(now)} (eased off from ${drill.levelLabel(lastLevel)})';
    return 'Staying at ${drill.levelLabel(now)}';
  }

  /// Advances to the next trial, or ends the session.
  void nextTrial(VoidCallback startTrial) {
    trial++;
    if (trial >= totalTrials) {
      streakExtended = game.completeMemorySession(drill);
      setState(() => phase = DrillPhase.summary);
    } else {
      startTrial();
    }
  }

  void restartSession(VoidCallback startTrial) {
    trial = 0;
    passedTrials = 0;
    sessionIp = 0;
    startLevel = level;
    streakExtended = false;
    startTrial();
  }

  Widget buildSummary(VoidCallback startTrial) => DrillSummary(
        drill: drill,
        passed: passedTrials,
        total: totalTrials,
        ip: sessionIp,
        startLevel: startLevel,
        endLevel: level,
        streakExtended: streakExtended,
        onAgain: () => restartSession(startTrial),
      );

  void openLesson() => openMemoryLesson(context, game, drill);
}

// ════════════════════════════════════════════════════════════════════════════
//  MEMORY GYM: DRILLS
// ════════════════════════════════════════════════════════════════════════════

// ── Number Span (chunking) ────────────────────────────────────────────────

class DigitSpanScreen extends StatefulWidget {
  const DigitSpanScreen({super.key, required this.game});
  final GameState game;

  @override
  State<DigitSpanScreen> createState() => _DigitSpanScreenState();
}

class _DigitSpanScreenState extends State<DigitSpanScreen> with DrillSession<DigitSpanScreen> {
  String _target = '';
  String _entry = '';

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.digits;
  @override
  int get totalTrials => 5;

  @override
  void initState() {
    super.initState();
    initSession();
  }

  void _startTrial() {
    final digits = List<int>.generate(level, (_) => rng.nextInt(10));
    setState(() {
      _target = digits.join();
      _entry = '';
      phase = DrillPhase.study;
    });
  }

  void _press(String key) {
    if (phase != DrillPhase.recall) return;
    HapticFeedback.selectionClick();
    if (key == 'del') {
      if (_entry.isNotEmpty) setState(() => _entry = _entry.substring(0, _entry.length - 1));
      return;
    }
    if (key == 'ok') {
      _submit();
      return;
    }
    if (_entry.length >= _target.length) return;
    setState(() => _entry += key);
    if (_entry.length == _target.length) _submit();
  }

  void _submit() {
    final passed = _entry == _target;
    finishTrial(passed: passed, levelDelta: passed ? 1 : -1, ip: passed ? 2 + _target.length ~/ 3 : 0);
  }

  String _chunked(String s) {
    final parts = <String>[];
    for (var i = 0; i < s.length; i += 3) {
      parts.add(s.substring(i, math.min(i + 3, s.length)));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return DrillScaffold(
      drill: drill,
      progress: progress,
      label: '${drill.title.toUpperCase()} · ROUND ${math.min(trial + 1, totalTrials)}/$totalTrials',
      child: switch (phase) {
        DrillPhase.intro => DrillIntro(
            drill: drill,
            level: level,
            tip: 'Chunk it: split the number into groups of 2–3 and give each group a meaning or a rhythm.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study || DrillPhase.blank => _buildStudy(),
        DrillPhase.recall => _buildRecall(),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Perfect recall' : 'Not quite',
            levelText: levelChangeText,
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Next number',
            onNext: () => nextTrial(_startTrial),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _NumberRow(label: 'The number', value: _chunked(_target), color: Palette.green),
                const SizedBox(height: 10),
                _NumberRow(
                  label: 'You typed',
                  value: _entry.isEmpty ? '–' : _chunked(_entry),
                  color: lastPassed ? Palette.green : Palette.red,
                ),
                const SizedBox(height: 14),
                const InfoBanner(
                  icon: Icons.tips_and_updates,
                  color: Palette.blue,
                  text: 'Groups of three are shown above. Try hearing each group as one "word".',
                ),
              ],
            ),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  Widget _buildStudy() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          StudyTimer(
            key: ValueKey<String>('study$trial$_target'),
            duration: Duration(milliseconds: 1000 + 650 * _target.length),
            color: drill.color,
            onDone: () => setState(() => phase = DrillPhase.recall),
          ),
          const Spacer(),
          const Text('MEMORIZE', style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 12),
          FittedBox(
            child: Text(
              _target,
              style: const TextStyle(
                color: Palette.textPrimary,
                fontSize: 54,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => phase = DrillPhase.recall),
            child: const Text("I'M READY", style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildRecall() {
    const keys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', 'del', '0', 'ok'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: <Widget>[
          const Text('TYPE THE NUMBER', style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < _target.length; i++)
                Container(
                  width: 30,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: i == _entry.length ? drill.color : Palette.border, width: 2),
                  ),
                  child: Text(
                    i < _entry.length ? _entry[i] : '',
                    style: const TextStyle(color: Palette.textPrimary, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
            ],
          ),
          const Spacer(),
          for (var row = 0; row < 4; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  for (var col = 0; col < 3; col++) ...<Widget>[
                    if (col > 0) const SizedBox(width: 10),
                    Expanded(child: _KeypadKey(value: keys[row * 3 + col], color: drill.color, onTap: _press)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({required this.value, required this.color, required this.onTap});
  final String value;
  final Color color;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final Widget label = switch (value) {
      'del' => const Icon(Icons.backspace_outlined, color: Palette.textPrimary),
      'ok' => Icon(Icons.check, color: color, size: 28),
      _ => Text(value, style: const TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
    };
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(value),
        child: SizedBox(height: 60, child: Center(child: label)),
      ),
    );
  }
}

class _NumberRow extends StatelessWidget {
  const _NumberRow({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(140), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label.toUpperCase(), style: const TextStyle(color: Palette.textMuted, fontSize: 11.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
        ],
      ),
    );
  }
}

// ── Story Chain (link method) ─────────────────────────────────────────────

class StoryChainScreen extends StatefulWidget {
  const StoryChainScreen({super.key, required this.game});
  final GameState game;

  @override
  State<StoryChainScreen> createState() => _StoryChainScreenState();
}

class _StoryChainScreenState extends State<StoryChainScreen> with DrillSession<StoryChainScreen> {
  List<String> _target = <String>[];
  List<String> _pool = <String>[];
  final List<int> _picked = <int>[];
  int _score = 0;

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.words;
  @override
  int get totalTrials => 3;

  @override
  void initState() {
    super.initState();
    initSession();
  }

  void _startTrial() {
    final bank = List<String>.of(MemoryContent.words)..shuffle(rng);
    final n = level;
    final decoys = math.min(10, math.max(5, n ~/ 2 + 2));
    setState(() {
      _target = bank.take(n).toList();
      _pool = bank.take(n + decoys).toList()..shuffle(rng);
      _picked.clear();
      phase = DrillPhase.study;
    });
  }

  void _tapWord(int index) {
    if (phase != DrillPhase.recall || _picked.contains(index)) return;
    HapticFeedback.selectionClick();
    setState(() => _picked.add(index));
    if (_picked.length == _target.length) _check();
  }

  void _check() {
    var score = 0;
    for (var i = 0; i < _target.length; i++) {
      if (_pool[_picked[i]] == _target[i]) score++;
    }
    _score = score;
    final n = _target.length;
    final passed = score == n;
    finishTrial(passed: passed, levelDelta: passed ? 1 : (score <= n - 3 ? -1 : 0), ip: score);
  }

  @override
  Widget build(BuildContext context) {
    return DrillScaffold(
      drill: drill,
      progress: progress,
      label: '${drill.title.toUpperCase()} · ROUND ${math.min(trial + 1, totalTrials)}/$totalTrials',
      child: switch (phase) {
        DrillPhase.intro => DrillIntro(
            drill: drill,
            level: level,
            tip: 'Link each word to the next in one crazy, vivid story. The weirder, the better.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study || DrillPhase.blank => _buildStudy(),
        DrillPhase.recall => _buildRecall(),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Perfect chain' : '$_score of ${_target.length} in place',
            levelText: levelChangeText,
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Next list',
            onNext: () => nextTrial(_startTrial),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < _target.length; i++)
                  _ResultLine(
                    index: i + 1,
                    expected: _target[i],
                    given: _pool[_picked[i]],
                  ),
              ],
            ),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  Widget _buildStudy() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StudyTimer(
            key: ValueKey<String>('words$trial'),
            duration: Duration(seconds: 2 + _target.length * 2),
            color: drill.color,
            onDone: () => setState(() => phase = DrillPhase.recall),
          ),
          const SizedBox(height: 16),
          const Text(
            'BUILD A STORY IN THIS ORDER',
            style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 1.4),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 10,
                children: <Widget>[
                  for (var i = 0; i < _target.length; i++)
                    _WordChip(text: '${i + 1}. ${_target[i].toUpperCase()}', color: drill.color, filled: true),
                ],
              ),
            ),
          ),
          ChunkyButton(
            label: "I'm ready",
            color: drill.color,
            onPressed: () => setState(() => phase = DrillPhase.recall),
          ),
        ],
      ),
    );
  }

  Widget _buildRecall() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'TAP THE WORDS IN ORDER · ${_picked.length}/${_target.length}',
            style: const TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          const Text('Some of these are decoys.', style: TextStyle(color: Palette.textMuted, fontSize: 13)),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 10,
                children: <Widget>[
                  for (var i = 0; i < _pool.length; i++)
                    GestureDetector(
                      onTap: () => _tapWord(i),
                      child: _WordChip(
                        text: _picked.contains(i)
                            ? '${_picked.indexOf(i) + 1}. ${_pool[i].toUpperCase()}'
                            : _pool[i].toUpperCase(),
                        color: drill.color,
                        filled: _picked.contains(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _picked.isEmpty ? null : () => setState(() => _picked.removeLast()),
            icon: const Icon(Icons.undo),
            label: const Text('Undo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Palette.textPrimary,
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Palette.border, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordChip extends StatelessWidget {
  const _WordChip({required this.text, required this.color, required this.filled});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: filled ? color.withAlpha(60) : Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: filled ? color : Palette.border, width: 2),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? Palette.textPrimary : Palette.textPrimary.withAlpha(230),
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.index, required this.expected, required this.given});
  final int index;
  final String expected;
  final String given;

  @override
  Widget build(BuildContext context) {
    final ok = expected == given;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Palette.green : Palette.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok ? '$index. $expected' : '$index. $expected  (you: $given)',
              style: TextStyle(color: ok ? Palette.textPrimary : Palette.red, fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Memory Palace (method of loci) ────────────────────────────────────────

class MemoryPalaceScreen extends StatefulWidget {
  const MemoryPalaceScreen({super.key, required this.game});
  final GameState game;

  @override
  State<MemoryPalaceScreen> createState() => _MemoryPalaceScreenState();
}

class _MemoryPalaceScreenState extends State<MemoryPalaceScreen> with DrillSession<MemoryPalaceScreen> {
  List<PalaceStop> _items = <PalaceStop>[];
  List<String> _prompts = <String>[];
  int _studyIndex = 0;
  List<bool> _results = <bool>[];
  List<QuizQuestion> _questions = <QuizQuestion>[];

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.palace;
  @override
  int get totalTrials => 2;

  @override
  void initState() {
    super.initState();
    initSession();
  }

  String _label(PalaceStop s) => '${s.emoji}  ${s.name}';

  void _startTrial() {
    final n = math.min(level, MemoryContent.palaceRoute.length);
    final items = List<PalaceStop>.of(MemoryContent.palaceItems)..shuffle(rng);
    final chosen = items.take(n).toList();
    final prompts = <String>[
      for (var i = 0; i < n; i++)
        MemoryContent.palacePrompts[rng.nextInt(MemoryContent.palacePrompts.length)]
            .replaceAll('{item}', chosen[i].name)
            .replaceAll('{stop}', MemoryContent.palaceRoute[i].name),
    ];
    final extras = items.skip(n).take(4).map(_label).toList();
    final sessionLabels = chosen.map(_label).toList();
    final questions = <QuizQuestion>[
      for (var i = 0; i < n; i++)
        buildChoiceQuestion(
          prompt: 'What was at the ${MemoryContent.palaceRoute[i].name}?',
          visual: MemoryContent.palaceRoute[i].emoji,
          answer: sessionLabels[i],
          // Mostly other items from this walk, so you must know the position.
          pool: <String>[...sessionLabels, ...extras],
          rng: rng,
          count: 5,
        ),
    ];
    setState(() {
      _items = chosen;
      _prompts = prompts;
      _questions = questions;
      _studyIndex = 0;
      phase = DrillPhase.study;
    });
  }

  void _finish(List<bool> results) {
    _results = results;
    final score = results.where((r) => r).length;
    final n = results.length;
    final passed = score == n;
    finishTrial(passed: passed, levelDelta: passed ? 1 : (score <= n - 3 ? -1 : 0), ip: score);
  }

  @override
  Widget build(BuildContext context) {
    return DrillScaffold(
      drill: drill,
      progress: progress,
      label: '${drill.title.toUpperCase()} · WALK ${math.min(trial + 1, totalTrials)}/$totalTrials',
      child: switch (phase) {
        DrillPhase.intro => DrillIntro(
            drill: drill,
            level: level,
            tip: 'Picture YOUR home. At each stop, make the item do something strange and vivid right there.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study || DrillPhase.blank => _buildStudy(),
        DrillPhase.recall => QuizRunner(
            key: ValueKey<String>('palace$trial'),
            questions: _questions,
            color: drill.color,
            onFinished: _finish,
          ),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Every stop remembered' : '${_results.where((r) => r).length} of ${_results.length} stops',
            levelText: levelChangeText,
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Next walk',
            onNext: () => nextTrial(_startTrial),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < _items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          i < _results.length && _results[i] ? Icons.check_circle : Icons.cancel,
                          color: i < _results.length && _results[i] ? Palette.green : Palette.red,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${MemoryContent.palaceRoute[i].emoji} ${MemoryContent.palaceRoute[i].name}  →  ${_label(_items[i])}',
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  Widget _buildStudy() {
    final stop = MemoryContent.palaceRoute[_studyIndex];
    final item = _items[_studyIndex];
    final last = _studyIndex + 1 >= _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: <Widget>[
          Text(
            'STOP ${_studyIndex + 1} OF ${_items.length}',
            style: TextStyle(color: drill.color, fontWeight: FontWeight.w800, letterSpacing: 1.6),
          ),
          const Spacer(),
          Text(stop.emoji, style: const TextStyle(fontSize: 54)),
          Text(
            stop.name.toUpperCase(),
            style: const TextStyle(color: Palette.textMuted, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: Column(
              key: ValueKey<int>(_studyIndex),
              children: <Widget>[
                Text(item.emoji, style: const TextStyle(fontSize: 96)),
                Text(
                  item.name.toUpperCase(),
                  style: const TextStyle(color: Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          InfoBanner(icon: Icons.auto_awesome, color: drill.color, text: _prompts[_studyIndex]),
          const Spacer(),
          ChunkyButton(
            label: last ? 'Walk it back' : 'Next stop',
            color: drill.color,
            onPressed: () {
              if (last) {
                setState(() => phase = DrillPhase.recall);
              } else {
                setState(() => _studyIndex++);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Names & Faces ─────────────────────────────────────────────────────────

class _Person {
  const _Person(this.face, this.name, this.job, this.detail);
  final String face;
  final String name;
  final String job;
  final String detail;
}

class NamesFacesScreen extends StatefulWidget {
  const NamesFacesScreen({super.key, required this.game});
  final GameState game;

  @override
  State<NamesFacesScreen> createState() => _NamesFacesScreenState();
}

class _NamesFacesScreenState extends State<NamesFacesScreen> with DrillSession<NamesFacesScreen> {
  List<_Person> _people = <_Person>[];
  List<QuizQuestion> _questions = <QuizQuestion>[];
  int _studyIndex = 0;
  int _score = 0;

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.faces;
  @override
  int get totalTrials => 2;

  @override
  void initState() {
    super.initState();
    initSession();
  }

  void _startTrial() {
    final n = level;
    final faces = List<String>.of(MemoryContent.faces)..shuffle(rng);
    final names = List<String>.of(MemoryContent.names)..shuffle(rng);
    final jobs = List<String>.of(MemoryContent.jobs)..shuffle(rng);
    final details = List<String>.of(MemoryContent.details)..shuffle(rng);
    final people = <_Person>[for (var i = 0; i < n; i++) _Person(faces[i], names[i], jobs[i], details[i])];

    final sessionNames = people.map((p) => p.name).toList();
    final sessionDetails = people.map((p) => p.detail).toList();
    final order = List<_Person>.of(people)..shuffle(rng);
    final detailOrder = List<_Person>.of(people)..shuffle(rng);
    final questions = <QuizQuestion>[
      for (final p in order)
        buildChoiceQuestion(
          prompt: 'What\'s this ${p.job}\'s name?',
          visual: p.face,
          answer: p.name,
          pool: <String>[...sessionNames, ...names.skip(n).take(4)],
          rng: rng,
          count: 5,
        ),
      for (final p in detailOrder)
        buildChoiceQuestion(
          prompt: 'What did you learn about ${p.name}?',
          visual: p.face,
          answer: p.detail,
          pool: <String>[...sessionDetails, ...details.skip(n).take(4)],
          rng: rng,
          count: 5,
        ),
    ];
    setState(() {
      _people = people;
      _questions = questions;
      _studyIndex = 0;
      phase = DrillPhase.study;
    });
  }

  void _finish(List<bool> results) {
    _score = results.where((r) => r).length;
    final total = results.length;
    final passed = _score == total;
    finishTrial(passed: passed, levelDelta: passed ? 1 : (_score <= total - 3 ? -1 : 0), ip: _score);
  }

  @override
  Widget build(BuildContext context) {
    return DrillScaffold(
      drill: drill,
      progress: progress,
      label: '${drill.title.toUpperCase()} · ROUND ${math.min(trial + 1, totalTrials)}/$totalTrials',
      child: switch (phase) {
        DrillPhase.intro => DrillIntro(
            drill: drill,
            level: level,
            tip: 'Say each name in your head, then hook it to an image tied to their face, job or detail.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study || DrillPhase.blank => _buildStudy(),
        DrillPhase.recall => QuizRunner(
            key: ValueKey<String>('faces$trial'),
            questions: _questions,
            color: drill.color,
            onFinished: _finish,
          ),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Never forget a face' : '$_score of ${_questions.length} right',
            levelText: levelChangeText,
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Meet new people',
            onNext: () => nextTrial(_startTrial),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final p in _people)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: <Widget>[
                        Text(p.face, style: const TextStyle(fontSize: 34)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${p.name}, ${p.job}\n${p.detail}',
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 14.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  Widget _buildStudy() {
    final p = _people[_studyIndex];
    final last = _studyIndex + 1 >= _people.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: <Widget>[
          Text(
            'PERSON ${_studyIndex + 1} OF ${_people.length}',
            style: TextStyle(color: drill.color, fontWeight: FontWeight.w800, letterSpacing: 1.6),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: Column(
              key: ValueKey<int>(_studyIndex),
              children: <Widget>[
                Text(p.face, style: const TextStyle(fontSize: 110)),
                const SizedBox(height: 8),
                Text(
                  '"Hi, I\'m ${p.name}."',
                  style: const TextStyle(color: Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'I work as a ${p.job}.',
                  style: const TextStyle(color: Palette.textMuted, fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: drill.color.withAlpha(140)),
                  ),
                  child: Text(
                    '${p.name} ${p.detail}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          InfoBanner(
            icon: Icons.auto_awesome,
            color: drill.color,
            text: 'Hook it: link "${p.name}" to something you can see, then hang "${p.detail}" on the same picture.',
          ),
          const Spacer(),
          ChunkyButton(
            label: last ? 'Test me' : 'Next person',
            color: drill.color,
            onPressed: () {
              if (last) {
                setState(() => phase = DrillPhase.recall);
              } else {
                setState(() => _studyIndex++);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Kim's Game (visual attention) ─────────────────────────────────────────

class KimsGameScreen extends StatefulWidget {
  const KimsGameScreen({super.key, required this.game});
  final GameState game;

  @override
  State<KimsGameScreen> createState() => _KimsGameScreenState();
}

class _KimsGameScreenState extends State<KimsGameScreen> with DrillSession<KimsGameScreen> {
  static const List<int> _sizes = <int>[6, 9, 12, 16, 20, 25, 30];
  static const List<int> _columns = <int>[3, 3, 4, 4, 5, 5, 5];
  static const List<int> _studySeconds = <int>[5, 7, 8, 10, 12, 14, 15];

  List<String> _grid = <String>[];
  int _target = 0;
  String _replacement = '';
  bool _missingMode = false;
  List<String> _options = <String>[];

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.kim;
  @override
  int get totalTrials => 4;

  int get _tier => (level - 1).clamp(0, _sizes.length - 1);

  @override
  void initState() {
    super.initState();
    initSession();
  }

  void _startTrial() {
    final pool = List<String>.of(MemoryContent.kimItems)..shuffle(rng);
    final size = _sizes[_tier];
    final grid = pool.take(size).toList();
    final outside = pool.skip(size).toList();
    final target = rng.nextInt(size);
    setState(() {
      _grid = grid;
      _target = target;
      _missingMode = trial.isOdd;
      _replacement = outside.first;
      _options = <String>[grid[target], ...outside.skip(1).take(4)]..shuffle(rng);
      phase = DrillPhase.study;
    });
  }

  void _toBlank() {
    setState(() => phase = DrillPhase.blank);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && phase == DrillPhase.blank) setState(() => phase = DrillPhase.recall);
    });
  }

  void _pickTile(int index) {
    if (phase != DrillPhase.recall || _missingMode) return;
    final passed = index == _target;
    finishTrial(passed: passed, levelDelta: passed ? 1 : -1, ip: passed ? 3 : 0);
  }

  void _pickOption(int index) {
    if (phase != DrillPhase.recall || !_missingMode) return;
    final passed = _options[index] == _grid[_target];
    finishTrial(passed: passed, levelDelta: passed ? 1 : -1, ip: passed ? 3 : 0);
  }

  Widget _gridView({required List<String> cells, int? highlight, Color? highlightColor, ValueChanged<int>? onTap}) {
    final cols = _columns[_tier];
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: <Widget>[
        for (var i = 0; i < cells.length; i++)
          GestureDetector(
            onTap: onTap == null ? null : () => onTap(i),
            child: Container(
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: i == highlight ? (highlightColor ?? drill.color) : Palette.border, width: 2.5),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(cells[i], style: const TextStyle(fontSize: 40)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrillScaffold(
      drill: drill,
      progress: progress,
      label: '${drill.title.toUpperCase()} · ROUND ${math.min(trial + 1, totalTrials)}/$totalTrials',
      child: switch (phase) {
        DrillPhase.intro => DrillIntro(
            drill: drill,
            level: level,
            tip: 'Sweep row by row and name each item in your head. Look for patterns: animals, food, round things.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study => _buildStudy(),
        DrillPhase.blank => const Center(
            child: Text(
              '👀  Look away…',
              style: TextStyle(color: Palette.textMuted, fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
        DrillPhase.recall => _buildRecall(),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Sharp eyes' : 'Missed it',
            levelText: levelChangeText,
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Next grid',
            onNext: () => nextTrial(_startTrial),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _missingMode
                      ? 'The missing item was ${_grid[_target]}.'
                      : 'The ${_grid[_target]} was swapped for $_replacement.',
                  style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _gridView(cells: _grid, highlight: _target, highlightColor: Palette.green),
              ],
            ),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  Widget _buildStudy() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StudyTimer(
            key: ValueKey<String>('kim$trial'),
            duration: Duration(seconds: _studySeconds[_tier]),
            color: drill.color,
            onDone: _toBlank,
          ),
          const SizedBox(height: 14),
          const Text('MEMORIZE THE GRID', style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: _gridView(cells: _grid))),
          const SizedBox(height: 12),
          ChunkyButton(label: "I'm ready", color: drill.color, onPressed: _toBlank),
        ],
      ),
    );
  }

  Widget _buildRecall() {
    if (!_missingMode) {
      final changed = List<String>.of(_grid)..[_target] = _replacement;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'One item changed. Tap it.',
              style: TextStyle(color: Palette.textPrimary, fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Expanded(child: SingleChildScrollView(child: _gridView(cells: changed, onTap: _pickTile))),
          ],
        ),
      );
    }
    final hidden = List<String>.of(_grid)..[_target] = '❔';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'What was in the ❔ spot?',
            style: TextStyle(color: Palette.textPrimary, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: _gridView(cells: hidden, highlight: _target))),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (var i = 0; i < _options.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _pickOption(i),
                      child: SizedBox(
                        height: 64,
                        child: Center(child: Text(_options[i], style: const TextStyle(fontSize: 34))),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Person Snapshot (observation recall) ──────────────────────────────────

class SnapshotScreen extends StatefulWidget {
  const SnapshotScreen({super.key, required this.game});
  final GameState game;

  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> with DrillSession<SnapshotScreen> {
  static const List<int> _studySeconds = <int>[22, 18, 15, 12, 10, 8, 6];

  final List<int> _order = <int>[];
  SnapshotCase? _case;
  List<QuizQuestion> _questions = <QuizQuestion>[];
  int _score = 0;

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.snapshot;
  @override
  int get totalTrials => 2;

  @override
  void initState() {
    super.initState();
    initSession();
    _order.addAll(List<int>.generate(MemoryContent.snapshots.length, (i) => i)..shuffle(rng));
  }

  void _startTrial() {
    if (_order.isEmpty) {
      _order.addAll(List<int>.generate(MemoryContent.snapshots.length, (i) => i)..shuffle(rng));
    }
    final snap = MemoryContent.snapshots[_order.removeLast()];
    final questions = <QuizQuestion>[
      for (final q in snap.questions)
        buildChoiceQuestion(prompt: q.question, answer: q.options.first, pool: q.options, rng: rng, note: q.explain),
    ];
    setState(() {
      _case = snap;
      _questions = questions;
      phase = DrillPhase.study;
    });
  }

  void _finish(List<bool> results) {
    _score = results.where((r) => r).length;
    final passed = _score == results.length;
    finishTrial(passed: passed, levelDelta: passed ? 1 : (_score <= 1 ? -1 : 0), ip: _score * 2);
  }

  @override
  Widget build(BuildContext context) {
    return DrillScaffold(
      drill: drill,
      progress: progress,
      label: '${drill.title.toUpperCase()} · CASE ${math.min(trial + 1, totalTrials)}/$totalTrials',
      child: switch (phase) {
        DrillPhase.intro => DrillIntro(
            drill: drill,
            level: level,
            tip: 'Scan head to toe in the same order every time: face → hands → clothes → shoes → objects.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study || DrillPhase.blank => _buildStudy(),
        DrillPhase.recall => QuizRunner(
            key: ValueKey<String>('snap$trial'),
            questions: _questions,
            color: drill.color,
            onFinished: _finish,
          ),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Nothing got past you' : '$_score of ${_questions.length} right',
            levelText: levelChangeText,
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Next case',
            onNext: () => nextTrial(_startTrial),
            child: ContextCard(
              label: 'THE SNAPSHOT · ${_case!.place.toUpperCase()}',
              icon: Icons.visibility,
              text: _case!.text,
              accent: drill.color,
            ),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  Widget _buildStudy() {
    final snap = _case!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StudyTimer(
            key: ValueKey<String>('snapStudy$trial'),
            duration: Duration(seconds: _studySeconds[(level - 1).clamp(0, _studySeconds.length - 1)]),
            color: drill.color,
            onDone: () => setState(() => phase = DrillPhase.recall),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: ContextCard(
                label: 'SNAPSHOT · ${snap.place.toUpperCase()}',
                icon: Icons.visibility,
                text: snap.text,
                accent: drill.color,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: "I'm ready",
            color: drill.color,
            onPressed: () => setState(() => phase = DrillPhase.recall),
          ),
        ],
      ),
    );
  }
}

// ── Spaced Review (retrieval + spacing) ───────────────────────────────────

class SpacedReviewScreen extends StatefulWidget {
  const SpacedReviewScreen({super.key, required this.game});
  final GameState game;

  @override
  State<SpacedReviewScreen> createState() => _SpacedReviewScreenState();
}

class _SpacedReviewScreenState extends State<SpacedReviewScreen> {
  late final List<StudyCard> _queue = widget.game.memory.reviewQueue(dayIndex());
  late final int _initialCount = _queue.length;
  final Set<String> _requeued = <String>{};
  int _index = 0;
  bool _revealed = false;
  int _knew = 0;
  bool _finished = false;
  bool _streakExtended = false;

  MemoryDrill get drill => MemoryDrill.review;

  void _rate(bool knew) {
    final card = _queue[_index];
    widget.game.reviewCard(card.id, knew: knew);
    if (knew) {
      _knew++;
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
      if (_requeued.add(card.id)) _queue.add(card); // one more try this session
    }
    setState(() {
      _index++;
      _revealed = false;
      if (_index >= _queue.length) {
        _finished = true;
        _streakExtended = widget.game.completeMemorySession(drill);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_queue.isEmpty) {
      body = _buildCaughtUp();
    } else if (_finished) {
      body = DrillSummary(
        drill: drill,
        passed: _knew,
        total: _queue.length,
        ip: _knew,
        startLevel: 0,
        endLevel: 0,
        streakExtended: _streakExtended,
        onAgain: () => Navigator.of(context).maybePop(),
      );
    } else {
      body = _buildCard();
    }
    return DrillScaffold(
      drill: drill,
      progress: _queue.isEmpty ? 1 : _index / _queue.length,
      label: _queue.isEmpty || _finished
          ? drill.title.toUpperCase()
          : '${drill.title.toUpperCase()} · CARD ${_index + 1}/${_queue.length}',
      child: body,
    );
  }

  Widget _buildCaughtUp() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const Spacer(),
          const Text('✅', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 12),
          const Text(
            'All caught up',
            style: TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'No cards are due right now. Come back tomorrow: the spacing is what makes it stick.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.textMuted, fontSize: 15, height: 1.4),
          ),
          const Spacer(),
          ChunkyButton(label: 'Back', color: drill.color, onPressed: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final card = _queue[_index];
    final isNew = !widget.game.memory.cards.containsKey(card.id);
    final second = _index >= _initialCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            second ? 'ONE MORE TRY' : (isNew ? 'NEW CARD' : 'REVIEW'),
            style: TextStyle(color: drill.color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Palette.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: drill.color.withAlpha(140), width: 2),
                    ),
                    child: Text(
                      card.front,
                      style: const TextStyle(color: Palette.textPrimary, fontSize: 21, fontWeight: FontWeight.w800, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 220),
                    crossFadeState: _revealed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Answer it in your head first, then flip.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.textMuted, fontSize: 14),
                      ),
                    ),
                    secondChild: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: drill.color.withAlpha(30),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: drill.color.withAlpha(120)),
                      ),
                      child: Text(
                        card.back,
                        style: const TextStyle(color: Palette.textPrimary, fontSize: 16.5, height: 1.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_revealed)
            ChunkyButton(label: 'Show answer', color: drill.color, onPressed: () => setState(() => _revealed = true))
          else
            Row(
              children: <Widget>[
                Expanded(child: ChunkyButton(label: 'Missed it', color: Palette.red, onPressed: () => _rate(false))),
                const SizedBox(width: 12),
                Expanded(child: ChunkyButton(label: 'Knew it', color: Palette.green, onPressed: () => _rate(true))),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Technique lessons ─────────────────────────────────────────────────────

class MemoryLessonScreen extends StatefulWidget {
  const MemoryLessonScreen({super.key, required this.game, required this.drill});
  final GameState game;
  final MemoryDrill drill;

  @override
  State<MemoryLessonScreen> createState() => _MemoryLessonScreenState();
}

class _MemoryLessonScreenState extends State<MemoryLessonScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  List<LessonPage> get _content => MemoryContent.lessons[widget.drill] ?? const <LessonPage>[];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drill = widget.drill;
    final pages = _content;
    final last = _page >= pages.length - 1;
    return DrillScaffold(
      drill: drill,
      progress: pages.isEmpty ? 1 : (_page + 1) / pages.length,
      label: '${drill.title.toUpperCase()} · ${drill.technique.toUpperCase()}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: <Widget>[
                  for (final page in pages)
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: 12),
                          Icon(drill.icon, color: drill.color, size: 48),
                          const SizedBox(height: 14),
                          Text(
                            page.title,
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 25, fontWeight: FontWeight.w900, height: 1.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            page.body,
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 16.5, height: 1.5),
                          ),
                          if (page.example != null) ...<Widget>[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: drill.color.withAlpha(30),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: drill.color.withAlpha(130)),
                              ),
                              child: Text(
                                page.example!,
                                style: TextStyle(color: drill.color, fontSize: 16, fontWeight: FontWeight.w800, height: 1.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? drill.color : Palette.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            ChunkyButton(
              label: last ? 'Practice now' : 'Next',
              color: drill.color,
              onPressed: () {
                if (last) {
                  openMemoryDrill(context, widget.game, drill, replace: true);
                } else {
                  _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BASELINE CASE GENERATOR
//  Every option shows a tell; the baseline decides which ones are normal.
// ════════════════════════════════════════════════════════════════════════════

class _Behavior {
  const _Behavior(this.id, this.habit, this.moment, this.flag, this.meaning, [this.group]);
  final String id;

  /// How it reads in the baseline profile ("rubs the back of the neck while talking").
  final String habit;

  /// How it reads in a moment ("rubs the back of the neck"). Identical wording
  /// whether it's a habit or the anomaly, so only the baseline tells them apart.
  final String moment;
  final Flag flag;
  final String meaning;

  /// Behaviors in the same group can't both be habits (e.g. fast vs. slow).
  final String? group;
}

class _CaseFile {
  const _CaseFile(this.incident, this.accusation, this.denial, this.topics);
  final String incident;
  final String accusation;
  final String denial;
  final List<List<String>> topics; // [question, answer]
}

class _Cause {
  const _Cause(this.event, this.reaction);
  final String event;
  final String reaction;
}

class BaselineGenerator {
  BaselineGenerator._();

  static const List<_Behavior> _behaviors = <_Behavior>[
    _Behavior('neck', 'rubs the back of the neck while talking', 'rubs the back of the neck', Flag.pacifying,
        'Neck rubbing is a pacifier: the brain soothing itself after a stressor.'),
    _Behavior('collar', 'tugs at the collar every few minutes', 'tugs at the collar', Flag.pacifying,
        'Collar tugging vents built-up stress, a classic pacifier.'),
    _Behavior('eyes', 'rubs the eyes a lot (dry contacts)', 'rubs the eyes', Flag.ocularShift,
        'Eye rubbing can be eye blocking: shutting out something unwelcome.'),
    _Behavior('blink', 'blinks fast, in little bursts', 'blinks in a quick burst', Flag.ocularShift,
        'Blink-rate surges often follow a stressful question.'),
    _Behavior('lookAway', 'looks away while thinking', 'looks away before answering', Flag.ocularShift,
        'Breaking eye contact on one topic, in someone who usually holds it, marks a hot spot.', 'gaze'),
    _Behavior('stare', 'holds steady, unbroken eye contact', 'holds unbroken eye contact', Flag.ocularShift,
        'A sudden fixed stare can be overcompensation: trying hard to look honest.', 'gaze'),
    _Behavior('still', 'keeps both hands completely still', 'keeps both hands completely still', Flag.gestureShift,
        'Hands freezing signals heavy thinking or the freeze response.', 'hands'),
    _Behavior('gesture', 'talks with big hand gestures', 'gestures widely', Flag.gestureShift,
        'Sudden animated gesturing from a still person can be a performance.', 'hands'),
    _Behavior('lips', 'presses the lips together between sentences', 'presses the lips together', Flag.pacifying,
        'Lip compression shows someone holding something back.'),
    _Behavior('throat', 'clears the throat often', 'clears the throat', Flag.vocalShift,
        'Throat clearing is a common stress response in the voice.'),
    _Behavior('knee', 'bounces a knee constantly', 'bounces a knee', Flag.postureShift,
        'Restless legs starting on one topic signal rising tension.'),
    _Behavior('door', 'keeps the feet pointed toward the door', 'feet point toward the door', Flag.postureShift,
        'Feet pointing at the exit show a wish to leave the topic.'),
    _Behavior('lean', 'leans back with arms crossed', 'leans back with arms crossed', Flag.postureShift,
        'Leaning away and crossing the arms puts distance between them and the topic.'),
    _Behavior('pause', 'pauses a few seconds before every answer', 'pauses a few seconds first', Flag.vocalShift,
        'A sudden delay means the answer is being built, not remembered.', 'tempo'),
    _Behavior('fast', 'answers instantly, talking fast', 'answers instantly, talking fast', Flag.vocalShift,
        'A sudden rush from a careful speaker can be a rehearsed line.', 'tempo'),
    _Behavior('pitch', 'speaks in a high, bright voice', 'voice goes high and bright', Flag.vocalShift,
        'Stress tightens the vocal cords and raises pitch.'),
    _Behavior('laugh', 'laughs nervously after answers', 'laughs nervously', Flag.vocalShift,
        'A nervous laugh on one topic, and nowhere else, leaks discomfort.'),
    _Behavior('forehead', 'rubs the forehead when thinking', 'rubs the forehead', Flag.pacifying,
        'Forehead rubbing is a pacifier.'),
    _Behavior('nose', 'touches the nose a lot (allergies)', 'touches the nose', Flag.pacifying,
        'Nose touching can be a pacifier or a way of blocking the mouth.'),
    _Behavior('shrug', 'shrugs one shoulder a lot', 'shrugs one shoulder', Flag.gestureShift,
        'A one-shoulder shrug shows weak commitment to the words.'),
    _Behavior('sigh', 'sighs heavily between answers', 'sighs heavily', Flag.vocalShift,
        'A heavy sigh on one topic releases built-up tension.'),
  ];

  static const List<_CaseFile> _cases = <_CaseFile>[
    _CaseFile('cash missing from the register', 'whether they took the cash', "No, I didn't take it.", <List<String>>[
      <String>['who closed the register', 'Me and Luis.'],
      <String>['about the lunch break', 'Twenty minutes, at the deli.'],
      <String>['where they parked', 'Out back, by the dumpster.'],
      <String>['when they left', 'Right at nine.'],
      <String>['about the camera outage', "I didn't know it was down."],
      <String>['about money troubles', 'Same as anyone.'],
    ]),
    _CaseFile('client files leaked to a competitor', 'whether they sent the files', 'No. I never sent them.', <List<String>>[
      <String>['which laptop they use', 'The silver work one.'],
      <String>['when they logged off Friday', 'Around six.'],
      <String>['who else had access', 'Three people on my team.'],
      <String>['about the competitor', 'Never worked with them.'],
      <String>['about weekend plans', "Just my sister's place."],
      <String>['about the shared drive', 'Everyone uses it.'],
    ]),
    _CaseFile('a dent in the company van', 'whether they hit something', 'No. It was fine when I parked.', <List<String>>[
      <String>['where they parked overnight', 'Lot B, near the fence.'],
      <String>['who rode along', 'Nobody, just me.'],
      <String>['about the route', 'Highway, then Fifth.'],
      <String>['when they returned the keys', 'Seven-thirty.'],
      <String>['about the weather', 'Rainy, kind of dark.'],
      <String>['about the fuel log', 'Filled it Tuesday.'],
    ]),
    _CaseFile('a missing office laptop', 'whether they took it', "No, I didn't.", <List<String>>[
      <String>['where they sat that day', 'By the window.'],
      <String>['who left last', 'Carla, I think.'],
      <String>['about the cleaners', 'They come at eight.'],
      <String>['when they last saw it', 'Tuesday morning.'],
      <String>['about the storage room', "I don't have a key."],
      <String>['about their own laptop', "It's at home."],
    ]),
    _CaseFile('a fire alarm pulled as a prank', 'whether they pulled it', 'No way.', <List<String>>[
      <String>['which class they were in', 'Chemistry.'],
      <String>['who they sat with', 'Jake and Mia.'],
      <String>['about the hallway', "I didn't go out there."],
      <String>['about lunch', 'Pizza in the cafeteria.'],
      <String>['when the bell rang', 'Right after it went off.'],
      <String>['about the hall pass', 'I never asked for one.'],
    ]),
    _CaseFile('a padded expense report', 'whether they added personal charges', 'No, never.', <List<String>>[
      <String>['about the hotel bill', 'Two nights, for the conference.'],
      <String>['about the taxi receipts', 'Airport and back.'],
      <String>['who approved the trip', 'My manager.'],
      <String>['about the client dinner', 'Four of us, Italian place.'],
      <String>['about the conference', 'Mostly sales talks.'],
      <String>['when they filed it', 'The Monday after.'],
    ]),
    _CaseFile('a broken shop window', 'whether they broke it', 'No. I heard it from the back.', <List<String>>[
      <String>['where they were standing', 'In the stockroom.'],
      <String>['who else was working', 'Just Dana.'],
      <String>['about the noise', 'A loud crack, then glass.'],
      <String>['when they called the owner', 'Right away.'],
      <String>['about the kids outside', 'There were a few earlier.'],
      <String>['about closing time', 'We close at eight.'],
    ]),
    _CaseFile('deleted server logs', 'whether they ran the delete', 'No. Not me.', <List<String>>[
      <String>['about the backup schedule', 'Nightly, at two.'],
      <String>['when they left Tuesday', 'About seven.'],
      <String>['who has admin access', 'Me and two others.'],
      <String>['about the team lead', 'We get along fine.'],
      <String>['about their commute', 'Train, forty minutes.'],
      <String>['about the server room', 'I badge in most days.'],
    ]),
  ];

  static const List<_Cause> _causes = <_Cause>[
    _Cause('a phone buzzes on the table', 'glances at it and silences it'),
    _Cause('a sneeze comes on', 'sneezes twice and apologizes'),
    _Cause('someone knocks on the door', 'looks over at it'),
    _Cause('a siren passes outside', 'looks toward the window'),
    _Cause('the chair wobbles', 'shifts to steady it'),
    _Cause('the AC kicks on', 'pulls the sleeves down'),
    _Cause('a coffee cup tips', 'catches it and wipes up the drip'),
    _Cause('the lights flicker', 'looks up at them'),
    _Cause('a door slams down the hall', 'flinches and looks over'),
  ];

  /// Habit phrase → moment phrase, for tests.
  @visibleForTesting
  static Map<String, String> get habitToMoment => <String, String>{for (final b in _behaviors) b.habit: b.moment};

  static String _joinHabits(List<String> items) {
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  /// Builds a fresh baseline case. [focus] steers the anomaly toward one flag
  /// (or forces a clean case for [Flag.cleanBaseline]).
  static Challenge generate(math.Random rng, {bool hard = false, Flag? focus, bool? clean}) {
    final name = MemoryContent.names[rng.nextInt(MemoryContent.names.length)];
    final file = _cases[rng.nextInt(_cases.length)];

    // Baseline habits, at most one per group.
    final habitCount = hard ? 3 : 2;
    final shuffled = List<_Behavior>.of(_behaviors)..shuffle(rng);
    final habits = <_Behavior>[];
    for (final b in shuffled) {
      if (habits.length >= habitCount) break;
      if (b.group != null && habits.any((h) => h.group == b.group)) continue;
      habits.add(b);
    }

    final isClean = clean ?? (focus == Flag.cleanBaseline ? true : rng.nextDouble() < 0.35);
    _Behavior? anomaly;
    if (!isClean) {
      final candidates = _behaviors.where((b) => !habits.contains(b)).toList()..shuffle(rng);
      final focused = candidates.where((b) => b.flag == focus).toList();
      anomaly = focused.isNotEmpty ? focused.first : candidates.first;
    }

    // Topics: the accusation plus side questions, each used once.
    final optionCount = hard ? 6 : 5;
    final topics = <List<String>>[
      <String>[file.accusation, file.denial],
      ...(List<List<String>>.of(file.topics)..shuffle(rng)),
    ];
    final lines = <String>[];
    var answer = Challenge.clean;
    var topicIndex = 0;
    String take(String behavior) {
      final t = topics[topicIndex++];
      return 'Asked ${t[0]} → $behavior: "${t[1]}"';
    }

    // The anomaly lands on the accusation only some of the time, but the
    // accusation is always one of the moments.
    final accusation = topics.removeAt(0);
    topics.shuffle(rng);
    final accusationSlot = (anomaly != null && rng.nextDouble() < 0.3) ? 0 : 1 + rng.nextInt(optionCount - 1);
    topics.insert(accusationSlot, accusation);
    final causes = List<_Cause>.of(_causes)..shuffle(rng);
    if (anomaly != null) {
      answer = lines.length;
      lines.add(take(anomaly.moment));
    }
    for (final h in habits) {
      lines.add(take(h.moment));
    }
    lines.add(take('${causes[0].event}; ${causes[0].reaction}'));
    var extra = 0;
    while (lines.length < optionCount) {
      // Fill with more baseline habits (so tells keep showing up as decoys).
      lines.add(take(habits[extra % habits.length].moment));
      extra++;
    }

    // Shuffle, tracking the answer.
    final order = List<int>.generate(lines.length, (i) => i)..shuffle(rng);
    final options = <String>[for (final i in order) lines[i]];
    final correct = answer == Challenge.clean ? Challenge.clean : order.indexOf(answer);

    final habitText = _joinHabits(habits.map((h) => h.habit).toList());
    final context = '$name is questioned about ${file.incident}.\n\n'
        'BASELINE: $name $habitText. This has been true since the interview started.';
    final explainHabits = 'Normal for $name: ${habits.map((h) => h.moment).join(', ')}.';
    final insight = anomaly == null
        ? 'Every tell here is part of $name\'s baseline. $explainHabits The "${causes[0].event}" moment had an '
            'outside cause. With no change from normal there\'s no signal; calling a lie would be a false alarm.'
        : 'Only "${anomaly.moment}" isn\'t in $name\'s baseline. ${anomaly.meaning} $explainHabits '
            'The "${causes[0].event}" moment had an outside cause.';

    return Challenge(
      id: 'gen_${rng.nextInt(1 << 30)}',
      level: 1,
      type: ChallengeType.baseline,
      flag: anomaly?.flag ?? Flag.cleanBaseline,
      prompt: 'Which moment breaks the baseline, if any?',
      context: context,
      options: options,
      correct: <int>{correct},
      insight: insight,
      highLoad: hard,
    );
  }

  /// Swaps a fixed baseline question for a freshly generated one.
  static Challenge live(Challenge c, math.Random rng, {bool? hard}) {
    if (c.type != ChallengeType.baseline) return c;
    return generate(rng, hard: hard ?? c.highLoad, focus: c.flag);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PRACTICE HUB
// ════════════════════════════════════════════════════════════════════════════

enum PracticeMode {
  baselineLab('Baseline Lab', 'Endless fresh baseline cases. How long can your streak go?', Icons.science, Palette.green),
  speed('Speed Round', '90 seconds. As many right answers as you can.', Icons.timer, Palette.orange),
  survival('Survival', 'Three strikes and you\'re out. It gets harder as you go.', Icons.local_fire_department, Palette.red),
  mistakes('Mistake Review', 'Replay the questions you got wrong until they stick.', Icons.replay, Palette.purple),
  daily('Daily Case File', 'Five new cases every day. Bonus IP the first time.', Icons.folder_special, Palette.gold);

  const PracticeMode(this.title, this.subtitle, this.icon, this.color);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class PracticeHubScreen extends StatefulWidget {
  const PracticeHubScreen({super.key, required this.game});
  final GameState game;

  @override
  State<PracticeHubScreen> createState() => _PracticeHubScreenState();
}

class _PracticeHubScreenState extends State<PracticeHubScreen> {
  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    game.addListener(_onChanged);
  }

  @override
  void dispose() {
    game.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _status(PracticeMode mode) {
    final best = game.practiceBest[mode.name] ?? 0;
    return switch (mode) {
      PracticeMode.baselineLab => best == 0 ? 'No streak yet' : 'Best streak: $best',
      PracticeMode.speed => best == 0 ? 'No score yet' : 'Best: $best correct',
      PracticeMode.survival => best == 0 ? 'No score yet' : 'Best: $best correct',
      PracticeMode.mistakes => game.mistakes.isEmpty ? 'No mistakes saved' : '${game.mistakes.length} to review',
      PracticeMode.daily => game.dailyDoneDay == dayIndex() ? 'Done today ✓ (replay for practice)' : 'Ready',
    };
  }

  void _open(PracticeMode mode) {
    if (mode == PracticeMode.mistakes && game.mistakes.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          backgroundColor: Palette.surfaceHigh,
          content: Text('No mistakes saved yet. Wrong answers in quests and practice show up here.',
              style: TextStyle(color: Palette.textPrimary)),
        ));
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PracticeScreen(game: game, mode: mode)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Practice',
                        style: TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Extra reps. No hearts lost.',
                        style: TextStyle(color: Palette.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                StatPill(emoji: '💡', label: '${game.insightPoints} IP', color: Palette.blue, tooltip: 'Insight Points'),
              ],
            ),
            const SizedBox(height: 16),
            InfoBanner(
              icon: Icons.lock_open,
              color: Palette.teal,
              text: 'Mixed modes use every level you\'ve unlocked so far (up to Level ${game.highestUnlockedLevel}).',
            ),
            const SizedBox(height: 14),
            for (final mode in PracticeMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _open(mode),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Palette.border, width: 1.5),
                      ),
                      child: Row(
                        children: <Widget>[
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: mode.color,
                            child: Icon(mode.icon, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  mode.title,
                                  style: const TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 2),
                                Text(mode.subtitle, style: const TextStyle(color: Palette.textMuted, fontSize: 13, height: 1.3)),
                                const SizedBox(height: 4),
                                Text(
                                  _status(mode),
                                  style: TextStyle(color: mode.color, fontSize: 12.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Palette.textMuted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PracticePhase { answering, feedback, over }

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key, required this.game, required this.mode});
  final GameState game;
  final PracticeMode mode;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> with SingleTickerProviderStateMixin {
  static const int speedSeconds = 90;
  static const int survivalStrikes = 3;
  static const int dailyBonus = 25;

  final math.Random _rng = math.Random();
  late final AnimationController _sheetController;
  late final Animation<Offset> _sheetOffset;

  late Challenge _current;
  List<Challenge> _fixed = <Challenge>[];
  int _fixedIndex = 0;
  int _serial = 0;

  _PracticePhase _phase = _PracticePhase.answering;
  Set<int> _selection = <int>{};
  bool _lastCorrect = false;
  bool? _flash;

  int _score = 0;
  int _answered = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _strikes = 0;
  int _ipEarned = 0;
  int _secondsLeft = speedSeconds;
  Timer? _clock;
  bool _newBest = false;
  bool _bonusAwarded = false;

  GameState get game => widget.game;
  PracticeMode get mode => widget.mode;

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _sheetOffset = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _sheetController, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
    );
    _start();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _start() {
    _score = 0;
    _answered = 0;
    _streak = 0;
    _bestStreak = 0;
    _strikes = 0;
    _ipEarned = 0;
    _newBest = false;
    _bonusAwarded = false;
    _fixedIndex = 0;
    _fixed = switch (mode) {
      PracticeMode.mistakes => (game.mistakes
          .map((id) => Curriculum.byId[id])
          .whereType<Challenge>()
          .map((c) => c.shuffled(_rng))
          .toList()
        ..shuffle(_rng)),
      PracticeMode.daily => _dailySet(),
      _ => <Challenge>[],
    };
    _clock?.cancel();
    if (mode == PracticeMode.speed) {
      _secondsLeft = speedSeconds;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) _finish();
      });
    }
    if ((mode == PracticeMode.mistakes || mode == PracticeMode.daily) && _fixed.isEmpty) {
      _phase = _PracticePhase.over;
      return;
    }
    _phase = _PracticePhase.answering;
    _current = _nextChallenge();
    _selection = <int>{};
    _serial++;
  }

  List<Challenge> _dailySet() {
    final seeded = math.Random(dayIndex() * 7919 + 17);
    final maxLevel = game.highestUnlockedLevel;
    final pool = Curriculum.challenges.where((c) => c.level <= maxLevel).toList()..shuffle(seeded);
    return pool.take(5).map((c) => BaselineGenerator.live(c, seeded).shuffled(seeded)).toList();
  }

  Challenge _randomChallenge({required bool hard}) {
    final maxLevel = game.highestUnlockedLevel;
    var pool = Curriculum.challenges.where((c) => c.level <= maxLevel && c.highLoad == hard).toList();
    if (pool.isEmpty) pool = Curriculum.challenges.where((c) => c.level <= maxLevel).toList();
    final pick = pool[_rng.nextInt(pool.length)];
    return BaselineGenerator.live(pick, _rng).shuffled(_rng);
  }

  Challenge _nextChallenge() => switch (mode) {
        PracticeMode.baselineLab =>
          BaselineGenerator.generate(_rng, hard: _streak >= 5 && _rng.nextBool()).shuffled(_rng),
        PracticeMode.speed => _randomChallenge(hard: _rng.nextDouble() < 0.3),
        PracticeMode.survival => _randomChallenge(hard: _rng.nextDouble() < math.min(0.85, _score * 0.07)),
        PracticeMode.mistakes || PracticeMode.daily => _fixed[_fixedIndex],
      };

  bool get _canCheck => _phase == _PracticePhase.answering && _selection.length == _current.requiredSelections;

  void _onOptionTap(int index) {
    if (_phase != _PracticePhase.answering) return;
    final c = _current;
    if (c.isMultiSelect) {
      if (_selection.contains(index)) {
        setState(() => _selection = <int>{..._selection}..remove(index));
      } else if (_selection.length < c.requiredSelections) {
        setState(() => _selection = <int>{..._selection, index});
      } else {
        HapticFeedback.heavyImpact();
        return;
      }
    } else {
      setState(() => _selection = <int>{index});
    }
    HapticFeedback.selectionClick();
  }

  void _check() {
    if (!_canCheck) return;
    final correct = setEquals(_selection, _current.correct);
    final ip = correct ? (mode == PracticeMode.speed ? 2 : 3) : 0;
    game.recordPractice(_current, correct: correct, ip: ip);
    _ipEarned += ip;
    _answered++;
    if (correct) {
      _score++;
      _streak++;
      _bestStreak = math.max(_bestStreak, _streak);
      HapticFeedback.mediumImpact();
    } else {
      _streak = 0;
      _strikes++;
      HapticFeedback.heavyImpact();
    }
    if (mode == PracticeMode.speed) {
      setState(() {
        _flash = correct;
        _phase = _PracticePhase.feedback;
      });
      Future<void>.delayed(const Duration(milliseconds: 650), () {
        if (!mounted || _phase == _PracticePhase.over) return;
        _advance();
      });
      return;
    }
    setState(() {
      _lastCorrect = correct;
      _phase = _PracticePhase.feedback;
    });
    _sheetController.forward(from: 0);
  }

  Future<void> _continue() async {
    await _sheetController.reverse();
    if (!mounted) return;
    _advance();
  }

  void _advance() {
    final fixedMode = mode == PracticeMode.mistakes || mode == PracticeMode.daily;
    if (mode == PracticeMode.survival && _strikes >= survivalStrikes) {
      _finish();
      return;
    }
    if (fixedMode) {
      _fixedIndex++;
      if (_fixedIndex >= _fixed.length) {
        _finish();
        return;
      }
    }
    setState(() {
      _current = _nextChallenge();
      _selection = <int>{};
      _flash = null;
      _phase = _PracticePhase.answering;
      _serial++;
    });
  }

  void _finish() {
    if (_phase == _PracticePhase.over) return;
    _clock?.cancel();
    final value = mode == PracticeMode.baselineLab ? _bestStreak : _score;
    if (mode == PracticeMode.speed || mode == PracticeMode.survival || mode == PracticeMode.baselineLab) {
      _newBest = game.reportPracticeScore(mode.name, value);
    }
    if (mode == PracticeMode.daily) {
      _bonusAwarded = game.completeDaily(dailyBonus);
    } else {
      game.touchPracticeStreak();
    }
    setState(() => _phase = _PracticePhase.over);
  }

  Future<void> _handleBack() async {
    if (_phase == _PracticePhase.over || _answered == 0) {
      Navigator.of(context).pop();
      return;
    }
    if (mode == PracticeMode.baselineLab) {
      _finish();
      return;
    }
    final quit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('End this run?', style: TextStyle(color: Palette.textPrimary)),
        content: const Text('Points you earned are kept.', style: TextStyle(color: Palette.textMuted)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('KEEP GOING')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('END', style: TextStyle(color: Palette.red)),
          ),
        ],
      ),
    );
    if (quit == true && mounted) _finish();
  }

  String get _headerStat {
    return switch (mode) {
      PracticeMode.baselineLab => 'Streak $_streak · best ${math.max(_bestStreak, game.practiceBest[mode.name] ?? 0)}',
      PracticeMode.speed => '⏱ ${math.max(0, _secondsLeft)}s · $_score correct',
      PracticeMode.survival => '${'❤️' * (survivalStrikes - _strikes)}${'🖤' * _strikes} · $_score',
      PracticeMode.mistakes => '${math.min(_fixedIndex + 1, _fixed.length)}/${_fixed.length}',
      PracticeMode.daily => 'Case ${math.min(_fixedIndex + 1, _fixed.length)}/${_fixed.length}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: Palette.background,
        body: SafeArea(child: _phase == _PracticePhase.over ? _buildOver() : _buildRun()),
      ),
    );
  }

  Widget _buildRun() {
    final revealed = _phase == _PracticePhase.feedback && mode != PracticeMode.speed;
    final screenHeight = MediaQuery.of(context).size.height;
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 16, 4),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'End',
                    onPressed: _handleBack,
                    icon: const Icon(Icons.close, color: Palette.textMuted, size: 28),
                  ),
                  Expanded(
                    child: Text(
                      mode.title.toUpperCase(),
                      style: TextStyle(color: mode.color, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ),
                  Text(_headerStat, style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            if (mode == PracticeMode.speed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (_secondsLeft / speedSeconds).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Palette.surfaceHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(mode.color),
                  ),
                ),
              ),
            if (_flash != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: InfoBanner(
                  icon: _flash! ? Icons.check_circle : Icons.cancel,
                  color: _flash! ? Palette.green : Palette.red,
                  text: _flash! ? 'Correct' : 'Wrong: ${_current.correctAnswerText}',
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey<int>(_serial),
                padding: EdgeInsets.fromLTRB(16, 12, 16, revealed ? screenHeight * 0.55 : 24),
                child: ChallengeView(
                  challenge: _current,
                  selection: _selection,
                  revealed: revealed || _flash != null,
                  onOptionTap: _onOptionTap,
                ),
              ),
            ),
            if (_phase == _PracticePhase.answering)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ChunkyButton(
                  label: _current.isMultiSelect && _selection.length < _current.requiredSelections
                      ? 'Select ${_current.requiredSelections - _selection.length} more'
                      : 'Check answer',
                  color: mode.color,
                  onPressed: _canCheck ? _check : null,
                ),
              ),
          ],
        ),
        if (_phase == _PracticePhase.feedback && mode != PracticeMode.speed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _sheetOffset,
              child: FeedbackSheet(
                correct: _lastCorrect,
                challenge: _current,
                ipGain: _lastCorrect ? 3 : 0,
                heartsLeft: 0,
                practice: true,
                onContinue: _continue,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOver() {
    final best = game.practiceBest[mode.name] ?? 0;
    final headline = switch (mode) {
      PracticeMode.baselineLab => 'Best streak this run: $_bestStreak',
      PracticeMode.speed => '$_score correct in $speedSeconds seconds',
      PracticeMode.survival => 'You survived $_score questions',
      PracticeMode.mistakes => '$_score of $_answered fixed',
      PracticeMode.daily => '$_score of ${_fixed.length} cases solved',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: <Widget>[
          const Spacer(),
          Text(_newBest ? '🏆' : '🎯', style: const TextStyle(fontSize: 72)),
          const SizedBox(height: 12),
          Text(
            _newBest ? 'New personal best!' : 'Run complete',
            style: TextStyle(color: _newBest ? Palette.gold : Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(headline, textAlign: TextAlign.center, style: const TextStyle(color: Palette.textPrimary, fontSize: 17)),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Palette.border, width: 1.5),
            ),
            child: Column(
              children: <Widget>[
                _BreakdownLine(label: 'Insight Points', value: '+${_ipEarned + (_bonusAwarded ? dailyBonus : 0)} IP'),
                if (_bonusAwarded) const _BreakdownLine(label: 'Daily case bonus', value: '+$dailyBonus IP'),
                if (mode == PracticeMode.speed || mode == PracticeMode.survival || mode == PracticeMode.baselineLab)
                  _BreakdownLine(label: 'Personal best', value: '$best'),
                if (mode == PracticeMode.mistakes)
                  _BreakdownLine(label: 'Mistakes left', value: '${game.mistakes.length}'),
              ],
            ),
          ),
          const Spacer(),
          ChunkyButton(label: 'Done', color: Palette.green, onPressed: () => Navigator.of(context).pop()),
          const SizedBox(height: 8),
          if (mode != PracticeMode.mistakes || game.mistakes.isNotEmpty)
            TextButton(
              onPressed: () => setState(_start),
              child: const Text(
                'PLAY AGAIN',
                style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  SHARED UI
// ════════════════════════════════════════════════════════════════════════════

/// Duolingo-style 3D button that sinks when pressed.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Palette.green,
    this.textColor = Colors.white,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final double height;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  static const double _depth = 5;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final face = enabled ? widget.color : Palette.locked;
    final edge = enabled ? darken(widget.color, 0.15) : darken(Palette.locked, 0.08);
    final labelColor = enabled ? widget.textColor : Palette.lockedIcon;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          height: widget.height + _depth,
          width: double.infinity,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: widget.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(16)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 70),
                left: 0,
                right: 0,
                top: _pressed ? _depth : 0,
                height: widget.height,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: face, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    widget.label.toUpperCase(),
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.padding = EdgeInsets.zero,
  });

  final IconData icon;
  final Color color;
  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(34),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(130)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
