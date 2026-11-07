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
  cleanStatement('Spotting Truthful Statements', ChallengeType.statement),
  unverifiable('Uncheckable Details', ChallengeType.statement),
  vagueCore('Vague Where It Counts', ChallengeType.statement),
  cognitiveLoad('Raising Cognitive Load', ChallengeType.scenario),
  evidenceTiming('Timing Your Evidence', ChallengeType.scenario),
  mythBusting('Busting Lie Myths', ChallengeType.scenario),
  othelloError('Avoiding False Alarms', ChallengeType.scenario),
  deduction('Deduction', ChallengeType.scenario),
  coldReading('Cold Reading Tricks', ChallengeType.scenario);

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
    int level = 7,
    String prompt = 'What\'s your best next move?',
  }) =>
      Challenge(
        id: id,
        level: level,
        type: ChallengeType.scenario,
        flag: flag,
        prompt: prompt,
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
    this.questLength = 6,
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
    LevelInfo(9, 'Checkable Details', 'Truth can be checked. Lies hide where it can\'t.', Palette.gold,
        ChallengeType.statement),
    LevelInfo(10, 'Making Lies Hard Work', 'Questions that overload a liar and spare the truthful', Palette.red,
        ChallengeType.scenario),
    LevelInfo(11, 'Myths & False Alarms', 'What doesn\'t mean lying, and how innocent people get blamed',
        Palette.purple, ChallengeType.scenario),
    LevelInfo(12, 'Deduction & Cold Reading', 'Think like Patrick Jane: clues, guesses and tricks', Palette.teal,
        ChallengeType.scenario),
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
      questLength: 7,
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
      questLength: 7,
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
      questLength: 7,
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
      questLength: 7,
    ),
    SkillNode(
      id: 'l5a',
      level: 5,
      title: 'Qualifiers & Minimizing',
      description: '"To be honest", "I swear", "just a little": words that try to sound true or shrink things.',
      icon: Icons.campaign,
    ),
    SkillNode(
      id: 'l5b',
      level: 5,
      title: 'Distance & Stalling',
      description: '"That woman", "the individual", and repeating the question back to buy time.',
      icon: Icons.social_distance,
    ),
    SkillNode(
      id: 'r5',
      level: 5,
      title: 'Verbal Review',
      description: 'Levels 1–5 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 7,
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
      questLength: 7,
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
      questLength: 7,
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
      id: 'r8',
      level: 8,
      title: 'Digital Review',
      description: 'Levels 1–8 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 7,
    ),
    SkillNode(
      id: 'l9a',
      level: 9,
      title: 'Checkable or Not',
      description: 'Truthful stories hand you names, places and receipts. Lies hide the key part where no one can check.',
      icon: Icons.fact_check,
    ),
    SkillNode(
      id: 'l9b',
      level: 9,
      title: 'Vague Where It Counts',
      description: 'Sharp detail before and after, then a blur right at the moment that matters.',
      icon: Icons.blur_on,
    ),
    SkillNode(
      id: 'r9',
      level: 9,
      title: 'Details Review',
      description: 'Levels 1–9 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 7,
    ),
    SkillNode(
      id: 'l10a',
      level: 10,
      title: 'Cognitive Load',
      description: 'Backwards stories, unexpected questions and sketches: make lying hard work.',
      icon: Icons.psychology_alt,
    ),
    SkillNode(
      id: 'l10b',
      level: 10,
      title: 'Timing Your Evidence',
      description: 'Hold back what you know until they commit to a story.',
      icon: Icons.hourglass_bottom,
    ),
    SkillNode(
      id: 'r10',
      level: 10,
      title: 'Tactics Review II',
      description: 'Levels 1–10 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 7,
    ),
    SkillNode(
      id: 'l11a',
      level: 11,
      title: 'Lie Myths',
      description: 'Eye direction, nose touching, crossed arms: what the research actually says.',
      icon: Icons.do_not_disturb_alt,
    ),
    SkillNode(
      id: 'l11b',
      level: 11,
      title: 'False Alarms',
      description: 'The Othello error: when honest fear looks like guilt.',
      icon: Icons.notification_important,
    ),
    SkillNode(
      id: 'r11',
      level: 11,
      title: 'Myths Review',
      description: 'Levels 1–11 mixed, calibrated to your weak spots.',
      icon: Icons.fitness_center,
      isReview: true,
      questLength: 7,
    ),
    SkillNode(
      id: 'l12a',
      level: 12,
      title: 'Deduction',
      description: 'Combine small clues into the one story that explains all of them.',
      icon: Icons.search,
    ),
    SkillNode(
      id: 'l12b',
      level: 12,
      title: 'Cold Reading Tricks',
      description: 'Barnum statements, shotgunning and safe guesses: how mentalists seem psychic.',
      icon: Icons.auto_awesome,
    ),
    SkillNode(
      id: 'exam',
      level: 12,
      title: 'Master Exam',
      description: 'The final adaptive exam across all twelve levels, calibrated to your profile.',
      icon: Icons.emoji_events,
      isReview: true,
      questLength: 12,
    ),
  ];

  /// Lessons that teach specific skills; the other lesson of the level gets the rest.
  static const Map<String, Set<Flag>> _lessonFlags = <String, Set<Flag>>{
    'l4a': <Flag>{Flag.pronounDrop, Flag.temporalGap},
    'l5a': <Flag>{Flag.qualifier, Flag.minimizing},
    'l7a': <Flag>{Flag.openQuestion, Flag.rapport},
    'l9a': <Flag>{Flag.unverifiable},
    'l10a': <Flag>{Flag.cognitiveLoad},
    'l11a': <Flag>{Flag.mythBusting},
    'l12a': <Flag>{Flag.deduction},
  };

  /// Each lesson's own questions, so the two lessons of a level never repeat
  /// each other. Truthful ("nothing here") cases are shared out evenly.
  static final Map<String, List<Challenge>> lessonPools = _buildLessonPools();

  static Map<String, List<Challenge>> _buildLessonPools() {
    final pools = <String, List<Challenge>>{};
    for (final info in levels) {
      final lessons = nodes.where((n) => n.level == info.number && !n.isReview).toList();
      final a = <Challenge>[];
      final b = <Challenge>[];
      final clean = <Challenge>[];
      final flagsA = _lessonFlags[lessons.first.id];
      var i = 0;
      for (final c in challenges.where((c) => c.level == info.number)) {
        if (flagsA == null) {
          (i++.isEven ? a : b).add(c);
        } else if (c.isClean) {
          clean.add(c);
        } else {
          (flagsA.contains(c.flag) ? a : b).add(c);
        }
      }
      for (final c in clean) {
        (a.length <= b.length ? a : b).add(c);
      }
      pools[lessons.first.id] = a;
      if (lessons.length > 1) pools[lessons[1].id] = b;
    }
    return pools;
  }

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
    // ── Level 9: Checkable Details ──────────────────────────────────────
    Challenge.statement(
      id: 'ck1',
      flag: Flag.unverifiable,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked where she was Saturday night when the party got out of hand:',
      sentences: <String>[
        'I left work at six and got tacos at Lupe\'s with my sister Dana.',
        'After that I just drove around alone for a few hours.',
        'I got home around eleven and texted Dana goodnight.',
      ],
      answer: 1,
      insight: 'The first and last sentences can be checked: a named restaurant, a named sister, a text. The hours that matter are spent alone, nowhere, with nothing to check. Liars put the uncheckable details exactly where the gap is.',
    ),
    Challenge.statement(
      id: 'ck2',
      flag: Flag.cleanStatement,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked what he did the afternoon the store\'s register came up short:',
      sentences: <String>[
        'I opened at noon with Priya and we counted the drawer together.',
        'At three I signed for the Pepsi delivery; the driver was Carl.',
        'I clocked out at 5:04 and Priya closed the drawer after me.',
      ],
      answer: Challenge.clean,
      insight: 'Every sentence names a person, a time or a record someone could check: the drawer count, the delivery slip, the time clock. Truth-tellers offer checkable details freely because they know they\'ll hold up.',
    ),
    Challenge.statement(
      id: 'ck3',
      flag: Flag.vagueCore,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked about the new dent in the family car:',
      sentences: <String>[
        'I drove to the mall on Route 9 around four to get Mom\'s gift.',
        'I parked on the second level of the garage by the Target doors.',
        'Then something must have happened at some point.',
        'After that I drove straight home and parked in the driveway.',
      ],
      answer: 2,
      insight: 'Precise before and after (Route 9, level two, the Target doors), then a blur right where the dent happened. Detail that drops out only at the key moment is a classic sign of an edited story.',
    ),
    Challenge.statement(
      id: 'ck4',
      flag: Flag.cleanStatement,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'A friend explains why she missed your game:',
      sentences: <String>[
        'My car battery died in the Kroger lot on Elm Street.',
        'A guy from the store gave me a jump, but it died again a mile later.',
        'I called AAA at 5:40 and they towed it to Midas; I have the receipt.',
      ],
      answer: Challenge.clean,
      insight: 'Store, street, times, a tow company and a receipt: all checkable. She even includes a detail that makes the story messier (it died again). The unnamed guy isn\'t a flag here; the key events don\'t depend on him.',
    ),
    Challenge.statement(
      id: 'ck5',
      flag: Flag.unverifiable,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked how he had the answers to the history test:',
      sentences: <String>[
        'Some kid I don\'t know posted a guide in a chat.',
        'I studied it Wednesday night at my kitchen table.',
        'My mom saw me studying and quizzed me on the dates.',
      ],
      answer: 0,
      insight: 'Where the answers came from is the key fact, and it\'s the one detail nobody can trace: an unnamed kid in an unnamed chat. Ask: "Which chat? Show me." Truth-tellers can usually point you to it.',
    ),
    Challenge.statement(
      id: 'ck6',
      flag: Flag.cleanStatement,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked why she wasn\'t at roll call during the fire drill:',
      sentences: <String>[
        'I was in the nurse\'s office with a nosebleed from chemistry.',
        'Ms. Ortiz wrote me a pass at 10:20; it\'s still in my backpack.',
        'The nurse told me to stay put during the drill, so I did.',
      ],
      answer: Challenge.clean,
      insight: 'A teacher, a timed pass she still has, and a nurse who can confirm it. Everything important can be checked, and she points you to the proof herself.',
    ),
    Challenge.statement(
      id: 'ck7',
      flag: Flag.vagueCore,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked why the delivery was two hours late:',
      sentences: <String>[
        'I loaded the van at the warehouse at 8:15 and left at 8:30.',
        'Then there was stuff going on with traffic and things.',
        'I dropped the first order on Bell Street at 11:10; it\'s signed.',
      ],
      answer: 1,
      insight: 'Exact times on both sides, and the missing two hours get "stuff" and "things". Real traffic comes with a road, a crash, a detour. Ask: "Which road? Where were you stuck?"',
    ),
    Challenge.statement(
      id: 'ck8',
      flag: Flag.unverifiable,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked where the \$200 from the fundraiser went:',
      sentences: <String>[
        'I counted it Friday with Coach Reyes after the bake sale.',
        'I put it in the blue envelope and locked it in my locker.',
        'Sunday I gave it to a parent who said they\'d deposit it.',
      ],
      answer: 2,
      insight: 'The money is tracked carefully, with a named coach and a locker, right up until it leaves his hands. Then it goes to "a parent" with no name. The handoff is the one moment that matters, and the one you can\'t check.',
    ),
    Challenge.statement(
      id: 'ck9',
      flag: Flag.unverifiable,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked why he wasn\'t at practice on Tuesday:',
      sentences: <String>[
        'I had a doctor\'s appointment for my knee.',
        'It was at a clinic across town, I forget the name.',
        'The doctor said to rest it for a few days, so I did.',
      ],
      answer: 1,
      insight: 'A real appointment comes with a clinic name, a parking lot, a co-pay. "I forget the name" sits exactly on the checkable part. Ask for the appointment text or the bill.',
    ),
    Challenge.statement(
      id: 'ck10',
      flag: Flag.unverifiable,
      level: 9,
      highLoad: true,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'An employee explains how a work laptop went missing:',
      sentences: <String>[
        'I worked from the Fifth Street library Thursday, second floor by the windows.',
        'I badged in at 9:12, and my login history will show the library Wi-Fi.',
        'Around two I went downstairs to get a coffee from the cart.',
        'When I got back, a man near me said someone had taken it.',
        'I told library security before I left.',
      ],
      answer: 3,
      insight: 'Everything around the theft is checkable: the badge, the Wi-Fi, security. But the only witness to the moment itself is an unnamed stranger. Check the security report: did it mention him?',
    ),
    Challenge.statement(
      id: 'ck11',
      flag: Flag.cleanStatement,
      level: 9,
      highLoad: true,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'A roommate explains why the rent was paid late:',
      sentences: <String>[
        'My paycheck from the hospital didn\'t clear until Tuesday.',
        'Honestly, I forgot Monday was a bank holiday, which is on me.',
        'I sent the landlord a Venmo at 7:02 Tuesday morning with an apology.',
        'You can see the timestamp, and I\'ll cover the late fee.',
      ],
      answer: Challenge.clean,
      insight: 'A qualifier like "honestly" isn\'t a flag on its own. Here it\'s attached to an admission against herself. The rest is checkable: payday, the holiday, a timestamped payment.',
    ),
    Challenge.statement(
      id: 'ck12',
      flag: Flag.vagueCore,
      level: 9,
      highLoad: true,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'A teen explains getting home at 2 a.m.:',
      sentences: <String>[
        'We saw the 9:40 showing of the new Marvel movie at the Regal.',
        'It ended around midnight and Jake\'s mom picked us up out front.',
        'Then we were kind of hanging out for a while.',
        'Jake\'s mom dropped me off after; you can ask her.',
      ],
      answer: 2,
      insight: 'Two hours are missing between midnight and 2 a.m., and they\'re the only vague part. Notice the offer to "ask Jake\'s mom" covers the pickup and drop-off, not the middle. Ask where they were hanging out.',
    ),
    Challenge.statement(
      id: 'ck13',
      flag: Flag.cleanStatement,
      level: 9,
      highLoad: true,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'A contractor explains why the job is a week behind:',
      sentences: <String>[
        'The tile from Floor & Decor came in gray instead of white.',
        'I have the order number and the photo I sent them on the 12th.',
        'They promised a replacement by Friday, but it got backordered.',
        'I can forward you their email if you want to see it.',
      ],
      answer: Challenge.clean,
      insight: 'A store, an order number, a dated photo and an email he offers to forward. When someone hands you the means to check their story, that\'s one of the strongest truth signals there is.',
    ),
    Challenge.statement(
      id: 'ck14',
      flag: Flag.unverifiable,
      level: 9,
      highLoad: true,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked how the dog got out of the yard:',
      sentences: <String>[
        'I fed him at 6:30 and put him out back while I made dinner.',
        'Someone, maybe a delivery guy, must have left the gate open.',
        'At seven I called him and he didn\'t come, so I checked the yard.',
        'I posted on the neighborhood app at 7:15 and drove around looking.',
      ],
      answer: 1,
      insight: 'The only part that explains the gate blames an imagined, unnamed person. That\'s where to check: was there a delivery? Is there a doorbell camera? A guess that points away from yourself deserves a follow-up, not a verdict.',
    ),

    // ── Level 10: Making Lies Hard Work ─────────────────────────────────
    Challenge.scenario(
      id: 'lw1',
      level: 10,
      flag: Flag.cognitiveLoad,
      context: 'Your little brother says he was at Sam\'s house all afternoon. You think he was at the skate park he\'s banned from. His story comes out smooth, like he practiced it.',
      moves: <String>[
        'Ask him to tell it backwards, from leaving Sam\'s.',
        'Ask: "Were you at Sam\'s the whole afternoon?"',
        'Tell him you know he\'s lying, then stay silent.',
        'Make him swear on something that he was at Sam\'s.',
      ],
      answer: 0,
      insight: 'A rehearsed story runs smoothly forward. Telling it in reverse adds mental load: a liar has to rebuild it, while a truth-teller just remembers. Watch for stalls and new contradictions.',
    ),
    Challenge.scenario(
      id: 'lw2',
      level: 10,
      flag: Flag.cognitiveLoad,
      context: 'A coworker says she missed the meeting because she was stuck at the dentist. Her answer came fast and complete.',
      moves: <String>[
        'Ask whether she was really at the dentist.',
        'Ask what the waiting room looked like.',
        'Ask what time her appointment started.',
        'Tell her the boss was annoyed about it.',
      ],
      answer: 1,
      insight: 'Time and place are the questions liars prepare for. An unexpected question about a side detail raises the load. A truth-teller answers it easily; a liar stalls or goes generic.',
    ),
    Challenge.scenario(
      id: 'lw3',
      level: 10,
      flag: Flag.evidenceTiming,
      context: 'You found a receipt showing your friend was at the mall on Friday, but he told the group he was home sick. You want the truth.',
      moves: <String>[
        'Show him the receipt right away so he can\'t deny it.',
        'Ask about his Friday; keep the receipt to yourself.',
        'Post the receipt in the group chat to see how he reacts.',
        'Ask him: "You weren\'t at the mall, were you?"',
      ],
      answer: 1,
      insight: 'Strategic Use of Evidence: if you reveal what you know first, a liar just builds the story around it. Let him commit to a version, then compare it with the receipt. A truthful story will fit; a lie won\'t.',
    ),
    Challenge.scenario(
      id: 'lw4',
      level: 10,
      flag: Flag.evidenceTiming,
      context: 'Your sister says she never borrowed your hoodie. You saw it in her laundry pile this morning.',
      moves: <String>[
        'Ask her when she last saw your hoodie.',
        'Grab it from her laundry and hold it up in front of her.',
        'Tell her you saw it in her room this morning.',
        'Ask your parents to search her room for it.',
      ],
      answer: 0,
      insight: 'A question she can answer either way lets her commit. If she says "I haven\'t seen it in weeks", you\'ve caught a clear contradiction instead of starting an argument.',
    ),
    Challenge.scenario(
      id: 'lw5',
      level: 10,
      flag: Flag.cognitiveLoad,
      context: 'A job candidate says he led a big project at his last job. His answers sound polished, like he\'s given them many times.',
      moves: <String>[
        'Ask if he really led the project himself.',
        'Ask him to draw the team and who did what.',
        'Ask about his greatest strength as a leader.',
        'Thank him and move on to the next question on the list.',
      ],
      answer: 1,
      insight: 'Drawing or laying things out forces specifics a rehearsed answer doesn\'t have. People who did the work place names and roles easily; people inflating their role go vague.',
    ),
    Challenge.scenario(
      id: 'lw6',
      level: 10,
      flag: Flag.cognitiveLoad,
      context: 'A friend says she can\'t come to your party because of "just a family thing." Her answer is short and vague.',
      moves: <String>[
        'Say "okay, no worries" and drop it.',
        'Ask where it is and who\'s coming.',
        'Ask her if she\'s mad at you about something.',
        'Tell her everyone else is coming, so she should too.',
      ],
      answer: 1,
      insight: 'A real plan expands easily: "my aunt\'s house, my cousins from Ohio". A cover story stays thin. Asking for more, in a friendly way, is the simplest load-raiser there is. (And if she just doesn\'t want to come, you\'ve learned that too.)',
    ),
    Challenge.scenario(
      id: 'lw7',
      level: 10,
      flag: Flag.evidenceTiming,
      context: 'The class hamster got out. One student had cage duty, and the sign-in sheet shows he went into the classroom at lunch. He doesn\'t know you\'ve seen it.',
      moves: <String>[
        'Ask him to walk you through his lunch period.',
        'Tell him the sign-in sheet shows he was in the room.',
        'Ask the whole class who let the hamster out.',
        'Ask him directly: "Did you open the cage?"',
      ],
      answer: 0,
      insight: 'Let him tell his lunch period in his own words first. If he leaves out the classroom visit, that omission is your best clue. Bring up the sign-in sheet only after he\'s committed.',
    ),
    Challenge.scenario(
      id: 'lw8',
      level: 10,
      flag: Flag.cognitiveLoad,
      context: 'Your friend tells an unlikely story about meeting a famous rapper at a gas station. You want to test it without calling him a liar.',
      moves: <String>[
        'Tell him straight out that it never happened.',
        'Later, casually ask him to tell it again.',
        'Search it online right away in front of him.',
        'Ask him to swear the whole story is true.',
      ],
      answer: 1,
      insight: 'True memories keep the same core details when retold. Invented ones drift (the time changes, the car changes) or come out word-for-word like a script. Retelling tests a story without accusing anyone.',
    ),
    Challenge.scenario(
      id: 'lw9',
      level: 10,
      flag: Flag.evidenceTiming,
      highLoad: true,
      context: 'A store manager suspects an employee of voiding sales and keeping the cash. The register log shows six voids on her shifts, all between 2 and 3 p.m. She doesn\'t know about the log.',
      moves: <String>[
        'Show her the register log and ask her to explain all six voids.',
        'Ask her about a normal shift first, then about voids.',
        'Ask her coworkers if they have seen her voiding sales.',
        'Say the cameras caught everything and see if she confesses.',
      ],
      answer: 1,
      insight: 'Let her describe her routine and when voids happen ("only when a customer changes their mind"). Then bring out the 2 to 3 p.m. pattern piece by piece. Evidence she can\'t square with her own story beats any pushed confession. Bluffing about cameras can make an innocent person panic too.',
    ),
    Challenge.scenario(
      id: 'lw10',
      level: 10,
      flag: Flag.cognitiveLoad,
      highLoad: true,
      context: 'Two friends say they spent Saturday together at the lake. You think they\'re covering for each other. You can talk to each one alone.',
      moves: <String>[
        'Ask them together to tell you all about the lake.',
        'Ask each alone about lunch, the weather and who drove.',
        'Ask each one alone whether the other one is lying.',
        'Say you already know, and ask them together who planned it.',
      ],
      answer: 1,
      insight: 'People covering for each other agree on the main story but not the side details they didn\'t plan. Separate questions about small, unexpected details show mismatches. Together, they just follow each other\'s lead.',
    ),
    Challenge.scenario(
      id: 'lw11',
      level: 10,
      flag: Flag.evidenceTiming,
      highLoad: true,
      context: 'Your cousin says he hasn\'t vaped since he promised to quit. You found a vape charger in his car. He\'s calm and friendly.',
      moves: <String>[
        'Put the charger on the table and wait for him to explain.',
        'Ask if anyone else has used his car lately.',
        'Tell your aunt about the charger before you talk to him.',
        'Ask him why he keeps lying to the whole family.',
      ],
      answer: 1,
      insight: 'Close the exits before you show evidence. If he first says "nobody else drives my car" and "I threw all my vape stuff out", the charger means something. Show it first and he\'ll say it\'s a friend\'s, or old.',
    ),
    Challenge.scenario(
      id: 'lw12',
      level: 10,
      flag: Flag.cognitiveLoad,
      highLoad: true,
      context: 'You\'re asking a friend about a rumor she may have started. She\'s getting defensive and her answers are getting shorter.',
      moves: <String>[
        'Raise your voice so she knows how serious it is.',
        'Ease off, then ask her to tell you about that day.',
        'List every piece of evidence you have against her.',
        'Tell her everybody already knows it was her.',
      ],
      answer: 1,
      insight: 'Pressure makes truthful and lying people both shut down, so you learn nothing. Load works when the person is talking. Lower the heat, ask for the whole day, and let details (or gaps) pile up.',
    ),

    // ── Level 11: Myths & False Alarms ──────────────────────────────────
    Challenge.scenario(
      id: 'mf1',
      level: 11,
      flag: Flag.mythBusting,
      prompt: 'What\'s the best read?',
      context: 'Asked about a broken vase, your friend looks away while he answers. Someone says: "See? Liars can\'t look you in the eye."',
      moves: <String>[
        'Looking away is a reliable sign of lying.',
        'Alone, it means little. Check his baseline.',
        'He\'s telling the truth, since liars stare at you.',
        'He looks ashamed, so he probably broke it.',
      ],
      answer: 1,
      insight: 'Gaze aversion is the most famous "tell", and it\'s a myth. Studies find almost no link between eye contact and lying. People look away to think, from shyness, or because of their culture. Practiced liars often hold eye contact on purpose.',
    ),
    Challenge.scenario(
      id: 'mf2',
      level: 11,
      flag: Flag.othelloError,
      prompt: 'What\'s the best read?',
      context: 'Your mom angrily asks your brother if he dented the car. His voice shakes and his hands tremble. He says no.',
      moves: <String>[
        'The trembling means he\'s lying to her.',
        'Fear fits an innocent kid too. Ask more.',
        'He\'s calm inside and faking the shaking.',
        'He\'s guilty, because innocent people don\'t get nervous.',
      ],
      answer: 1,
      insight: 'This is the Othello error, named after Shakespeare\'s Othello, who read Desdemona\'s fear as guilt. Honest people get scared of not being believed, especially by an angry parent. Fear tells you about the situation, not the truth.',
    ),
    Challenge.scenario(
      id: 'mf3',
      level: 11,
      flag: Flag.mythBusting,
      prompt: 'What\'s the best read?',
      context: 'A viral video says: "If someone looks up and to the right, they\'re making something up."',
      moves: <String>[
        'True: right is the brain\'s "creating" side.',
        'True, but only for right-handed people.',
        'False: eye direction doesn\'t show lying.',
        'True for strangers, but not for friends.',
      ],
      answer: 2,
      insight: 'This comes from an old NLP claim. When researchers actually tested it, eye direction didn\'t predict lying at all. It spreads because it sounds scientific.',
    ),
    Challenge.scenario(
      id: 'mf4',
      level: 11,
      flag: Flag.othelloError,
      prompt: 'What\'s the best read?',
      context: 'A new kid is quiet, fidgets a lot and rarely smiles. Someone\'s phone went missing and people say it was him.',
      moves: <String>[
        'He fits the profile of a thief.',
        'That\'s a nervous new kid, not evidence.',
        'His fidgeting proves he\'s hiding something.',
        'He\'s quiet because he\'s planning his next theft.',
      ],
      answer: 1,
      insight: 'Judging by personality or "shifty" behavior is how innocent people get blamed. Nervous, quiet and awkward are traits, not evidence. Ask what anyone actually saw.',
    ),
    Challenge.scenario(
      id: 'mf5',
      level: 11,
      flag: Flag.mythBusting,
      prompt: 'What\'s the best read?',
      context: 'Your friend says she can always tell when people lie, because they touch their nose (the "Pinocchio effect").',
      moves: <String>[
        'She\'s right: lying makes the nose itch.',
        'Lots of people touch their nose all day.',
        'Only if they touch it with their left hand.',
        'She\'s right, but only during the lie itself.',
      ],
      answer: 1,
      insight: 'The "Pinocchio effect" got lots of press but never held up as a reliable sign. Nose touching is a common habit. At most it matters as a change from someone\'s own baseline, together with other signals.',
    ),
    Challenge.scenario(
      id: 'mf6',
      level: 11,
      flag: Flag.othelloError,
      prompt: 'What\'s the best read?',
      context: 'A woman cries in a TV interview while denying she hurt anyone. The comments say: "Fake tears. Guilty."',
      moves: <String>[
        'Her crying proves she\'s innocent.',
        'Her crying proves she\'s faking it.',
        'Crying alone can\'t tell you either way.',
        'An innocent person would be angry, not sad.',
      ],
      answer: 2,
      insight: 'People react to stress in wildly different ways: tears, anger, flat calm. Online crowds judging "fake" emotion have turned on innocent people. Emotional displays are not lie detectors.',
    ),
    Challenge.scenario(
      id: 'mf7',
      level: 11,
      flag: Flag.mythBusting,
      prompt: 'What\'s the best read?',
      context: 'Someone says lie detector (polygraph) tests are always accurate, so if you pass one you must be telling the truth.',
      moves: <String>[
        'True: the machine measures lying directly.',
        'False: it measures stress, not lies.',
        'True, as long as the examiner is trained.',
        'True, which is why courts always use them.',
      ],
      answer: 1,
      insight: 'A polygraph records heart rate, breathing and sweat: arousal, not lying. Nervous honest people can fail, and calm liars can pass. That\'s why most US courts don\'t accept the results as evidence.',
    ),
    Challenge.scenario(
      id: 'mf8',
      level: 11,
      flag: Flag.othelloError,
      prompt: 'What\'s the best read?',
      context: 'You ask a friend "Where were you last night?" and she pauses for a few seconds before answering.',
      moves: <String>[
        'A pause means she\'s making up a story.',
        'Pauses are normal. Listen to what comes next.',
        'She is definitely hiding some kind of secret.',
        'Long pauses only happen when people lie.',
      ],
      answer: 1,
      insight: 'People pause to remember, to decide how much to share, or because the question surprised them. A pause is a cue to listen closely, not a verdict. What she says, and whether it can be checked, matters far more.',
    ),
    Challenge.scenario(
      id: 'mf9',
      level: 11,
      flag: Flag.othelloError,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: '\$50 went missing from the tip jar at work. Alex goes red, talks fast and says: "I didn\'t take it, I swear, you can check my bag." Morgan shrugs: "Wasn\'t me." Your manager says Alex is obviously guilty.',
      moves: <String>[
        'Alex is guilty: blushing and talking fast are classic signs.',
        'Morgan is guilty: calm people make cold, practiced liars.',
        'Neither reaction says much. Check the facts.',
        'They\'re both lying, since they both denied it.',
      ],
      answer: 2,
      insight: 'Alex\'s embarrassment fits an innocent person afraid of being blamed; Morgan\'s calm fits someone who doesn\'t care, or someone practiced. Notice Alex offered something checkable: his bag. Go by evidence, not reactions.',
    ),
    Challenge.scenario(
      id: 'mf10',
      level: 11,
      flag: Flag.mythBusting,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'A best-selling body-language book says crossed arms mean someone is defensive and probably lying.',
      moves: <String>[
        'Crossed arms are a proven sign of lying.',
        'Usually it\'s comfort, cold or habit.',
        'It means lying only when the legs are crossed too.',
        'It shows someone is protecting their heart from you.',
      ],
      answer: 1,
      insight: 'Popular books overstate single gestures. People cross their arms because they\'re cold, comfortable, or it\'s their habit. A gesture means something only as a change from their baseline, clustered with other changes, on a specific topic.',
    ),
    Challenge.scenario(
      id: 'mf11',
      level: 11,
      flag: Flag.mythBusting,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'You\'ve played Two Truths & a Lie a lot and feel like you can always tell. Your record says you\'re right 38% of the time. Chance is 33%.',
      moves: <String>[
        'Trust your gut; the record must be off.',
        'Your confidence is ahead of your accuracy.',
        'You\'re a natural, and 38% is a great score.',
        'Stop playing, because practice never helps.',
      ],
      answer: 1,
      insight: 'Research finds confidence and lie-detection accuracy are barely related. Feeling sure isn\'t evidence. Use your record to find which clues work for you, and drop the ones that don\'t.',
    ),
    Challenge.scenario(
      id: 'mf12',
      level: 11,
      flag: Flag.othelloError,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'After a fender bender, one driver keeps his eyes down while the officer talks. He grew up where looking an adult in the eye is rude. The officer calls him "evasive".',
      moves: <String>[
        'The officer is right: he\'s being evasive.',
        'The officer is misreading a cultural habit.',
        'He\'s lying, because his eyes stay down.',
        'The other driver is lying, since he made eye contact.',
      ],
      answer: 1,
      insight: 'Eye contact rules vary across cultures and families. Judging someone against your own norm instead of their baseline is a classic false alarm, and it falls hardest on people who are already outsiders.',
    ),

    // ── Level 12: Deduction & Cold Reading ──────────────────────────────
    Challenge.scenario(
      id: 'dj1',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      context: 'Your friend says he "did nothing all weekend." He has paint flecks on his sneakers and a sunburned neck.',
      moves: <String>[
        'He spent the whole weekend gaming inside.',
        'He painted something outside.',
        'He went to the beach and swam all day.',
        'He was sick and stayed in bed the whole time.',
      ],
      answer: 1,
      insight: 'Two separate clues point to the same thing: paint on the shoes, sun on the neck. Patrick Jane-style reading means combining small physical clues, not finding one dramatic tell. Then test it: "So what did you paint?"',
    ),
    Challenge.scenario(
      id: 'dj2',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      context: 'Your friend won\'t say what he\'s going to be for Halloween. This week he asked if you have a fake mustache, searched "how to make a bowler hat" and keeps whistling old silent-movie music.',
      moves: <String>[
        'A pirate with a parrot',
        'Charlie Chaplin',
        'A cowboy from a western',
        'A vampire with a cape',
      ],
      answer: 1,
      insight: 'Mustache + bowler hat + silent-movie music = Chaplin. Jane rarely gets one big clue; he lets several small ones narrow the options until only one fits. For your friend\'s real costume, collect what he buys, searches for and talks about.',
    ),
    Challenge.scenario(
      id: 'dj3',
      level: 12,
      flag: Flag.coldReading,
      prompt: 'What\'s the best read?',
      context: 'A "psychic" tells you: "You can be outgoing, but deep down part of you needs time alone." It feels spot-on.',
      moves: <String>[
        'She read your personality from your face.',
        'It fits almost everyone.',
        'She looked you up on social media first.',
        'She guessed it from the clothes you wore.',
      ],
      answer: 1,
      insight: 'This is a Barnum statement: so general it fits nearly everyone, but it feels personal. Cold readers stack these to seem uncanny. Knowing the trick lets you spot it, and use it for fun.',
    ),
    Challenge.scenario(
      id: 'dj4',
      level: 12,
      flag: Flag.coldReading,
      prompt: 'What\'s the best read?',
      context: 'A stage mentalist says: "I\'m getting an older man... a J or G name... someone who passed?" A woman in the crowd gasps: "My grandpa George!"',
      moves: <String>[
        'He really sensed her grandfather.',
        'Vague guesses fit someone in a big crowd.',
        'He has a hidden earpiece feeding him names.',
        'He read her lips before the show started.',
      ],
      answer: 1,
      insight: 'This is "shotgunning": vague guesses to a big crowd until someone connects. With hundreds of people, someone has an older relative who died with a J or G name. The audience remembers the hit and forgets the misses.',
    ),
    Challenge.scenario(
      id: 'dj5',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      context: 'A new classmate has hard calluses on the fingertips of her left hand, a pale tan line on her left wrist, and checks the time on her phone.',
      moves: <String>[
        'She plays guitar.',
        'She works long hours on a farm.',
        'She\'s left-handed and writes a lot.',
        'She plays a lot of video games at night.',
      ],
      answer: 0,
      insight: 'Fingertip calluses on the hand that presses the strings are a guitar tell. The wrist tan line only says she used to wear a watch. Good deduction uses each clue for what it actually supports and ignores the rest.',
    ),
    Challenge.scenario(
      id: 'dj6',
      level: 12,
      flag: Flag.coldReading,
      prompt: 'What\'s the best read?',
      context: 'You tell a friend: "You have a scar on your knee from when you were a kid." He\'s amazed. Why did it work?',
      moves: <String>[
        'Most people have one.',
        'You read it from his body language.',
        'You must have noticed it some other time.',
        'He wanted to be impressed by you.',
      ],
      answer: 0,
      insight: 'A childhood knee scar is a classic high-probability guess: true for most people, but it feels specific. Cold readers lean on these. The skill is knowing which guesses are safe.',
    ),
    Challenge.scenario(
      id: 'dj7',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      context: 'Your friend says he\'s "totally broke." He\'s wearing brand-new shoes, has a fresh haircut and just upgraded his phone.',
      moves: <String>[
        'He\'s lying about being broke.',
        'He spent it all, so now he\'s broke.',
        'He must have stolen the shoes and the phone.',
        'His parents are rich, so he made it up.',
      ],
      answer: 1,
      insight: 'The new stuff explains why he\'s broke now. Jumping to "liar" ignores the simplest explanation that fits every clue. Deduction means picking the story that explains everything, not the most dramatic one.',
    ),
    Challenge.scenario(
      id: 'dj8',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      context: 'Your friend says she went to bed early. This morning she\'s yawning, her phone is at 3%, and she knows the ending of a show that dropped at midnight.',
      moves: <String>[
        'She went to bed early and slept badly.',
        'She stayed up watching the show.',
        'She woke up early to watch the show.',
        'Somebody online told her the ending.',
      ],
      answer: 1,
      insight: 'Each clue alone has an innocent answer, but together they fit one story best: up late, watching on her phone. "Someone spoiled it" explains one clue; "stayed up" explains all three.',
    ),
    Challenge.scenario(
      id: 'dj9',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'Your friend is keeping his Halloween costume a secret. He borrowed his dad\'s old suit, asked for your blond hair spray, practiced a calm smile in the mirror, and said "there\'s no such thing as psychics" in a funny voice.',
      moves: <String>[
        'A businessman from a movie',
        'Patrick Jane from The Mentalist',
        'A blond surfer from an old movie',
        'A TV news anchor on the evening news',
      ],
      answer: 1,
      insight: 'The suit fits lots of costumes; the blond hair narrows it; the calm smile and a line straight from the show settle it. Strong deductions use the most specific clue to choose between options the general clues allow.',
    ),
    Challenge.scenario(
      id: 'dj10',
      level: 12,
      flag: Flag.coldReading,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'A cold reader says: "You\'ve been thinking about a change, maybe work, school or a relationship. Someone close to you doesn\'t fully get you." You nod. What just happened?',
      moves: <String>[
        'He picked up real signals from your face and posture.',
        'Broad guesses; your nod told him he was right.',
        'He researched you online before you sat down.',
        'It was a run of lucky guesses, nothing more.',
      ],
      answer: 1,
      insight: '"Work, school or a relationship" covers almost everything (the rainbow ruse), and your nod tells him which one to dig into next. Cold reading runs on feedback from the person being read.',
    ),
    Challenge.scenario(
      id: 'dj11',
      level: 12,
      flag: Flag.deduction,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'A coworker says she drove in from home. Her umbrella is wet, but it hasn\'t rained in town today. The news says it\'s raining 40 miles north, where her boyfriend lives.',
      moves: <String>[
        'She came from her boyfriend\'s.',
        'She left her umbrella out in a sprinkler.',
        'It rained on her street and nowhere else.',
        'She\'s covering up a secret second job.',
      ],
      answer: 0,
      insight: 'The wet umbrella is easiest to explain by where it was raining. But a deduction isn\'t proof, and it\'s not your business unless it matters. Clues tell you where to ask, not what to accuse.',
    ),
    Challenge.scenario(
      id: 'dj12',
      level: 12,
      flag: Flag.coldReading,
      prompt: 'What\'s the best read?',
      highLoad: true,
      context: 'A friend hides a coin under one of three cups and dares you to find it. You can talk to him first. What\'s the Patrick Jane move?',
      moves: <String>[
        'Name each cup slowly and watch for a reaction.',
        'Ask him to swear which cup it\'s under.',
        'Just guess, because reading people can\'t help here.',
        'Pick whichever cup he looked at the most beforehand.',
      ],
      answer: 0,
      insight: 'Mentalists watch for tiny changes (a held breath, a glance, a pause) as they name each option. It\'s a baseline test: the reaction to the right answer differs from the others. It works best on people who aren\'t trying hard to hide it.',
    ),
    // ── Extra questions so each lesson has its own set ──────────────────
    Challenge.cluster(
      id: 't11',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A friend explains why she was late to your birthday dinner:\n\n"I left at 6:15, I know because my podcast had just started. On Maple there was a fender bender, and a guy in a Lakers hat was directing traffic with his phone flashlight, which was kind of hilarious. I honestly can\'t remember if I texted you or just meant to. I would never be late on purpose. I\'m the most punctual person you know. And you know I\'d never lie to you."',
      indicators: <String>[
        'Ties the time to when her podcast started',
        'Mentions the man in the Lakers hat with a flashlight',
        'Admits she can\'t remember if she texted',
        'Says she would never be late on purpose',
        'Calls herself the most punctual person you know',
        'Adds that she would never lie to you',
      ],
      answers: <int>{0, 1, 2},
      insight: 'Tying a time to something else (the podcast), an odd detail she didn\'t need (the flashlight guy) and admitting a memory gap are hard to invent. "Never on purpose", "most punctual" and "never lie" are credibility pitches: they argue instead of describe.',
    ),
    Challenge.cluster(
      id: 't12',
      level: 6,
      flag: Flag.truthMarkers,
      prompt: 'Tap the 3 signs this account is likely truthful.',
      profile: 'A coworker explains how the office coffee machine broke:\n\n"I put my mug under, hit the large button, and it made this grinding noise, like a blender full of gravel. Then it just stopped. I unplugged it, which maybe was wrong, I don\'t know. Priya came in right after and said, \'Mine did that yesterday too.\' I\'m extremely careful with equipment. Anyone here will tell you I\'d never break something and not say so."',
      indicators: <String>[
        'Describes the noise as a blender full of gravel',
        'Admits unplugging it may have been wrong',
        'Quotes what Priya said about the day before',
        'Says he is extremely careful with equipment',
        'Says anyone will vouch for him',
        'Says he would never hide breaking something',
      ],
      answers: <int>{0, 1, 2},
      insight: 'A vivid sensory detail (the gravel noise), a concession against himself (maybe unplugging was wrong) and a reproduced quote are truth markers. "Extremely careful" and "anyone will tell you" are character claims, not memories.',
    ),
    Challenge.scenario(
      id: 'op1',
      flag: Flag.openQuestion,
      context: 'Your friend Jordan might know who scratched your bike, but he gets defensive easily. You want his honest version of what he saw.',
      moves: <String>[
        'Ask: "Tell me what you saw at the bike rack yesterday."',
        'Ask: "Did you see Marcus scratch my bike?"',
        'Ask: "You saw who did it, right?"',
        'Tell him what you think happened, then ask if he agrees.',
      ],
      answer: 0,
      insight: 'An open question gets his memory, not your theory. "Did you see Marcus…" plants a name and invites a yes or no. Leading questions get agreement, not information.',
    ),
    Challenge.scenario(
      id: 'op2',
      flag: Flag.rapport,
      context: 'You need to ask your little cousin about a broken lamp. She\'s nervous and won\'t look at you.',
      moves: <String>[
        'Sit down at her level and chat about her day first.',
        'Stand over her and tell her she needs to tell the truth right now.',
        'Tell her you already know she did it.',
        'Keep asking the same question until she answers.',
      ],
      answer: 0,
      insight: 'Scared people, especially kids, either shut down or say whatever ends the pressure. Rapport first (calm, at eye level, small talk) gets more true information, and an answer you can believe.',
    ),
    Challenge.statement(
      id: 'ck15',
      flag: Flag.vagueCore,
      level: 9,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'Asked why he missed curfew by an hour:',
      sentences: <String>[
        'I left Ty\'s house at 10:40, right after the game ended.',
        'His street was blocked off, so I had to go around.',
        'Then I kind of ended up somewhere else for a bit.',
        'I pulled into the driveway at 11:55; I remember the clock.',
      ],
      answer: 2,
      insight: 'Times and places on both sides, then "somewhere else for a bit" right where an hour disappears. A detour around a blocked street takes minutes, not an hour. Ask where "somewhere else" was.',
    ),
    Challenge.statement(
      id: 'ck16',
      flag: Flag.vagueCore,
      level: 9,
      highLoad: true,
      prompt: 'Tap the sentence that can\'t be checked where it matters, if there is one.',
      question: 'A coworker explains why the client presentation went out late:',
      sentences: <String>[
        'I finished the slides Tuesday at four and saved them to the team drive.',
        'Dana reviewed them at five and left two comments, which I fixed.',
        'Wednesday morning there were some issues with things on my end.',
        'By the time those were sorted, the client had already called.',
        'I sent it at 11:20 with an apology; it\'s in the email thread.',
      ],
      answer: 2,
      insight: 'Clear, checkable steps (the drive, Dana\'s comments, the email thread) until the moment it went wrong, which becomes "some issues with things". Real problems have names: the laptop died, the file wouldn\'t open. Ask what the issue was.',
    ),
    Challenge.scenario(
      id: 'lw13',
      level: 10,
      flag: Flag.evidenceTiming,
      context: 'Your roommate says he hasn\'t touched your PlayStation. The game history shows a new save last night, in a game you don\'t play.',
      moves: <String>[
        'Show him the save file right away.',
        'Ask about his night first, then the game.',
        'Ask him: "Did you play my PlayStation?"',
        'Change your password and say nothing to him at all.',
      ],
      answer: 1,
      insight: 'Let him describe his evening before you mention the save. If he says "I was out all night", the save contradicts him. Show it first and he\'ll just say a friend used it.',
    ),
    Challenge.scenario(
      id: 'dj13',
      level: 12,
      flag: Flag.coldReading,
      prompt: 'What\'s the best read?',
      context: 'At a party, someone "reads your aura" and says: "You\'re loyal to your friends, but you\'ve been let down by someone you trusted." Everyone says she\'s scary accurate.',
      moves: <String>[
        'She sensed your past through your energy.',
        'That\'s true of nearly everyone.',
        'One of your friends told her about you.',
        'She noticed something sad in your eyes.',
      ],
      answer: 1,
      insight: 'Loyal to friends and let down by someone you trusted: true of nearly everyone, but it feels personal (Barnum statements). A cold reader says them confidently, then watches your face to see which part to build on.',
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
  GameState({AppStore? store, this.missionsOn = true}) : _store = store ?? AppStore.memoryOnly() {
    _restore(_store.load());
    _checkAchievements(silent: true);
    if (_introBadges && achievements.isNotEmpty) {
      _toasts.add('🏅 You already earned ${achievements.length} badges. See the Progress tab!');
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  final AppStore _store;
  bool _dirty = false;

  /// Daily missions can be switched off so tests get exact IP totals.
  final bool missionsOn;

  /// Memory Gym progress, saved with everything else.
  final MemoryState memory = MemoryState();

  /// Daily answers for the progress chart: day → [answered, correct].
  final Map<int, List<int>> dayLog = <int, List<int>>{};

  /// The Consultant: best stars per case.
  final Map<String, int> caseStars = <String, int>{};

  /// Two Truths & a Lie: friend → [rounds, caught].
  final Map<String, List<int>> realLifeStats = <String, List<int>>{};

  void _logDay(bool correct) {
    final d = dayIndex();
    final entry = dayLog.putIfAbsent(d, () => <int>[0, 0]);
    entry[0]++;
    if (correct) entry[1]++;
    dayLog.removeWhere((k, _) => k < d - 90);
  }

  void recordCase(String id, int stars) {
    if (stars > (caseStars[id] ?? 0)) caseStars[id] = stars;
    if (stars > 0) {
      insightPoints += 20 + 10 * stars;
      _bump(MissionKind.consultant);
    }
    _touchStreak();
    _changed();
  }

  /// Real-life rounds by the clue you went on: clue → [rounds, caught].
  final Map<LieClue, List<int>> clueStats = <LieClue, List<int>>{};

  /// Real-life rounds by how sure you were (0 guessing, 1 fairly sure, 2 certain).
  final List<List<int>> confidenceStats = <List<int>>[
    <int>[0, 0],
    <int>[0, 0],
    <int>[0, 0],
  ];

  void recordRealLife(String friend, {required bool correct, LieClue? clue, int? confidence}) {
    final s = realLifeStats.putIfAbsent(friend, () => <int>[0, 0]);
    if (clue != null) {
      final c = clueStats.putIfAbsent(clue, () => <int>[0, 0]);
      c[0]++;
      if (correct) c[1]++;
    }
    if (confidence != null && confidence >= 0 && confidence < 3) {
      confidenceStats[confidence][0]++;
      if (correct) confidenceStats[confidence][1]++;
    }
    s[0]++;
    if (correct) {
      s[1]++;
      insightPoints += 5;
    }
    _touchStreak();
    _changed();
  }

  /// Blackjack table: [hands played, net IP, biggest win].
  final List<int> blackjackStats = <int>[0, 0, 0];

  /// Takes a bet out of the bankroll (call only when affordable).
  void placeBet(int amount) {
    insightPoints = math.max(0, insightPoints - amount);
    _changed();
  }

  /// Pays back [returned] IP for a hand that cost [staked].
  void settleBlackjack({required int staked, required int returned}) {
    insightPoints += returned;
    blackjackStats[0]++;
    blackjackStats[1] += returned - staked;
    blackjackStats[2] = math.max(blackjackStats[2], returned - staked);
    _bump(MissionKind.hands);
    _changed();
  }

  /// Poker: [hands, hands won, net IP, biggest pot won].
  final List<int> pokerStats = <int>[0, 0, 0, 0];
  final Map<String, int> pokerBest = <String, int>{};
  static const int pokerDrillIp = 2;

  /// Settles a finished poker hand: [net] IP won (or lost, if negative).
  void settlePoker({required int net, required bool won, required int pot}) {
    insightPoints = math.max(0, insightPoints + net);
    pokerStats[0]++;
    if (won) {
      pokerStats[1]++;
      pokerStats[3] = math.max(pokerStats[3], pot);
    }
    pokerStats[2] += net;
    _bump(MissionKind.poker);
    _changed();
  }

  /// Returns true for a new best on that drill.
  bool reportPokerDrill(String drill, int score) {
    insightPoints += score * pokerDrillIp;
    final best = score > (pokerBest[drill] ?? -1);
    if (best) pokerBest[drill] = score;
    _touchStreak();
    _changed();
    return best;
  }

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
    _rate(c, correct);
    _trackMistake(c, correct);
    _logDay(correct);
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
    _bump(MissionKind.daily);
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
    _rate(challenge, correct);
    _trackMistake(challenge, correct);
    _logDay(correct);
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
    _bump(MissionKind.lesson);

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
    _bump(MissionKind.memory);
    if (drill == MemoryDrill.cards) _bump(MissionKind.cards);
    final extended = _touchStreak();
    _changed();
    return extended;
  }

  /// Returns true if this round unlocked the next coach stage.
  bool recordCoach({required bool passed, required int stageIndex}) {
    final m = memory;
    var advanced = false;
    if (passed) {
      insightPoints += 2;
      _bump(MissionKind.coach);
    }
    if (stageIndex == m.coachStage) {
      if (passed) {
        m.coachStreak++;
        if (m.coachStreak >= ChunkCoach.passesToAdvance) {
          m.coachStage++;
          m.coachStreak = 0;
          advanced = true;
        }
      } else {
        m.coachStreak = 0;
      }
    }
    if (passed) _touchStreak();
    _changed();
    return advanced;
  }

  void reviewCard(String id, {required bool knew}) {
    memory.review(id, knew: knew, today: dayIndex());
    if (knew) insightPoints += 1;
    _changed();
  }

  // ── Rating, missions, checkups, badges ──────────────────────────────────

  static const int startRating = 800;
  static const int missionReward = 15;
  static const int allMissionsBonus = 40;
  static const int checkupBonus = 30;
  static const int checkupLength = 24;

  /// Reader Rating: an Elo-style lie-reading score. Harder questions move it more.
  int rating = startRating;
  int peakRating = startRating;
  int lastRatingDelta = 0;

  /// Day → rating at the end of that day.
  final Map<int, int> ratingLog = <int, int>{};

  /// Checkup results: [day, correct, total].
  final List<List<int>> checkups = <List<int>>[];

  int missionDay = -1;
  final Map<MissionKind, int> missionProgress = <MissionKind, int>{};
  int missionsAllDoneDays = 0;
  int _runCorrect = 0;

  final Set<String> achievements = <String>{};
  final List<String> _toasts = <String>[];
  bool _introBadges = false;

  ReaderRank get rank => ReaderRank.of(rating);

  bool get hasToasts => _toasts.isNotEmpty;

  List<String> takeToasts() {
    final out = List<String>.of(_toasts);
    _toasts.clear();
    return out;
  }

  /// How hard a question is on the rating scale.
  static int difficultyOf(Challenge c) => 700 + 110 * c.level + (c.highLoad ? 160 : 0);

  void _rate(Challenge c, bool correct) {
    final expected = 1 / (1 + math.pow(10, (difficultyOf(c) - rating) / 400));
    final k = totalAnswered <= 30 ? 40 : 24;
    final before = rating;
    final oldPeakRank = ReaderRank.of(peakRating);
    rating = (rating + k * ((correct ? 1 : 0) - expected)).round().clamp(400, 3000);
    lastRatingDelta = rating - before;
    if (rating > peakRating) {
      peakRating = rating;
      final r = ReaderRank.of(rating);
      if (r.index > oldPeakRank.index) _toasts.add('${r.emoji} Rank up: ${r.title}!');
    }
    final d = dayIndex();
    ratingLog[d] = rating;
    ratingLog.removeWhere((day, _) => day < d - 120);

    _bump(MissionKind.answer);
    if (correct) {
      _runCorrect++;
      _bump(MissionKind.correct);
      _missionAtLeast(MissionKind.inARow, _runCorrect);
    } else {
      _runCorrect = 0;
    }
  }

  /// Rating at the end of [day] (the last known value on or before it).
  int ratingOn(int day) {
    int? bestDay;
    for (final d in ratingLog.keys) {
      if (d <= day && (bestDay == null || d > bestDay)) bestDay = d;
    }
    if (bestDay != null) return ratingLog[bestDay]!;
    if (ratingLog.isEmpty) return rating;
    return ratingLog[ratingLog.keys.reduce(math.min)]!;
  }

  List<MissionKind> get todaysMissions => MissionKind.forDay(dayIndex());

  int missionCount(MissionKind k) => missionDay == dayIndex() ? (missionProgress[k] ?? 0) : 0;

  bool missionDone(MissionKind k) => missionCount(k) >= k.target;

  void bumpMission(MissionKind k) {
    _bump(k);
    _changed();
  }

  void _bump(MissionKind k) => _missionAtLeast(k, missionCount(k) + 1);

  void _missionAtLeast(MissionKind k, int value) {
    final today = dayIndex();
    if (missionDay != today) {
      missionDay = today;
      missionProgress.clear();
    }
    final missions = MissionKind.forDay(today);
    if (!missionsOn || !missions.contains(k)) return;
    final before = missionProgress[k] ?? 0;
    if (value <= before) return;
    missionProgress[k] = value;
    if (before < k.target && value >= k.target) {
      insightPoints += missionReward;
      _toasts.add('${k.emoji} Mission done: ${k.title}  +$missionReward IP');
      if (missions.every((m) => (missionProgress[m] ?? 0) >= m.target)) {
        insightPoints += allMissionsBonus;
        missionsAllDoneDays++;
        _toasts.add('🏆 All 3 missions done!  +$allMissionsBonus IP');
      }
    }
  }

  void recordCheckup(int correct, int total) {
    checkups.add(<int>[dayIndex(), correct, total]);
    if (checkups.length > 60) checkups.removeAt(0);
    insightPoints += checkupBonus;
    _touchStreak();
    _changed();
  }

  int? get firstCheckupPct => checkups.isEmpty ? null : (100 * checkups.first[1] / checkups.first[2]).round();

  int? get bestCheckupPct => checkups.isEmpty
      ? null
      : checkups.map((c) => (100 * c[1] / c[2]).round()).reduce(math.max);

  /// The skills you miss most (at least 3 tries, under 85% right), worst first.
  List<Flag> weakFlags({int count = 3}) {
    double acc(Flag f) => (flagAttempts[f]! - flagMisses[f]!) / flagAttempts[f]!;
    final list = Flag.values.where((f) => flagAttempts[f]! >= 3 && acc(f) < 0.85).toList()
      ..sort((a, b) {
        final byAcc = acc(a).compareTo(acc(b));
        return byAcc != 0 ? byAcc : flagMisses[b]!.compareTo(flagMisses[a]!);
      });
    return list.take(count).toList();
  }

  void _checkAchievements({bool silent = false}) {
    for (final a in Achievement.all) {
      if (achievements.contains(a.id)) continue;
      if (!a.test(this)) continue;
      achievements.add(a.id);
      if (!silent) _toasts.add('${a.emoji} Badge unlocked: ${a.title}');
    }
  }

  // ── Saving ──────────────────────────────────────────────────────────────

  void _changed() {
    _dirty = true;
    _checkAchievements();
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
        'dayLog': <String, List<int>>{for (final e in dayLog.entries) '${e.key}': e.value},
        'caseStars': caseStars,
        'realLife': realLifeStats,
        'clues': <String, List<int>>{for (final e in clueStats.entries) e.key.name: e.value},
        'confidence': confidenceStats,
        'blackjack': blackjackStats,
        'rating': rating,
        'peakRating': peakRating,
        'ratingLog': <String, int>{for (final e in ratingLog.entries) '${e.key}': e.value},
        'checkups': checkups,
        'missionDay': missionDay,
        'missions': <String, int>{for (final e in missionProgress.entries) e.key.name: e.value},
        'missionsAll': missionsAllDoneDays,
        'achievements': achievements.toList(),
        'poker': pokerStats,
        'pokerBest': pokerBest,
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
      final log = data['dayLog'];
      if (log is Map) {
        log.forEach((Object? k, Object? v) {
          final day = int.tryParse('$k');
          if (day != null && v is List && v.length == 2 && v[0] is int && v[1] is int) {
            dayLog[day] = <int>[v[0] as int, v[1] as int];
          }
        });
      }
      _readCounts(data['caseStars'], caseStars, <String, String>{for (final c in ConsultantCases.all) c.id: c.id});
      final bj = data['blackjack'];
      if (bj is List && bj.length == 3 && bj.every((v) => v is int)) {
        for (var i = 0; i < 3; i++) {
          blackjackStats[i] = bj[i] as int;
        }
      }
      final savedRating = data['rating'];
      if (savedRating is int) {
        rating = savedRating.clamp(400, 3000);
      } else if (totalAnswered > 0) {
        // Older saves: start from how far you've come instead of from zero.
        final acc = totalAnswered >= 20 ? lifetimeAccuracy : 0.6;
        rating = (startRating + 70 * (highestUnlockedLevel - 1) + (acc - 0.6) * 400).round().clamp(600, 1300);
      }
      peakRating = math.max(rating, _readInt(data['peakRating'], rating));
      final rLog = data['ratingLog'];
      if (rLog is Map) {
        rLog.forEach((Object? k, Object? v) {
          final day = int.tryParse('$k');
          if (day != null && v is int) ratingLog[day] = v;
        });
      }
      if (totalAnswered > 0 && ratingLog.isEmpty) ratingLog[dayIndex()] = rating;
      final cks = data['checkups'];
      if (cks is List) {
        for (final c in cks) {
          if (c is List && c.length == 3 && c.every((v) => v is int) && (c[2] as int) > 0) {
            checkups.add(<int>[c[0] as int, c[1] as int, c[2] as int]);
          }
        }
      }
      missionDay = _readInt(data['missionDay'], -1);
      _readCounts(data['missions'], missionProgress, MissionKind.values.asNameMap());
      missionsAllDoneDays = _readInt(data['missionsAll'], 0);
      final ach = data['achievements'];
      final hadBadges = ach is List;
      if (ach is List) achievements.addAll(ach.whereType<String>());
      _introBadges = !hadBadges && totalAnswered > 0;
      final pk = data['poker'];
      if (pk is List && pk.length == 4 && pk.every((v) => v is int)) {
        for (var i = 0; i < 4; i++) {
          pokerStats[i] = pk[i] as int;
        }
      }
      _readCounts(data['pokerBest'], pokerBest, <String, String>{for (final d in PokerDrill.values) d.name: d.name});
      final clues = data['clues'];
      if (clues is Map) {
        final byName = LieClue.values.asNameMap();
        clues.forEach((Object? k, Object? v) {
          final clue = byName[k];
          if (clue != null && v is List && v.length == 2 && v[0] is int && v[1] is int) {
            clueStats[clue] = <int>[v[0] as int, v[1] as int];
          }
        });
      }
      final conf = data['confidence'];
      if (conf is List && conf.length == 3) {
        for (var i = 0; i < 3; i++) {
          final v = conf[i];
          if (v is List && v.length == 2 && v[0] is int && v[1] is int) {
            confidenceStats[i] = <int>[v[0] as int, v[1] as int];
          }
        }
      }
      final real = data['realLife'];
      if (real is Map) {
        real.forEach((Object? k, Object? v) {
          if (k is String && v is List && v.length == 2 && v[0] is int && v[1] is int) {
            realLifeStats[k] = <int>[v[0] as int, v[1] as int];
          }
        });
      }
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
//  RANKS, DAILY MISSIONS & BADGES
// ════════════════════════════════════════════════════════════════════════════

enum ReaderRank {
  rookie('Rookie', '🐣', 0, 'You\'re learning what to look for.'),
  observer('Observer', '👀', 900, 'You notice changes most people miss.'),
  analyst('Analyst', '🔍', 1000, 'You read the baseline before judging.'),
  investigator('Investigator', '🕵️', 1100, 'Clusters and statements don\'t fool you easily.'),
  profiler('Profiler', '🧠', 1250, 'You read people across every skill.'),
  interrogator('Interrogator', '🎯', 1400, 'You hold up on the hardest questions.'),
  mentalist('Mentalist', '🎩', 1550, 'Patrick Jane would nod.'),
  human('Human Lie Detector', '👑', 1700, 'Top of the scale.');

  const ReaderRank(this.title, this.emoji, this.minRating, this.blurb);
  final String title;
  final String emoji;
  final int minRating;
  final String blurb;

  static ReaderRank of(int rating) => values.lastWhere((r) => rating >= r.minRating);

  ReaderRank? get next => index + 1 < values.length ? values[index + 1] : null;
}

enum MissionKind {
  answer('Answer 15 lie-reading questions', '🎯', 15, 0),
  correct('Get 12 lie-reading answers right', '✅', 12, 0),
  inARow('Get 6 right in a row', '🔥', 6, 0),
  memory('Finish 2 memory drills', '🧠', 2, 1),
  cards('Count down a deck in Card Counting', '🃏', 1, 1),
  coach('Pass 3 Chunking Coach rounds', '🧩', 3, 1),
  lesson('Finish a Cold Reading lesson', '📘', 1, 2),
  daily('Solve the Daily Case File', '📁', 1, 2),
  consultant('Get a confession in The Consultant', '🕵️', 1, 2),
  hands('Play 5 blackjack hands', '♠️', 5, 2),
  poker('Play 5 poker hands', '♣️', 5, 2),
  weak('Finish a Weak Spot Training run', '🩹', 1, 2);

  const MissionKind(this.title, this.emoji, this.target, this.group);
  final String title;
  final String emoji;
  final int target;

  /// 0 = lie reading, 1 = memory, 2 = anything else. One of each per day.
  final int group;

  /// Today's three missions. Same for the whole day.
  static List<MissionKind> forDay(int day) {
    final rng = math.Random(day * 104729 + 11);
    final out = <MissionKind>[];
    for (var g = 0; g < 3; g++) {
      final pool = values.where((m) => m.group == g).toList();
      out.add(pool[rng.nextInt(pool.length)]);
    }
    return out;
  }
}

class Achievement {
  const Achievement(this.id, this.emoji, this.title, this.description, this.test);
  final String id;
  final String emoji;
  final String title;
  final String description;
  final bool Function(GameState g) test;

  static int _best(GameState g, MemoryDrill d) => g.memory.best[d] ?? 0;

  static final List<Achievement> all = <Achievement>[
    Achievement('first', '🌱', 'First Steps', 'Answer your first question.', (g) => g.totalAnswered >= 1),
    Achievement('hundred', '💯', 'Century', 'Answer 100 questions.', (g) => g.totalAnswered >= 100),
    Achievement('fivehundred', '📚', 'Case Hardened', 'Answer 500 questions.', (g) => g.totalAnswered >= 500),
    Achievement('thousand', '🗄️', 'Thousand Files', 'Answer 1,000 questions.', (g) => g.totalAnswered >= 1000),
    Achievement('sharp', '🎯', 'Sharp Eye', 'Keep 75%+ accuracy over 100+ answers.',
        (g) => g.totalAnswered >= 100 && g.lifetimeAccuracy >= 0.75),
    Achievement('level3', '🧭', 'Getting Serious', 'Reach Level 3.', (g) => g.highestUnlockedLevel >= 3),
    Achievement('level5', '🗝️', 'Deep In', 'Reach Level 5.', (g) => g.highestUnlockedLevel >= 5),
    Achievement('level8', '🏔️', 'Veteran', 'Reach Level 8.', (g) => g.highestUnlockedLevel >= 8),
    Achievement('level10', '🧗', 'Past the Old Finish', 'Reach Level 10.', (g) => g.highestUnlockedLevel >= 10),
    Achievement('level12', '🎩', 'Final Level', 'Reach Level 12.', (g) => g.highestUnlockedLevel >= 12),
    Achievement('graduate', '🎓', 'Graduate', 'Pass the final exam.', (g) => g.completedNodeIds.contains('exam')),
    Achievement('observer', '👀', 'Observer', 'Reach a 900 Reader Rating.', (g) => g.peakRating >= 900),
    Achievement('investigator', '🕵️', 'Investigator', 'Reach a 1100 Reader Rating.', (g) => g.peakRating >= 1100),
    Achievement('profiler', '🧠', 'Profiler', 'Reach a 1250 Reader Rating.', (g) => g.peakRating >= 1250),
    Achievement('mentalist', '🎩', 'Mentalist', 'Reach a 1550 Reader Rating.', (g) => g.peakRating >= 1550),
    Achievement('streak3', '🔥', 'On Fire', 'Keep a 3-day streak.', (g) => g.streak >= 3),
    Achievement('streak7', '⚡', 'One Full Week', 'Keep a 7-day streak.', (g) => g.streak >= 7),
    Achievement('streak30', '🌋', 'Unstoppable', 'Keep a 30-day streak.', (g) => g.streak >= 30),
    Achievement('missions5', '📅', 'Dedicated', 'Finish all 3 daily missions on 5 days.', (g) => g.missionsAllDoneDays >= 5),
    Achievement('checkup', '🩺', 'Checked In', 'Take your first Checkup.', (g) => g.checkups.isNotEmpty),
    Achievement('checkup80', '🏅', 'Top Marks', 'Score 80% or more on a Checkup.', (g) => (g.bestCheckupPct ?? 0) >= 80),
    Achievement('improved', '📈', 'Proof of Progress', 'Beat your first Checkup score by 15 points.',
        (g) => g.checkups.length >= 2 && g.bestCheckupPct! - g.firstCheckupPct! >= 15),
    Achievement('lab10', '🧪', 'Lab Rat', 'Hit a 10 streak in Baseline Lab.', (g) => (g.practiceBest['baselineLab'] ?? 0) >= 10),
    Achievement('speed15', '⏱️', 'Quick Read', 'Get 15 right in a Speed Round.', (g) => (g.practiceBest['speed'] ?? 0) >= 15),
    Achievement('survive20', '🛡️', 'Survivor', 'Survive 20 questions in Survival.', (g) => (g.practiceBest['survival'] ?? 0) >= 20),
    Achievement('digits10', '🔢', 'Phone Book', 'Remember 10 digits in Number Span.', (g) => _best(g, MemoryDrill.digits) >= 10),
    Achievement('digits15', '🧮', 'Human Calculator', 'Remember 15 digits in Number Span.', (g) => _best(g, MemoryDrill.digits) >= 15),
    Achievement('words12', '🔗', 'Storyteller', 'Remember 12 words in Story Chain.', (g) => _best(g, MemoryDrill.words) >= 12),
    Achievement('palace10', '🏛️', 'Architect', 'Place 10 items in a Memory Palace.', (g) => _best(g, MemoryDrill.palace) >= 10),
    Achievement('faces7', '🤝', 'Never Forget a Face', 'Remember 7 names in Names & Faces.', (g) => _best(g, MemoryDrill.faces) >= 7),
    Achievement('coach', '🧩', 'Chunk Master', 'Graduate from the Chunking Coach.',
        (g) => g.memory.coachStage >= ChunkCoach.stages.length),
    Achievement('cards20', '🗂️', 'Well Read', 'Learn 20 study cards in Spaced Review.', (g) => g.memory.learnedCards() >= 20),
    Achievement('count5', '🃏', 'Counter', 'Reach Card Counting level 5.', (g) => _best(g, MemoryDrill.cards) >= 5),
    Achievement('count10', '🎰', 'Advantage Player', 'Reach Card Counting level 10.', (g) => _best(g, MemoryDrill.cards) >= 10),
    Achievement('hands50', '♠️', 'Regular', 'Play 50 blackjack hands.', (g) => g.blackjackStats[0] >= 50),
    Achievement('poker25', '♣️', 'Card Shark', 'Play 25 poker hands.', (g) => g.pokerStats[0] >= 25),
    Achievement('pokerDrills', '📐', 'Poker Scholar', 'Score 8/10 or better on every Poker School drill.',
        (g) => PokerDrill.values.every((d) => (g.pokerBest[d.name] ?? 0) >= 8)),
    Achievement('bigwin', '💰', 'High Roller', 'Win 300+ IP in one blackjack hand.', (g) => g.blackjackStats[2] >= 300),
    Achievement('case1', '🔎', 'First Confession', 'Solve a Consultant case.', (g) => g.caseStars.values.any((s) => s > 0)),
    Achievement('allcases', '⭐', 'Patrick Would Be Proud', 'Get 3 stars on every Consultant case.',
        (g) => ConsultantCases.all.every((c) => (g.caseStars[c.id] ?? 0) >= 3)),
    Achievement('reallife10', '🎭', 'Party Trick', 'Play 10 rounds of Two Truths & a Lie.',
        (g) => g.realLifeStats.values.fold<int>(0, (a, s) => a + s[0]) >= 10),
  ];
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

    // Lessons only swap within their own questions, so they stay distinct.
    final source = node.isReview ? Curriculum.challenges : (Curriculum.lessonPools[node.id] ?? const <Challenge>[]);
    final candidates =
        source.where((c) => c.highLoad && c.level == item.challenge.level && !usedIds.contains(c.id)).toList();
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
      // Standard questions first, then this lesson's harder ones if it needs more.
      final own = Curriculum.lessonPools[node.id] ?? const <Challenge>[];
      final normal = own.where((c) => !c.highLoad).toList()..shuffle(rng);
      final hard = own.where((c) => c.highLoad).toList()..shuffle(rng);
      final picks = <Challenge>[...normal, ...hard].take(node.questLength).toList()..shuffle(rng);
      return QuestSession(
        nodeIndex: nodeIndex,
        items: picks.map((c) => QuestItem(BaselineGenerator.live(c, rng).shuffled(rng))).toList(),
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
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final List<String> _toastQueue = <String>[];
  bool _showingToast = false;

  @override
  void initState() {
    super.initState();
    _game.addListener(_drainToasts);
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainToasts());
  }

  @override
  void dispose() {
    _game.removeListener(_drainToasts);
    _game.dispose();
    super.dispose();
  }

  void _drainToasts() {
    if (_game.hasToasts) _toastQueue.addAll(_game.takeToasts());
    _showNextToast();
  }

  void _showNextToast() {
    if (_showingToast || _toastQueue.isEmpty || !mounted) return;
    final overlay = _navKey.currentState?.overlay;
    if (overlay == null) return;
    _showingToast = true;
    final text = _toastQueue.removeAt(0);
    final entry = OverlayEntry(builder: (_) => _ToastBanner(text: text));
    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 2800), () {
      if (entry.mounted) entry.remove();
      _showingToast = false;
      _showNextToast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Reading',
      navigatorKey: _navKey,
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

/// Four tabs: the Cold Reading tree, Practice, the Memory Gym and Progress.
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
          ProgressScreen(game: widget.game),
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
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Progress',
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
              ProgressChart(game: game),
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
                ratingDelta: game.lastRatingDelta,
                rating: game.rating,
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
    this.ratingDelta,
    this.rating,
  });

  final int? ratingDelta;
  final int? rating;
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${challenge.isClean ? '✅' : '🚩'} ${challenge.flag.label}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (ratingDelta != null && rating != null)
                  Text(
                    '${ratingDelta! >= 0 ? '▲ +' : '▼ '}$ratingDelta  ·  $rating',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                  ),
              ],
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
  cards('Card Counting', 'Hi-Lo running count', Icons.casino, Palette.red, 1, 1, 10, ''),
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

  /// Chunking Coach: current stage (== stages.length once graduated) and streak.
  int coachStage = 0;
  int coachStreak = 0;

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
        'coachStage': coachStage,
        'coachStreak': coachStreak,
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
    coachStage = _readInt(data['coachStage'], 0).clamp(0, ChunkCoach.stages.length);
    coachStreak = _readInt(data['coachStreak'], 0).clamp(0, ChunkCoach.passesToAdvance);
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
    MemoryDrill.cards: <LessonPage>[
      LessonPage('Blackjack in 30 seconds',
          'Get closer to 21 than the dealer without going over. Number cards count as their number, J, Q and K count as 10, '
          'and an ace is 1 or 11. "Hit" takes another card, "stand" stops. The dealer must keep hitting until 17 or more.'),
      LessonPage('Starter strategy',
          'A simplified version of the math-correct moves: always stand on 17 or more, always hit on 11 or less. '
          'With 12 to 16, stand if the dealer\'s face-up card is 2–6, and hit if it\'s 7 or higher.'),
      LessonPage('Why counting works',
          'The cards still in the deck change your odds. When lots of 10s and aces are left, blackjacks and dealer busts '
          'happen more, which helps the player. Counting tells you when the deck is "hot".'),
      LessonPage('Hi-Lo values',
          'Every card gets one of three values. You never memorize the cards themselves, just one running number.',
          '2 3 4 5 6  →  +1\n7 8 9  →  0\n10 J Q K A  →  −1'),
      LessonPage('The running count',
          'Start at 0 after a shuffle and add each card\'s value as it\'s dealt. Positive means the deck is good for you: bet more. '
          'Negative means bet the minimum. Cancel pairs to go faster: a 5 and a king together are 0.',
          '5, K, 2, 9, 4  →  +1, 0, +1, +1, +2'),
      LessonPage('Playing with friends',
          'Counting only helps if the deck is NOT reshuffled every hand. Shuffle two decks together, deal from the pile, and '
          'reshuffle only when about three quarters are used. Play for chips or snacks, not real money.'),
      LessonPage('How the drill works',
          'Cards flash by one at a time. Keep the running count in your head, then enter it (± for negative). The first '
          'two levels show each card\'s value; after that it\'s all you, with more cards and faster deals.'),
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
    StudyCard('m_hilo', 'What are the Hi-Lo card counting values?',
        '2–6 = +1, 7–9 = 0, and 10s, face cards and aces = −1. Keep one running total, starting at 0.'),
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
    MemoryDrill.cards => CardCountScreen(game: game),
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
    MemoryDrill.cards,
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
            _CoachCard(game: game),
            const SizedBox(height: 14),
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
            const SizedBox(height: 4),
            _BigModeCard(
              emoji: '🃏',
              title: 'Blackjack Table',
              subtitle: 'Play real blackjack with your IP. Use your counting. Play money only.',
              status: game.blackjackStats[0] == 0
                  ? 'No hands yet · ${game.insightPoints} IP to play with'
                  : '${game.blackjackStats[0]} hands · net ${game.blackjackStats[1] >= 0 ? '+' : ''}${game.blackjackStats[1]} IP',
              color: Palette.red,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => BlackjackScreen(game: game)),
              ),
            ),
            _BigModeCard(
              emoji: '♣️',
              title: 'Poker School',
              subtitle: 'Learn Texas Hold\'em: lessons, drills, and a table where you read your opponent\'s tells.',
              status: game.pokerStats[0] == 0
                  ? 'Start with lesson 1'
                  : '${game.pokerStats[0]} hands · net ${game.pokerStats[2] >= 0 ? '+' : ''}${game.pokerStats[2]} IP',
              color: Palette.indigo,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PokerSchoolScreen(game: game)),
              ),
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
            tip: 'Chunk it: split the number into groups of 2–3 and give each group a meaning or a rhythm. '
                'New to this? The Chunking Coach on the Memory tab teaches it step by step.',
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
    const keys = <String>['7', '8', '9', '4', '5', '6', '1', '2', '3', 'del', '0', 'ok'];
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
  daily('Daily Case File', 'Five new cases every day. Bonus IP the first time.', Icons.folder_special, Palette.gold),
  weakSpots('Weak Spot Training', 'Ten questions aimed at the skills you miss most.', Icons.healing, Palette.teal),
  checkup('Checkup', '24 questions, two from every level. No feedback until the end. Your true score.', Icons.monitor_heart,
      Palette.indigo);

  const PracticeMode(this.title, this.subtitle, this.icon, this.color);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}

/// The Checkup: two questions from every level (one normal, one hard) plus
/// extra hard ones if needed. Same shape every time, so scores compare fairly.
List<Challenge> checkupSet(math.Random rng) {
  final maxLevel = Curriculum.challenges.map((c) => c.level).reduce(math.max);
  final picks = <Challenge>[];
  for (var level = 1; level <= maxLevel; level++) {
    for (final hard in <bool>[false, true]) {
      var pool = Curriculum.challenges.where((c) => c.level == level && c.highLoad == hard).toList();
      if (pool.isEmpty) pool = Curriculum.challenges.where((c) => c.level == level && !picks.contains(c)).toList();
      if (pool.isEmpty) continue;
      picks.add(pool[rng.nextInt(pool.length)]);
    }
  }
  final extra = Curriculum.challenges.where((c) => c.level >= 2 && c.highLoad && !picks.contains(c)).toList()
    ..shuffle(rng);
  picks.addAll(extra.take(math.max(0, GameState.checkupLength - picks.length)));
  picks.sort((a, b) => a.level.compareTo(b.level));
  return picks.map((c) => BaselineGenerator.live(c, rng).shuffled(rng)).toList();
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
      PracticeMode.weakSpots => game.weakFlags().isEmpty
          ? 'Mixed set until your weak spots show up'
          : 'Focus: ${game.weakFlags().map((f) => f.label).join(', ')}',
      PracticeMode.checkup => game.checkups.isEmpty
          ? 'Not taken yet'
          : 'Last: ${(100 * game.checkups.last[1] / game.checkups.last[2]).round()}%',
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
            _BigModeCard(
              emoji: '🕵️',
              title: 'The Consultant',
              subtitle: 'Interview the suspects, switch between them, and get the guilty one to confess.',
              status: '${game.caseStars.values.where((s) => s > 0).length}/${ConsultantCases.all.length} cases solved',
              color: Palette.indigo,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ConsultantHubScreen(game: game)),
              ),
            ),
            _BigModeCard(
              emoji: '🎭',
              title: 'Two Truths & a Lie',
              subtitle: 'Play with friends in real life. The app tracks how often you catch the lie.',
              status: game.realLifeStats.isEmpty
                  ? 'No rounds yet'
                  : '${game.realLifeStats.values.fold<int>(0, (a, s) => a + s[1])}/'
                      '${game.realLifeStats.values.fold<int>(0, (a, s) => a + s[0])} caught',
              color: Palette.pink,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => RealLifeScreen(game: game)),
              ),
            ),
            _BigModeCard(
              emoji: '🔬',
              title: 'What Actually Works',
              subtitle: 'What the research says about catching real lies, and what\'s a myth.',
              status: '8 short cards · 2 min read',
              color: Palette.teal,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LieScienceScreen()),
              ),
            ),
            Container(
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
                  const Text('YOUR PROGRESS',
                      style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  ProgressChart(game: game),
                ],
              ),
            ),
            const Text('QUICK MODES',
                style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            for (final mode in PracticeMode.values.where((m) => m != PracticeMode.checkup))
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

class _BigModeCard extends StatelessWidget {
  const _BigModeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final String status;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withAlpha(160), width: 1.5),
            ),
            child: Row(
              children: <Widget>[
                Text(emoji, style: const TextStyle(fontSize: 38)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(color: Palette.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Palette.textPrimary, fontSize: 13, height: 1.3)),
                      const SizedBox(height: 4),
                      Text(status, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Palette.textMuted),
              ],
            ),
          ),
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
  int _ratingBefore = 0;
  final Map<ChallengeType, List<int>> _byType = <ChallengeType, List<int>>{};
  final List<Challenge> _missed = <Challenge>[];

  GameState get game => widget.game;
  PracticeMode get mode => widget.mode;

  bool get _fixedMode => switch (mode) {
        PracticeMode.mistakes || PracticeMode.daily || PracticeMode.weakSpots || PracticeMode.checkup => true,
        _ => false,
      };

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
    _ratingBefore = game.rating;
    _byType.clear();
    _missed.clear();
    _fixedIndex = 0;
    _fixed = switch (mode) {
      PracticeMode.mistakes => (game.mistakes
          .map((id) => Curriculum.byId[id])
          .whereType<Challenge>()
          .map((c) => c.shuffled(_rng))
          .toList()
        ..shuffle(_rng)),
      PracticeMode.daily => _dailySet(),
      PracticeMode.weakSpots => _weakSet(),
      PracticeMode.checkup => checkupSet(_rng),
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
    if (_fixedMode && _fixed.isEmpty) {
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

  List<Challenge> _weakSet() {
    final flags = game.weakFlags();
    final maxLevel = game.highestUnlockedLevel;
    final unlocked = Curriculum.challenges.where((c) => c.level <= maxLevel).toList()..shuffle(_rng);
    final picks = unlocked.where((c) => flags.contains(c.flag)).take(10).toList();
    picks.addAll(unlocked.where((c) => !picks.contains(c)).take(10 - picks.length));
    picks.shuffle(_rng);
    return picks.map((c) => BaselineGenerator.live(c, _rng).shuffled(_rng)).toList();
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
        PracticeMode.mistakes || PracticeMode.daily || PracticeMode.weakSpots || PracticeMode.checkup =>
          _fixed[_fixedIndex],
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
    final tally = _byType.putIfAbsent(_current.type, () => <int>[0, 0]);
    tally[0]++;
    if (correct) tally[1]++;
    if (!correct) _missed.add(_current);
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
    if (mode == PracticeMode.checkup) {
      _advance();
      return;
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
    final fixedMode = _fixedMode;
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
    } else if (mode == PracticeMode.checkup && _answered == _fixed.length) {
      game.recordCheckup(_score, _fixed.length);
    } else {
      if (mode == PracticeMode.weakSpots && _answered == _fixed.length) game.bumpMission(MissionKind.weak);
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
      PracticeMode.weakSpots || PracticeMode.checkup => '${math.min(_fixedIndex + 1, _fixed.length)}/${_fixed.length}',
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
                      : (mode == PracticeMode.checkup ? 'Lock in answer' : 'Check answer'),
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
                ratingDelta: game.lastRatingDelta,
                rating: game.rating,
                onContinue: _continue,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckupOver() {
    final total = _fixed.length;
    final complete = _answered == total;
    final pct = _answered == 0 ? 0 : (100 * _score / _answered).round();
    final history = game.checkups;
    final previous = complete && history.length >= 2 ? history[history.length - 2] : null;
    final prevPct = previous == null ? null : (100 * previous[1] / previous[2]).round();
    final first = game.firstCheckupPct;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: <Widget>[
        const Center(child: Text('🩺', style: TextStyle(fontSize: 64))),
        const SizedBox(height: 8),
        Text(
          complete ? 'Checkup complete' : 'Checkup stopped early',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          '$_score / $_answered right · $pct%',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: pct >= 80 ? Palette.green : (pct >= 60 ? Palette.gold : Palette.orange),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (!complete)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Only finished checkups are saved to your history.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.textMuted),
            ),
          ),
        const SizedBox(height: 16),
        if (complete)
          Row(
            children: <Widget>[
              Expanded(child: _MiniStat(label: 'First ever', value: first == null ? '–' : '$first%')),
              const SizedBox(width: 8),
              Expanded(child: _MiniStat(label: 'Last time', value: prevPct == null ? '–' : '$prevPct%')),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Change',
                  value: first == null || history.length < 2 ? 'new' : '${pct - first >= 0 ? '+' : ''}${pct - first}',
                  color: first != null && pct >= first ? Palette.green : Palette.orange,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.border, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('BY SKILL',
                  style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              for (final t in ChallengeType.values)
                if (_byType[t] != null) _BreakdownLine(label: t.label, value: '${_byType[t]![1]}/${_byType[t]![0]}'),
              _BreakdownLine(
                label: 'Reader Rating',
                value: '${game.rating - _ratingBefore >= 0 ? '+' : ''}${game.rating - _ratingBefore} → ${game.rating}',
              ),
              if (complete) const _BreakdownLine(label: 'Checkup bonus', value: '+${GameState.checkupBonus} IP'),
            ],
          ),
        ),
        if (_missed.isNotEmpty) ...<Widget>[
          const SizedBox(height: 18),
          Text('WHAT YOU MISSED (${_missed.length})',
              style: const TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          for (final c in _missed)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${c.isClean ? '✅' : '🚩'} ${c.flag.label} · Level ${c.level}',
                      style: const TextStyle(color: Palette.indigo, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  const SizedBox(height: 4),
                  Text(c.prompt, style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Answer: ${c.correctAnswerText}',
                      style: const TextStyle(color: Palette.green, fontWeight: FontWeight.w700, height: 1.3)),
                  const SizedBox(height: 4),
                  Text(c.insight, style: const TextStyle(color: Palette.textMuted, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        ChunkyButton(label: 'Done', color: Palette.indigo, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _buildOver() {
    if (mode == PracticeMode.checkup) return _buildCheckupOver();
    final best = game.practiceBest[mode.name] ?? 0;
    final headline = switch (mode) {
      PracticeMode.baselineLab => 'Best streak this run: $_bestStreak',
      PracticeMode.speed => '$_score correct in $speedSeconds seconds',
      PracticeMode.survival => 'You survived $_score questions',
      PracticeMode.mistakes => '$_score of $_answered fixed',
      PracticeMode.daily => '$_score of ${_fixed.length} cases solved',
      PracticeMode.weakSpots => '$_score of $_answered right on your weak spots',
      PracticeMode.checkup => '$_score of $_answered right',
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
                _BreakdownLine(
                  label: 'Reader Rating',
                  value: '${game.rating - _ratingBefore >= 0 ? '+' : ''}${game.rating - _ratingBefore} → ${game.rating}',
                ),
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
//  MEMORY COACH: guided chunking with support that fades stage by stage
// ════════════════════════════════════════════════════════════════════════════

class CoachStage {
  const CoachStage({
    required this.title,
    required this.goal,
    required this.length,
    required this.studySeconds,
    required this.meaningfulBias,
    this.preChunked = false,
    this.showSpoken = false,
    this.showHints = false,
    this.userSplit = false,
    this.pickMeaning = false,
  });

  final String title;
  final String goal;
  final int length;
  final int studySeconds;

  /// Chance that each hidden chunk is a "meaningful" number (a year, a time…).
  final double meaningfulBias;
  final bool preChunked;
  final bool showSpoken;
  final bool showHints;
  final bool userSplit;
  final bool pickMeaning;
}

class ChunkCoach {
  ChunkCoach._();

  static const int passesToAdvance = 3;

  static const List<CoachStage> stages = <CoachStage>[
    CoachStage(
      title: 'See the chunks',
      goal: 'The number comes already split. Read each chunk as ONE word, like "forty-one", not "four, one".',
      length: 6,
      studySeconds: 7,
      meaningfulBias: 0.3,
      preChunked: true,
      showSpoken: true,
    ),
    CoachStage(
      title: 'Give chunks meaning',
      goal: 'Longer numbers. Each chunk comes with a meaning. Picture it and say the chunks in a rhythm.',
      length: 8,
      studySeconds: 9,
      meaningfulBias: 0.5,
      preChunked: true,
      showSpoken: true,
      showHints: true,
    ),
    CoachStage(
      title: 'Split it yourself',
      goal: 'Tap between digits to make your own chunks of 2 to 4 digits. Then memorize your chunks.',
      length: 8,
      studySeconds: 8,
      meaningfulBias: 0.35,
      userSplit: true,
      showSpoken: true,
    ),
    CoachStage(
      title: 'Split and give meaning',
      goal: 'Split the number, then choose a meaning for every chunk before you memorize it.',
      length: 9,
      studySeconds: 9,
      meaningfulBias: 0.5,
      userSplit: true,
      pickMeaning: true,
      showSpoken: true,
    ),
    CoachStage(
      title: 'On your own',
      goal: 'No help. Split and give meaning in your head while the number is on screen.',
      length: 10,
      studySeconds: 8,
      meaningfulBias: 0.25,
    ),
  ];

  static const Map<String, String> famous = <String, String>{
    '007': 'James Bond',
    '911': 'the emergency number',
    '365': 'days in a year',
    '360': 'a full circle',
    '404': '"page not found"',
    '747': 'a jumbo jet',
    '101': 'a beginner class',
    '411': 'calling for info',
    '180': 'a U-turn',
    '100': 'a perfect score',
    '24': 'hours in a day',
    '12': 'a dozen',
    '60': 'minutes in an hour',
    '52': 'cards in a deck',
    '13': 'an unlucky number',
    '21': 'blackjack',
    '18': 'becoming an adult',
    '16': 'getting a driver\'s license',
    '42': 'the answer to everything',
    '99': 'just under 100',
    '50': 'half a hundred',
    '25': 'a quarter',
    '23': 'Michael Jordan\'s number',
    '10': 'a perfect ten',
    '90': 'a right angle',
    '88': 'keys on a piano',
    '64': 'squares on a chessboard',
    '1776': 'the Declaration of Independence',
    '1492': 'Columbus sailing',
    '1000': 'a grand',
    '1969': 'the moon landing',
    '2000': 'the new millennium',
  };

  static const List<String> _ones = <String>[
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
    'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  static const List<String> _tens = <String>[
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety',
  ];

  static String _two(int n) {
    if (n < 20) return _ones[n];
    final t = _tens[n ~/ 10];
    return n % 10 == 0 ? t : '$t-${_ones[n % 10]}';
  }

  /// How to say a chunk as a single "word": 41 → forty-one, 418 → four eighteen.
  static String spoken(String chunk) {
    final d = chunk.split('').map(int.parse).toList();
    switch (chunk.length) {
      case 1:
        return _ones[d[0]];
      case 2:
        if (chunk == '00') return 'double zero';
        return d[0] == 0 ? 'oh-${_ones[d[1]]}' : _two(int.parse(chunk));
      case 3:
        if (chunk.substring(1) == '00') return '${_ones[d[0]]} hundred';
        return '${_ones[d[0]]} ${spoken(chunk.substring(1))}';
      case 4:
        if (chunk.substring(2) == '00' && d[0] != 0) return '${spoken(chunk.substring(0, 2))} hundred';
        return '${spoken(chunk.substring(0, 2))} ${spoken(chunk.substring(2))}';
      default:
        return chunk.split('').map((c) => _ones[int.parse(c)]).join(' ');
    }
  }

  /// Ways to make a chunk meaningful, best first. Always has at least one.
  static List<String> hints(String chunk) {
    final out = <String>[];
    final n = int.parse(chunk);
    final known = famous[chunk];
    if (known != null) out.add(known);
    if (chunk.length == 4 && n >= 1900 && n <= 2035) out.add('the year $chunk');
    if (chunk.length == 4) {
      final h = int.parse(chunk.substring(0, 2));
      final m = int.parse(chunk.substring(2));
      if (h < 24 && m < 60) out.add('a time: ${chunk.substring(0, 2)}:${chunk.substring(2)}');
      if (chunk.substring(0, 2) == chunk.substring(2)) out.add('the same pair twice: ${chunk.substring(0, 2)}');
    }
    if (chunk.length == 3) {
      final h = int.parse(chunk[0]);
      final m = int.parse(chunk.substring(1));
      if (h >= 1 && m < 60) out.add('a time: $h:${chunk.substring(1)}');
    }
    if (chunk.split('').toSet().length == 1) out.add('all ${_ones[int.parse(chunk[0])]}s');
    final digits = chunk.split('').map(int.parse).toList();
    var up = true;
    var down = true;
    for (var i = 1; i < digits.length; i++) {
      if (digits[i] != digits[i - 1] + 1) up = false;
      if (digits[i] != digits[i - 1] - 1) down = false;
    }
    if (up && chunk.length > 1) out.add('counting up from ${digits.first}');
    if (down && chunk.length > 1) out.add('counting down from ${digits.first}');
    if (chunk.length == 2 && n >= 10) out.add('someone who is $n years old');
    out.add('say it as one word: "${spoken(chunk)}"');
    return out.toSet().toList();
  }

  /// Random chunk sizes of 2–4 digits that add up to [length] (length >= 2).
  static List<int> autoSplit(int length, math.Random rng) {
    final sizes = <int>[];
    var left = length;
    while (left > 0) {
      if (left <= 4) {
        sizes.add(left);
        break;
      }
      final options = <int>[2, 3, 3, 4].where((p) => left - p != 1).toList();
      final pick = options[rng.nextInt(options.length)];
      sizes.add(pick);
      left -= pick;
    }
    return sizes;
  }

  static String _meaningfulChunk(int size, math.Random rng) {
    final options = famous.keys.where((k) => k.length == size).toList();
    if (size == 4) {
      options.add('${1950 + rng.nextInt(76)}');
      options.add('${(rng.nextInt(24)).toString().padLeft(2, '0')}${(rng.nextInt(12) * 5).toString().padLeft(2, '0')}');
    }
    if (size == 3) options.add('${1 + rng.nextInt(9)}${(rng.nextInt(12) * 5).toString().padLeft(2, '0')}');
    if (size == 2) options.add('${10 + rng.nextInt(90)}');
    return options[rng.nextInt(options.length)];
  }

  static String makeNumber(List<int> sizes, double bias, math.Random rng) {
    final b = StringBuffer();
    for (final size in sizes) {
      if (rng.nextDouble() < bias) {
        b.write(_meaningfulChunk(size, rng));
      } else {
        for (var i = 0; i < size; i++) {
          b.write(rng.nextInt(10));
        }
      }
    }
    return b.toString();
  }

  /// Chunk sizes → the chunk strings.
  static List<String> cut(String number, List<int> sizes) {
    final out = <String>[];
    var i = 0;
    for (final s in sizes) {
      out.add(number.substring(i, i + s));
      i += s;
    }
    return out;
  }
}

enum _CoachPhase { intro, split, meaning, study, recall, feedback }

class ChunkCoachScreen extends StatefulWidget {
  const ChunkCoachScreen({super.key, required this.game});
  final GameState game;

  @override
  State<ChunkCoachScreen> createState() => _ChunkCoachScreenState();
}

class _ChunkCoachScreenState extends State<ChunkCoachScreen> {
  final math.Random _rng = math.Random();
  late int _stageIndex = math.min(widget.game.memory.coachStage, ChunkCoach.stages.length - 1);
  _CoachPhase _phase = _CoachPhase.intro;

  String _number = '';
  List<int> _sizes = <int>[];

  /// Gap i sits between digit i and i+1.
  Set<int> _cuts = <int>{};
  List<String> _chunks = <String>[];
  Map<int, String> _meanings = <int, String>{};
  String _entry = '';
  bool _lastPassed = false;
  bool _advanced = false;
  int _round = 0;

  GameState get game => widget.game;
  CoachStage get stage => ChunkCoach.stages[_stageIndex];
  bool get _graduated => game.memory.coachStage >= ChunkCoach.stages.length;
  Color get _color => MemoryDrill.digits.color;

  void _newRound() {
    _sizes = ChunkCoach.autoSplit(stage.length, _rng);
    _number = ChunkCoach.makeNumber(_sizes, stage.meaningfulBias, _rng);
    _chunks = stage.preChunked ? ChunkCoach.cut(_number, _sizes) : <String>[_number];
    _cuts = <int>{};
    _meanings = <int, String>{};
    _entry = '';
    _advanced = false;
    _round++;
    setState(() => _phase = stage.userSplit ? _CoachPhase.split : _CoachPhase.study);
  }

  List<String> _chunksFromCuts() {
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < _number.length - 1; i++) {
      if (_cuts.contains(i)) {
        out.add(_number.substring(start, i + 1));
        start = i + 1;
      }
    }
    out.add(_number.substring(start));
    return out;
  }

  bool get _splitValid {
    final chunks = _chunksFromCuts();
    return chunks.length > 1 && chunks.every((c) => c.length >= 2 && c.length <= 4);
  }

  void _finishSplit() {
    _chunks = _chunksFromCuts();
    setState(() => _phase = stage.pickMeaning ? _CoachPhase.meaning : _CoachPhase.study);
  }

  void _press(String key) {
    if (_phase != _CoachPhase.recall) return;
    HapticFeedback.selectionClick();
    if (key == 'del') {
      if (_entry.isNotEmpty) setState(() => _entry = _entry.substring(0, _entry.length - 1));
      return;
    }
    if (key == 'ok') {
      _submit();
      return;
    }
    if (_entry.length >= _number.length) return;
    setState(() => _entry += key);
    if (_entry.length == _number.length) _submit();
  }

  void _submit() {
    _lastPassed = _entry == _number;
    _advanced = game.recordCoach(passed: _lastPassed, stageIndex: _stageIndex);
    if (_lastPassed) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() => _phase = _CoachPhase.feedback);
  }

  void _afterFeedback() {
    if (_advanced) {
      _stageIndex = math.min(game.memory.coachStage, ChunkCoach.stages.length - 1);
      setState(() => _phase = _CoachPhase.intro);
      return;
    }
    _newRound();
  }

  @override
  Widget build(BuildContext context) {
    final streak = game.memory.coachStage == _stageIndex ? game.memory.coachStreak : 0;
    return DrillScaffold(
      drill: MemoryDrill.digits,
      progress: (_stageIndex + streak / ChunkCoach.passesToAdvance) / ChunkCoach.stages.length,
      label: 'CHUNKING COACH · STAGE ${_stageIndex + 1}/${ChunkCoach.stages.length}',
      child: switch (_phase) {
        _CoachPhase.intro => _buildIntro(),
        _CoachPhase.split => _buildSplit(),
        _CoachPhase.meaning => _buildMeaning(),
        _CoachPhase.study => _buildStudy(),
        _CoachPhase.recall => _buildRecall(),
        _CoachPhase.feedback => _buildFeedback(),
      },
    );
  }

  Widget _buildIntro() {
    final unlocked = math.min(game.memory.coachStage, ChunkCoach.stages.length - 1);
    final example = <String>['41', '97', '2001'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_graduated)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: InfoBanner(
                        icon: Icons.school,
                        color: Palette.gold,
                        text: 'You graduated the Chunking Coach. Use it in Number Span, or replay any stage.',
                      ),
                    ),
                  Text(
                    'STAGE ${_stageIndex + 1}',
                    style: TextStyle(color: _color, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stage.title,
                    style: const TextStyle(color: Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(stage.goal, style: const TextStyle(color: Palette.textPrimary, fontSize: 16.5, height: 1.45)),
                  const SizedBox(height: 18),
                  const Text(
                    'EXAMPLE',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 6),
                  const Text('41972001 is 8 digits, too many to hold. As chunks it\'s just 3 things:',
                      style: TextStyle(color: Palette.textMuted, fontSize: 14.5, height: 1.4)),
                  const SizedBox(height: 10),
                  _ChunkRow(chunks: example, color: _color, showSpoken: true, hints: const <String>['', '', 'the year 2001']),
                  const SizedBox(height: 16),
                  InfoBanner(
                    icon: Icons.flag,
                    color: _color,
                    text: 'Get ${ChunkCoach.passesToAdvance} right in a row to unlock the next stage.',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PICK A STAGE',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (var i = 0; i < ChunkCoach.stages.length; i++)
                        ChoiceChip(
                          label: Text('${i + 1}'),
                          selected: i == _stageIndex,
                          onSelected: i <= unlocked || _graduated ? (_) => setState(() => _stageIndex = i) : null,
                          avatar: i > unlocked && !_graduated ? const Icon(Icons.lock, size: 16) : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(label: 'Start stage ${_stageIndex + 1}', color: _color, onPressed: _newRound),
        ],
      ),
    );
  }

  Widget _buildSplit() {
    final chunks = _chunksFromCuts();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Tap between digits to split the number.',
            style: TextStyle(color: Palette.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('Chunks of 2 to 4 digits work best. Look for years, times and familiar numbers.',
              style: TextStyle(color: Palette.textMuted, fontSize: 14)),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < _number.length; i++) ...<Widget>[
                  Container(
                    width: 30,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Palette.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Palette.border, width: 1.5),
                    ),
                    child: Text(
                      _number[i],
                      style: const TextStyle(color: Palette.textPrimary, fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (i < _number.length - 1)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _cuts.contains(i) ? _cuts.remove(i) : _cuts.add(i));
                      },
                      child: SizedBox(
                        width: 20,
                        height: 64,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: _cuts.contains(i) ? 5 : 2,
                            height: _cuts.contains(i) ? 52 : 20,
                            decoration: BoxDecoration(
                              color: _cuts.contains(i) ? _color : Palette.border,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_cuts.isNotEmpty) _ChunkRow(chunks: chunks, color: _color, showSpoken: stage.showSpoken),
          const Spacer(),
          if (!_splitValid && _cuts.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Every chunk needs 2 to 4 digits.',
                  textAlign: TextAlign.center, style: TextStyle(color: Palette.orange, fontWeight: FontWeight.w700)),
            ),
          ChunkyButton(label: 'Done splitting', color: _color, onPressed: _splitValid ? _finishSplit : null),
        ],
      ),
    );
  }

  Widget _buildMeaning() {
    final allPicked = _meanings.length == _chunks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Give every chunk a meaning.',
            style: TextStyle(color: Palette.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text('Pick the one that clicks for you. Your own idea is even better.',
              style: TextStyle(color: Palette.textMuted, fontSize: 14)),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (var i = 0; i < _chunks.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Palette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _meanings.containsKey(i) ? _color : Palette.border, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _chunks[i],
                          style: TextStyle(color: _color, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final h in <String>[...ChunkCoach.hints(_chunks[i]).take(3), 'my own idea'])
                              ChoiceChip(
                                label: Text(h),
                                selected: _meanings[i] == h,
                                onSelected: (_) => setState(() => _meanings[i] = h),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ChunkyButton(
            label: allPicked ? 'Memorize it' : 'Pick ${_chunks.length - _meanings.length} more',
            color: _color,
            onPressed: allPicked ? () => setState(() => _phase = _CoachPhase.study) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStudy() {
    final showChunks = stage.preChunked || stage.userSplit;
    final hints = <String>[
      for (var i = 0; i < _chunks.length; i++)
        if (stage.pickMeaning)
          (_meanings[i] == 'my own idea' ? 'your idea' : (_meanings[i] ?? ''))
        else if (stage.showHints)
          ChunkCoach.hints(_chunks[i]).first
        else
          '',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StudyTimer(
            key: ValueKey<int>(_round),
            duration: Duration(seconds: stage.studySeconds),
            color: _color,
            onDone: () => setState(() => _phase = _CoachPhase.recall),
          ),
          const Spacer(),
          const Text(
            'MEMORIZE',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 14),
          if (showChunks)
            _ChunkRow(chunks: _chunks, color: _color, showSpoken: stage.showSpoken, hints: hints)
          else
            FittedBox(
              child: Text(
                _number,
                style: const TextStyle(color: Palette.textPrimary, fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 6),
              ),
            ),
          const Spacer(),
          if (showChunks)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Say the chunks in your head, twice, in a rhythm.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.textMuted, fontSize: 14),
              ),
            ),
          ChunkyButton(label: "I'm ready", color: _color, onPressed: () => setState(() => _phase = _CoachPhase.recall)),
        ],
      ),
    );
  }

  Widget _buildRecall() {
    const keys = <String>['7', '8', '9', '4', '5', '6', '1', '2', '3', 'del', '0', 'ok'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: <Widget>[
          const Text('TYPE THE NUMBER', style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 2)),
          const SizedBox(height: 6),
          const Text('Replay your chunks in your head, one at a time.',
              style: TextStyle(color: Palette.textMuted, fontSize: 13)),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var i = 0; i < _number.length; i++)
                Container(
                  width: 28,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: i == _entry.length ? _color : Palette.border, width: 2),
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
                    Expanded(child: _KeypadKey(value: keys[row * 3 + col], color: _color, onTap: _press)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedback() {
    final chunks = _chunks.length > 1 ? _chunks : ChunkCoach.cut(_number, _sizes);
    final streak = game.memory.coachStage == _stageIndex ? game.memory.coachStreak : 0;
    final String note;
    if (_advanced) {
      note = _graduated
          ? 'You graduated! Chunking is now your tool. Use it in Number Span and on real numbers.'
          : 'Stage ${_stageIndex + 2} unlocked: less help from here.';
    } else if (_lastPassed) {
      note = game.memory.coachStage == _stageIndex
          ? '$streak of ${ChunkCoach.passesToAdvance} in a row for the next stage.'
          : 'Nice. This is a replay, so it doesn\'t change your stage.';
    } else {
      note = 'Streak reset. Tip: if a chunk felt slippery, give it a stronger meaning next time.';
    }
    return DrillFeedback(
      passed: _lastPassed,
      headline: _advanced ? 'Stage cleared!' : (_lastPassed ? 'Got it' : 'Not quite'),
      levelText: note,
      nextLabel: _advanced ? 'Continue' : 'Next number',
      onNext: _afterFeedback,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('THE NUMBER, CHUNKED', style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _ChunkRow(chunks: chunks, color: Palette.green, showSpoken: true),
          const SizedBox(height: 14),
          _NumberRow(
            label: 'You typed',
            value: _entry.isEmpty ? '–' : _entry,
            color: _lastPassed ? Palette.green : Palette.red,
          ),
        ],
      ),
    );
  }
}

class _ChunkRow extends StatelessWidget {
  const _ChunkRow({required this.chunks, required this.color, this.showSpoken = false, this.hints});
  final List<String> chunks;
  final Color color;
  final bool showSpoken;
  final List<String>? hints;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (var i = 0; i < chunks.length; i++)
          Container(
            constraints: const BoxConstraints(minWidth: 76, maxWidth: 160),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(160), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  chunks[i],
                  style: const TextStyle(color: Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3),
                ),
                if (showSpoken)
                  Text(
                    ChunkCoach.spoken(chunks[i]),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                if (hints != null && i < hints!.length && hints![i].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      hints![i],
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textMuted, fontSize: 12, height: 1.25),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── How Memory Works guide ────────────────────────────────────────────────

class MemoryGuideScreen extends StatefulWidget {
  const MemoryGuideScreen({super.key, required this.game});
  final GameState game;

  static const List<LessonPage> pages = <LessonPage>[
    LessonPage('Memory is a skill',
        'People with great memories mostly aren\'t born with better brains. Studies of memory champions found ordinary brains using better techniques. You can learn the same ones.'),
    LessonPage('1. Pay attention on purpose',
        'Most "forgetting" is really never storing it. When something matters (a name, a number, where you parked), stop for three seconds and focus only on it.',
        'Meeting someone? Look at their face and say their name back: "Nice to meet you, Sam."'),
    LessonPage('2. Make it mean something',
        'Link new things to things you already know. Meaning is glue: a random number becomes a year, a name becomes a friend with the same name.',
        '1984 → the book. 0745 → quarter to eight. Ruby → a red gem.'),
    LessonPage('3. Make it a picture',
        'Your brain remembers pictures and places far better than words. Turn things into vivid, weird, moving images, and put them somewhere.',
        'Buy eggs and soap? Picture eggs exploding into soap bubbles on your front door.'),
    LessonPage('4. Test yourself',
        'Pulling a memory back out (without looking) is the strongest study habit there is. Rereading feels productive but works much less.',
        'Close the page and say what you remember. Then check.'),
    LessonPage('5. Space it out',
        'Review after a day, then a few days, then a week. Each review comes right as you start to forget, and that\'s what makes it stick. Short and often beats long and rare.'),
    LessonPage('6. Sleep on it',
        'Memories get locked in while you sleep. A good night after learning helps more than an extra late hour of studying.'),
    LessonPage('Your plan',
        'Do the Chunking Coach until you graduate, keep up the 5-minute daily workout, and use these tricks in real life: phone numbers, names, shopping lists, where you parked.'),
  ];

  @override
  State<MemoryGuideScreen> createState() => _MemoryGuideScreenState();
}

class _MemoryGuideScreenState extends State<MemoryGuideScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const pages = MemoryGuideScreen.pages;
    final last = _page >= pages.length - 1;
    const color = Palette.teal;
    return DrillScaffold(
      drill: MemoryDrill.review,
      progress: (_page + 1) / pages.length,
      label: 'HOW MEMORY WORKS',
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
                          const Icon(Icons.psychology, color: color, size: 48),
                          const SizedBox(height: 14),
                          Text(
                            page.title,
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 25, fontWeight: FontWeight.w900, height: 1.2),
                          ),
                          const SizedBox(height: 12),
                          Text(page.body, style: const TextStyle(color: Palette.textPrimary, fontSize: 16.5, height: 1.5)),
                          if (page.example != null) ...<Widget>[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: color.withAlpha(30),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: color.withAlpha(130)),
                              ),
                              child: Text(
                                page.example!,
                                style: const TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800, height: 1.4),
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
                      color: i == _page ? color : Palette.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            ChunkyButton(
              label: last ? 'Start the Chunking Coach' : 'Next',
              color: color,
              onPressed: () {
                if (last) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => ChunkCoachScreen(game: widget.game)),
                  );
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

class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final stage = game.memory.coachStage;
    final total = ChunkCoach.stages.length;
    final graduated = stage >= total;
    final color = MemoryDrill.digits.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.gold.withAlpha(150), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.school, color: Palette.gold, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Learn to remember',
                  style: TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Step-by-step coaching. Start here if the techniques feel hard.',
            style: TextStyle(color: Palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              for (var i = 0; i < total; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i < stage ? color : Palette.surfaceHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            graduated
                ? 'Chunking Coach: graduated 🎓'
                : 'Chunking Coach: stage ${stage + 1} of $total · ${ChunkCoach.stages[stage].title}',
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => MemoryGuideScreen(game: game)),
                  ),
                  icon: const Icon(Icons.menu_book, size: 18),
                  label: const Text('How memory works'),
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ChunkCoachScreen(game: game)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: Text(graduated ? 'Replay' : 'Coach me'),
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
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

// ════════════════════════════════════════════════════════════════════════════
//  THE CONSULTANT: interview several suspects and get the guilty one to confess
// ════════════════════════════════════════════════════════════════════════════

enum AskKind {
  smallTalk('Small talk', 'Read their baseline first. Costs a question, but makes every later answer meaningful.'),
  open('"Tell me everything"', 'An open question. Locks in their story before you show any evidence.'),
  reverse('"Now tell it backwards"', 'Reverse order is easy for real memories and hard for rehearsed ones. Ask after their story.'),
  detail('Ask for detail', 'Pin down the key time window. Truthful people add checkable detail; liars stay vague.'),
  unexpected('Unexpected question', 'Something they didn\'t prepare for. Liars rehearse the obvious questions only.'),
  pressure('"I know you\'re lying"', 'Pure pressure. Usually backfires: innocent and guilty both get defensive.');

  const AskKind(this.label, this.tip);
  final String label;
  final String tip;
}

class CaseEvidence {
  const CaseEvidence(this.id, this.name, this.detail, {this.implicates = false});
  final String id;
  final String name;
  final String detail;

  /// True if it contradicts the guilty suspect's story.
  final bool implicates;
}

/// Each line is "[behavior] words". The behavior part is optional.
class SuspectScript {
  const SuspectScript({
    required this.name,
    required this.emoji,
    required this.role,
    required this.answers,
    required this.evidence,
    required this.accused,
    this.evidenceEarly = const <String, String>{},
    this.confession,
  });

  final String name;
  final String emoji;
  final String role;
  final Map<AskKind, String> answers;

  /// Response to each evidence item once their story is locked in (or always, for innocents).
  final Map<String, String> evidence;

  /// Guilty suspect only: response if shown implicating evidence before telling their story.
  final Map<String, String> evidenceEarly;
  final String accused;
  final String? confession;
}

class ConsultantCase {
  const ConsultantCase({
    required this.id,
    required this.title,
    required this.briefing,
    required this.detailQuestion,
    required this.unexpectedQuestions,
    required this.evidence,
    required this.suspects,
    required this.guilty,
    required this.debrief,
    this.questionBudget = 15,
  });

  final String id;
  final String title;
  final String briefing;
  final String detailQuestion;

  /// One unexpected question per suspect (same order as [suspects]).
  final List<String> unexpectedQuestions;
  final List<CaseEvidence> evidence;
  final List<SuspectScript> suspects;
  final int guilty;
  final String debrief;
  final int questionBudget;
}

class ConsultantCases {
  ConsultantCases._();

  static const int confessAt = 70;
  static const int accusations = 2;

  static const List<ConsultantCase> all = <ConsultantCase>[
    ConsultantCase(
      id: 'tips',
      title: 'The Missing Tips',
      briefing: 'At Rosa\'s Diner, \$600 in tips vanished from the tip jar at closing on Friday. The jar was on the '
          'counter at 10:00 PM and gone by 10:30. Three people were still working.',
      detailQuestion: 'What exactly were you doing between 10:00 and 10:20?',
      unexpectedQuestions: <String>[
        'What did the kitchen look like when you left?',
        'What was the last thing you threw away tonight?',
        'What was the score of the game on the radio?',
      ],
      evidence: <CaseEvidence>[
        CaseEvidence('door', 'Back door camera',
            'The kitchen\'s back door opened at 10:12 PM. Too dark to see a face, but the person carried a trash bag.',
            implicates: true),
        CaseEvidence('bag', 'The trash bag',
            'The empty tip jar was found in the dumpster inside a black, heavy-duty bag. The kitchen uses black bags; servers use clear ones.',
            implicates: true),
        CaseEvidence('clock', 'Time clock',
            'Mia clocked out at 9:55 PM, Dev at 10:20 PM, Ron at 10:31 PM.'),
      ],
      guilty: 1,
      suspects: <SuspectScript>[
        SuspectScript(
          name: 'Mia',
          emoji: '👩‍🦰',
          role: 'Server',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[talks fast, clicks her pen] Busy week! Double shifts, my feet are dead. Sorry, I talk fast when I\'m tired.',
            AskKind.open: '[talks fast, clicks her pen] I finished my tables around 9:30, rolled silverware, cashed out with Ron at 9:45 '
                'and clocked out at 9:55. My boyfriend was late picking me up, so I waited by the host stand until about 10:05.',
            AskKind.reverse: '[clicks her pen] Okay, backwards: boyfriend pulled up, I was waiting by the host stand, I clocked out… '
                'oh wait, I grabbed my jacket from the break room first, then clocked out. Before that I cashed out with Ron.',
            AskKind.detail: '[talks fast] By the host stand on my phone, texting my boyfriend "where are you". Kevin the busser was '
                'stacking chairs right next to me. Ask him.',
            AskKind.unexpected: '[thinks for a second] I didn\'t go back there at the end, honestly. The lights were on and I could hear '
                'the dish machine.',
            AskKind.pressure: '[pen clicking faster] Excuse me? I\'ve worked here three years. Check the cameras, I was out front.',
          },
          evidence: <String, String>{
            'door': '10:12? I was out front, or already in the car. The back door\'s in the kitchen. I had no reason to go back there.',
            'bag': 'Black bags are kitchen bags. We use the clear ones up front.',
            'clock': 'Yep, 9:55. That\'s me.',
          },
          accused: '[stops clicking her pen] No. Ask Kevin, ask my boyfriend. I was out front the whole time.',
        ),
        SuspectScript(
          name: 'Dev',
          emoji: '🧑‍🍳',
          role: 'Line cook',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[arms crossed, steady eye contact] Fine. Tired. Long week.',
            AskKind.open: '[arms crossed, steady eye contact] I closed the line. Scraped the grill, wrapped everything, mopped. '
                'Clocked out at 10:20 and went home. Didn\'t take anything out.',
            AskKind.reverse: '[looks away for the first time] Backwards? Clocked out… before that I mopped… before that, uh… scraped '
                'the grill. And the line.',
            AskKind.detail: '[uncrosses his arms and rubs the back of his neck] Mopping. The whole time.',
            AskKind.unexpected: '[long pause, looks at the floor] …I don\'t know. Food scraps? I told you, I didn\'t take anything out.',
            AskKind.pressure: '[arms crossed tighter] I don\'t have to listen to this.',
          },
          evidenceEarly: <String, String>{
            'door': '[steady eye contact] Somebody took trash out. Probably the dishwasher. I was mopping.',
            'bag': '[shrugs] Anybody can grab a kitchen bag.',
          },
          evidence: <String, String>{
            'door': '[long pause, looks away] I… okay, maybe I took one bag out. I forgot. It\'s not a big deal.',
            'bag': '[voice drops, rubs his neck] That bag… I don\'t know how the jar got in there.',
            'clock': '[arms crossed] 10:20. Like I said.',
          },
          accused: '[arms crossed, steady eye contact] You\'ve got nothing. I mopped and went home.',
          confession: '[long silence, then quietly] …Fine. I took it. They cut my hours and rent was due. I dropped the jar in a '
              'trash bag at 10:12 and pulled it out of the dumpster after I clocked out. I was going to pay it back.',
        ),
        SuspectScript(
          name: 'Ron',
          emoji: '👴',
          role: 'Manager',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[laughs, adjusts his glasses] Oh, you know. Keeping the ship afloat.',
            AskKind.open: '[speaks slowly] Counted the register with Mia at 9:45, then did paperwork in the office with the door shut: '
                'the sales report, then next week\'s schedule. Walked the floor at 10:25, set the alarm, out at 10:31.',
            AskKind.reverse: '[adjusts his glasses] Alarm at 10:31, walked the floor, paperwork… the schedule first, actually, then '
                'sales numbers. And before that the register with Mia.',
            AskKind.detail: '[speaks slowly] In the office, door closed, the game on the radio. I heard the dish machine and somebody '
                'banging around in the kitchen. Mopping, I figured.',
            AskKind.unexpected: '[laughs] Three to one Rangers, last I heard, and they blew it in the ninth. I was yelling at the radio.',
            AskKind.pressure: '[laughs, but annoyed] I\'m the one who called you. Why would I report my own theft?',
          },
          evidence: <String, String>{
            'door': '[adjusts his glasses] 10:12… I was in the office. You can\'t see the back door from there. Huh.',
            'bag': 'Black bags are kitchen. Servers don\'t touch those.',
            'clock': 'That matches. Dev was the last one in the kitchen.',
          },
          accused: '[laughs in disbelief] I called this in! Check the office camera, I never left that chair.',
        ),
      ],
      debrief: 'Dev did it. His story left out the trash run ("didn\'t take anything out"). Once he\'d locked that in, the door '
          'camera and the kitchen bag contradicted him. His behavior also broke HIS baseline: steady eye contact turned into '
          'looking away, crossed arms into neck rubbing. Mia\'s fast talk and pen clicking were her normal, and Ron gave '
          'details you could check (the radio, the score). Pressure only made Dev shut down.',
    ),
    ConsultantCase(
      id: 'exam',
      title: 'The Leaked Exam',
      briefing: 'The answer key to Ms. Grant\'s chemistry final appeared in a student group chat at 7:40 PM Thursday. The key '
          'was printed after school, and three people could have reached it.',
      detailQuestion: 'Where were you, exactly, between 3:45 and 4:10?',
      unexpectedQuestions: <String>[
        'What were the handouts you were stapling about?',
        'Which class\'s labs were you grading?',
        'What did you find in the science wing trash?',
      ],
      evidence: <CaseEvidence>[
        CaseEvidence('print', 'Printer log',
            'The answer key was printed at 3:52 PM from Ms. Grant\'s classroom computer.'),
        CaseEvidence('key', 'Supply-room key log',
            'The key to the supply room (where the printer is) was signed out at 3:45 PM by "T." and returned at 4:10 PM.',
            implicates: true),
        CaseEvidence('photo', 'The leaked photo',
            'The photo shows the key on a wooden student desk, with a blue-striped notebook in the corner.',
            implicates: true),
      ],
      guilty: 0,
      suspects: <SuspectScript>[
        SuspectScript(
          name: 'Tyler',
          emoji: '👦',
          role: 'Student aide',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[smiles, lots of eye contact] Pretty good! Soccer game Saturday, we\'re playing Central.',
            AskKind.open: '[smiles, eye contact] I helped Ms. Grant after school until like four, stapled handouts, then went home '
                'and did homework all night. I didn\'t even check my phone.',
            AskKind.reverse: '[smile fades] Uh… homework, before that I went home, before that stapled… handouts. And helped.',
            AskKind.detail: '[answers instantly, smile gone] In the classroom. Stapling. The whole time.',
            AskKind.unexpected: '[pause] …Something for history? I didn\'t really read them.',
            AskKind.pressure: '[smiling again] I\'m a good student. Why would I need to cheat?',
          },
          evidenceEarly: <String, String>{
            'key': '[smiles] "T" could be anyone.',
            'photo': '[shrugs] Tons of people have notebooks like that.',
          },
          evidence: <String, String>{
            'print': '[eye contact] She prints stuff all the time.',
            'key': '[smile drops, voice quieter] …I signed it out to get paper. I forgot. That\'s not a crime.',
            'photo': '[touches his neck, voice cracks] That\'s… a lot of people have that notebook.',
          },
          accused: '[smiling, eye contact] No way. I was stapling handouts.',
          confession: '[looks down, quiet] Okay. When I got paper, the key was on the printer. I took a picture and sent it to one '
              'person. I didn\'t think it would go everywhere.',
        ),
        SuspectScript(
          name: 'Ms. Grant',
          emoji: '👩‍🏫',
          role: 'Chemistry teacher',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[pauses before answering, hands folded] Busy. Finals week is always busy.',
            AskKind.open: '[pauses, hands folded] I printed the key at 3:52 to check the formatting, then locked it in my desk '
                'drawer. Tyler helped with handouts until about four. I graded until 5:30 and drove home.',
            AskKind.reverse: '[pauses] Drove home at 5:30, graded, Tyler left around four… no, ten past four… and before that I '
                'printed the key and locked it away.',
            AskKind.detail: '[pauses, hands folded] At my desk grading. Tyler was at the side table, but he stepped out for about '
                'twenty minutes to get printer paper.',
            AskKind.unexpected: '[pauses] Third period\'s titration lab. Half of them forgot their units.',
            AskKind.pressure: '[pauses] I understand you have to ask. No.',
          },
          evidence: <String, String>{
            'print': '[hands folded] Yes, that was me, checking the formatting.',
            'key': '[pauses] "T" would be Tyler. I sent him for paper around then.',
            'photo': '[pauses] That isn\'t my desk. Mine is gray metal. That\'s a wooden student desk.',
          },
          accused: '[pauses, hands folded] I printed it and locked it away. I would not leak my own exam.',
        ),
        SuspectScript(
          name: 'Jordan',
          emoji: '🧔',
          role: 'Custodian',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[laughs, scratches his beard] Can\'t complain. Well, I can, but nobody listens.',
            AskKind.open: '[slow, laid back] Shift starts at four. Gym first, science wing around six. Checked the printer room at '
                'six-thirty, locked. Left at eleven.',
            AskKind.reverse: '[scratches his beard] Left at eleven, mopped the cafeteria, science wing around six, printer room locked, '
                'gym first. Yeah.',
            AskKind.detail: '[laughs] At 3:45 I was in my truck in the lot eating lunch. Shift doesn\'t start till four.',
            AskKind.unexpected: '[scratches his beard] Broken beaker in Grant\'s room, papers, a granola bar wrapper. The usual.',
            AskKind.pressure: '[laughs] Man, I can barely work the copier.',
          },
          evidence: <String, String>{
            'print': '[shrugs] Don\'t know nothing about printers.',
            'key': '[laughs] That\'s not my initial. Mine\'s J.',
            'photo': '[squints] I don\'t even have that chat app.',
          },
          accused: '[laughs] Wasn\'t even inside at 3:45. Check the parking lot camera.',
        ),
      ],
      debrief: 'Tyler did it. He committed to "stapling the whole time", then the key log ("T", 3:45–4:10) and Ms. Grant\'s '
          'detail (he stepped out for paper) broke his story. The unexpected question exposed him too: he said the handouts '
          'were for history, but Ms. Grant teaches chemistry. His smile and eye contact were his baseline; the smile dropping '
          'was the change. Ms. Grant\'s long pauses were HER normal, not stalling.',
    ),
    ConsultantCase(
      id: 'car',
      title: 'The Hit-and-Run',
      briefing: 'Someone backed into a neighbor\'s parked car outside the grocery store on Saturday around 2 PM and drove off. '
          'Three neighbors were at that shopping center then.',
      detailQuestion: 'What were you doing between 2:00 and 2:10?',
      unexpectedQuestions: <String>[
        'Who was parked next to you?',
        'What size hinge did you buy?',
        'What did you order?',
      ],
      evidence: <CaseEvidence>[
        CaseEvidence('paint', 'Paint scrape', 'Blue paint was scraped onto the victim\'s rear bumper.', implicates: true),
        CaseEvidence('camera', 'Store camera', 'A blue SUV left the lot fast at 2:09 PM. The plate isn\'t readable.',
            implicates: true),
        CaseEvidence('receipt', 'Receipt on the windshield',
            'A coffee shop receipt from 2:12 PM was stuck under the victim\'s wiper. No note.'),
      ],
      guilty: 0,
      suspects: <SuspectScript>[
        SuspectScript(
          name: 'Alicia',
          emoji: '👩',
          role: 'Drives a blue SUV',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[laughs, talks with her hands] Oh, it\'s been a week! My kid\'s birthday party, total chaos.',
            AskKind.open: '[talks with her hands] Grabbed groceries around two, loaded the car and drove home. Normal Saturday.',
            AskKind.reverse: '[hands go still] Got home… before that I drove… before that I loaded the groceries. And shopped.',
            AskKind.detail: '[hands still in her lap] Loading groceries. I was parked way at the end, nowhere near anybody.',
            AskKind.unexpected: '[looks away] …I didn\'t notice. Nobody, maybe.',
            AskKind.pressure: '[laughs, hands moving again] Wow. Okay. I have a perfect driving record.',
          },
          evidenceEarly: <String, String>{
            'paint': '[laughs] Lots of cars are blue.',
            'camera': '[talks with her hands] Half the town drives an SUV.',
          },
          evidence: <String, String>{
            'paint': '[hands still, voice drops] Blue… I mean, I did bump something backing out, but I thought it was a cart.',
            'camera': '[no laugh] I was in a hurry. My ice cream was melting.',
            'receipt': '[talks with her hands] Not mine. I paid with my phone.',
          },
          accused: '[laughs, hands moving] Me? I was nowhere near that car.',
          confession: '[quiet, hands still] Okay. I backed into it. I panicked and just drove. I\'ll pay for the damage.',
        ),
        SuspectScript(
          name: 'Chris',
          emoji: '👨',
          role: 'Drives a red pickup',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[arms crossed, short sentences] Fine. Busy.',
            AskKind.open: '[arms crossed] Hardware store at 1:30. Bought a hinge. Left at 1:50. Drove home.',
            AskKind.reverse: '[arms crossed] Home. Drove. Left the store at 1:50. Bought a hinge. Got there 1:30.',
            AskKind.detail: '[arms crossed] On Route 9 by then. Gas station receipt at 2:04 says so.',
            AskKind.unexpected: '[arms crossed] Three-and-a-half inch. Brass. For the shed door.',
            AskKind.pressure: '[arms crossed] Check my truck. Not a scratch on it.',
          },
          evidence: <String, String>{
            'paint': '[arms crossed] My truck\'s red.',
            'camera': '[arms crossed] Not an SUV.',
            'receipt': '[arms crossed] Wasn\'t at the coffee shop.',
          },
          accused: '[arms crossed] I was on Route 9. Check the gas station camera.',
        ),
        SuspectScript(
          name: 'Sam',
          emoji: '🧑‍🦱',
          role: 'Drives a blue sedan',
          answers: <AskKind, String>{
            AskKind.smallTalk: '[talks fast, touches his face] Good! Sorry, I always get nervous talking to officials.',
            AskKind.open: '[talks fast, touches his face] Sorry, okay. I went into the coffee shop at 1:55, came out at 2:15. My car '
                'was right out front. Sorry, I get nervous with this stuff.',
            AskKind.reverse: '[touches his face] Drove home, came out at 2:15, got coffee… oh, and I parked first, obviously. Sorry.',
            AskKind.detail: '[talks fast] In line. It was super long. I have the receipt, look: 2:12.',
            AskKind.unexpected: '[laughs nervously, touches his face] Large oat latte, extra shot. Sorry, that\'s embarrassing.',
            AskKind.pressure: '[touches his face, talks faster] Sorry, I mean, no! I didn\'t hit anything!',
          },
          evidence: <String, String>{
            'paint': '[touches his face] My car\'s blue, but look, no scratches. You can check.',
            'camera': '[talks fast] I drive a sedan, not an SUV.',
            'receipt': '[talks fast] That\'s not mine. Mine says 2:12 too… huh, they must print a lot of receipts.',
          },
          accused: '[touches his face] I was in line for coffee! The barista knows me!',
        ),
      ],
      debrief: 'Alicia did it. She claimed she was "nowhere near anybody" but couldn\'t say who parked next to her, and the '
          'blue paint and the SUV on camera broke her story once she\'d committed to it. Her baseline is animated and laughing; '
          'her hands going still was the change. Sam is nervous ALL the time (touching his face, apologizing). Nervous isn\'t '
          'guilty. The receipt was a red herring.',
    ),
  ];
}

/// The state of one investigation.
class Investigation {
  Investigation(this.file)
      : transcripts = List<List<String>>.generate(file.suspects.length, (_) => <String>[]),
        asked = List<Set<String>>.generate(file.suspects.length, (_) => <String>{}),
        told = List<bool>.filled(file.suspects.length, false);

  final ConsultantCase file;
  final List<List<String>> transcripts;
  final List<Set<String>> asked;
  final List<bool> told;
  int questionsUsed = 0;
  int accusationsLeft = ConsultantCases.accusations;
  int crack = 0;
  int goodMoves = 0;
  int pressureMoves = 0;
  bool solved = false;
  bool over = false;

  int get questionsLeft => file.questionBudget - questionsUsed;
  bool get outOfQuestions => questionsLeft <= 0;

  String questionText(AskKind kind, int suspect) => switch (kind) {
        AskKind.smallTalk => 'How\'s your week been?',
        AskKind.open => 'Tell me everything about that evening, from the start.',
        AskKind.reverse => 'Now tell it to me backwards, from the end.',
        AskKind.detail => file.detailQuestion,
        AskKind.unexpected => file.unexpectedQuestions[suspect],
        AskKind.pressure => 'I know you\'re lying. Just admit it.',
      };

  void ask(int s, AskKind kind) {
    asked[s].add(kind.name);
    questionsUsed++;
    final script = file.suspects[s];
    final guilty = s == file.guilty;
    String answer;
    if (kind == AskKind.reverse && !told[s]) {
      answer = '[confused] Backwards from what? I haven\'t told you my side yet.';
    } else {
      answer = script.answers[kind]!;
    }
    transcripts[s]
      ..add('Q:${questionText(kind, s)}')
      ..add('A:$answer');
    if (kind == AskKind.open) told[s] = true;
    if (kind == AskKind.pressure) {
      pressureMoves++;
      if (guilty) crack = math.max(0, crack - 10);
      return;
    }
    if (!guilty) return;
    final gain = switch (kind) {
      AskKind.open => 5,
      AskKind.reverse => told[s] ? 20 : 0,
      AskKind.detail => told[s] ? 15 : 5,
      AskKind.unexpected => 15,
      _ => 0,
    };
    if (gain >= 15) goodMoves++;
    crack += gain;
  }

  void show(int s, CaseEvidence e) {
    asked[s].add('ev:${e.id}');
    questionsUsed++;
    final script = file.suspects[s];
    final guilty = s == file.guilty;
    final early = guilty && e.implicates && !told[s];
    final answer = early
        ? (script.evidenceEarly[e.id] ?? script.evidence[e.id]!)
        : script.evidence[e.id]!;
    transcripts[s]
      ..add('Q:Take a look at this: ${e.name}.')
      ..add('A:$answer');
    if (guilty && e.implicates) {
      final gain = early ? 10 : 35;
      if (!early) goodMoves++;
      crack += gain;
    }
  }

  /// Returns the suspect's reply.
  String accuse(int s) {
    final script = file.suspects[s];
    final guilty = s == file.guilty;
    String reply;
    if (guilty && crack >= ConsultantCases.confessAt) {
      solved = true;
      over = true;
      reply = script.confession!;
    } else {
      accusationsLeft--;
      if (guilty) crack = math.max(0, crack - 10);
      reply = script.accused;
      if (accusationsLeft <= 0) over = true;
    }
    transcripts[s]
      ..add('Q:I think you did it.')
      ..add('A:$reply');
    return reply;
  }

  int get stars {
    if (!solved) return 0;
    if (questionsUsed <= 9 && pressureMoves == 0) return 3;
    if (questionsUsed <= 12) return 2;
    return 1;
  }
}

/// Splits "[behavior] words" into its two parts.
(String?, String) splitAnswer(String raw) {
  if (raw.startsWith('[')) {
    final end = raw.indexOf(']');
    if (end > 0) return (raw.substring(1, end), raw.substring(end + 1).trim());
  }
  return (null, raw);
}

// ── Consultant hub ────────────────────────────────────────────────────────

class ConsultantHubScreen extends StatelessWidget {
  const ConsultantHubScreen({super.key, required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: game,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Palette.textMuted),
                  ),
                  const Expanded(
                    child: Text(
                      'The Consultant',
                      style: TextStyle(color: Palette.textPrimary, fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const InfoBanner(
                icon: Icons.gavel,
                color: Palette.indigo,
                text: 'Interview the suspects, switch between them, and get the guilty one to confess. '
                    'Lock in each story first, then show evidence. Pressure backfires. '
                    '${ConsultantCases.accusations} accusations, limited questions.',
              ),
              const SizedBox(height: 16),
              for (final c in ConsultantCases.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => InterrogationScreen(game: game, file: c)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: <Widget>[
                            Text(c.suspects.map((s) => s.emoji).join(), style: const TextStyle(fontSize: 26)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    c.title,
                                    style: const TextStyle(color: Palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${c.suspects.length} suspects · ${c.questionBudget} questions',
                                    style: const TextStyle(color: Palette.textMuted, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _starText(game.caseStars[c.id] ?? 0),
                              style: const TextStyle(fontSize: 16, color: Palette.gold),
                            ),
                          ],
                        ),
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

  static String _starText(int stars) => stars == 0 ? 'unsolved' : '★' * stars + '☆' * (3 - stars);
}

// ── Interrogation room ────────────────────────────────────────────────────

class InterrogationScreen extends StatefulWidget {
  const InterrogationScreen({super.key, required this.game, required this.file});
  final GameState game;
  final ConsultantCase file;

  @override
  State<InterrogationScreen> createState() => _InterrogationScreenState();
}

class _InterrogationScreenState extends State<InterrogationScreen> {
  late Investigation _inv = Investigation(widget.file);
  late List<int> _order = _shuffledOrder();
  int _current = 0;
  bool _briefed = false;
  final ScrollController _scroll = ScrollController();

  ConsultantCase get file => widget.file;

  List<int> _shuffledOrder() => List<int>.generate(widget.file.suspects.length, (i) => i)..shuffle();

  int get _suspect => _order[_current];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _afterMove() {
    HapticFeedback.selectionClick();
    setState(() {});
    _scrollToEnd();
    if (_inv.outOfQuestions && !_inv.over) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          backgroundColor: Palette.surfaceHigh,
          content: Text('Out of questions. Make your accusation.', style: TextStyle(color: Palette.textPrimary)),
        ));
    }
  }

  void _ask(AskKind kind) {
    if (_inv.outOfQuestions || _inv.over) return;
    _inv.ask(_suspect, kind);
    _afterMove();
  }

  Future<void> _showEvidence() async {
    if (_inv.outOfQuestions || _inv.over) return;
    final picked = await showModalBottomSheet<CaseEvidence>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: <Widget>[
            Text(
              'Show ${file.suspects[_suspect].name} evidence',
              style: const TextStyle(color: Palette.textPrimary, fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text('Tip: evidence hits hardest after they\'ve told their story.',
                style: TextStyle(color: Palette.textMuted, fontSize: 13)),
            const SizedBox(height: 12),
            for (final e in file.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OptionTile(
                  visual: OptionVisual.idle,
                  onTap: _inv.asked[_suspect].contains('ev:${e.id}') ? null : () => Navigator.of(sheetContext).pop(e),
                  leading: Icon(
                    _inv.asked[_suspect].contains('ev:${e.id}') ? Icons.check : Icons.description,
                    color: Palette.indigo,
                  ),
                  text: '${e.name}: ${e.detail}',
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _inv.show(_suspect, picked);
    _afterMove();
  }

  Future<void> _accuse() async {
    if (_inv.over) return;
    final name = file.suspects[_suspect].name;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text('Accuse $name?', style: const TextStyle(color: Palette.textPrimary)),
        content: Text(
          'You have ${_inv.accusationsLeft} accusation${_inv.accusationsLeft == 1 ? '' : 's'} left. '
          'Only accuse when your case is strong enough to make them crack.',
          style: const TextStyle(color: Palette.textMuted),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('NOT YET')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ACCUSE', style: TextStyle(color: Palette.red)),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    _inv.accuse(_suspect);
    if (_inv.solved) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    if (_inv.over) widget.game.recordCase(file.id, _inv.stars);
    setState(() {});
    _scrollToEnd();
  }

  void _restart() {
    setState(() {
      _inv = Investigation(file);
      _order = _shuffledOrder();
      _current = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: !_briefed
            ? _buildBriefing()
            : (_inv.over ? _buildDebrief() : _buildRoom()),
      ),
    );
  }

  Widget _buildBriefing() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Palette.textMuted),
              ),
              const Text('CASE FILE', style: TextStyle(color: Palette.indigo, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
            ],
          ),
          Expanded(
            child: ListView(
              children: <Widget>[
                Text(file.title,
                    style: const TextStyle(color: Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Text(file.briefing, style: const TextStyle(color: Palette.textPrimary, fontSize: 16, height: 1.5)),
                const SizedBox(height: 18),
                const Text('SUSPECTS',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                for (final s in file.suspects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Text(s.emoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(width: 10),
                        Text('${s.name} · ${s.role}',
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('EVIDENCE',
                    style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                for (final e in file.evidence)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ContextCard(label: e.name.toUpperCase(), icon: Icons.description, text: e.detail, accent: Palette.indigo),
                  ),
                const SizedBox(height: 8),
                InfoBanner(
                  icon: Icons.lightbulb,
                  color: Palette.gold,
                  text: 'Jane\'s method: get each baseline, let them commit to a story, then use the evidence. '
                      'Budget: ${file.questionBudget} questions, ${ConsultantCases.accusations} accusations.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(
            label: 'Enter the interview room',
            color: Palette.indigo,
            onPressed: () => setState(() => _briefed = true),
          ),
        ],
      ),
    );
  }

  Widget _buildRoom() {
    final script = file.suspects[_suspect];
    final transcript = _inv.transcripts[_suspect];
    final asked = _inv.asked[_suspect];
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Leave the case',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Palette.textMuted),
              ),
              Expanded(
                child: Text(file.title.toUpperCase(),
                    style: const TextStyle(color: Palette.indigo, fontWeight: FontWeight.w900, letterSpacing: 1)),
              ),
              Text('❓ ${_inv.questionsLeft}  ⚖️ ${_inv.accusationsLeft}',
                  style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800)),
              IconButton(
                tooltip: 'Case file',
                onPressed: () => setState(() => _briefed = false),
                icon: const Icon(Icons.folder_open, color: Palette.textMuted),
              ),
            ],
          ),
        ),
        // Suspect switcher
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: <Widget>[
              for (var i = 0; i < _order.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _current = i);
                      _scrollToEnd();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 104,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: i == _current ? Palette.indigo.withAlpha(50) : Palette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: i == _current ? Palette.indigo : Palette.border, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(file.suspects[_order[i]].emoji, style: const TextStyle(fontSize: 28)),
                          Text(
                            file.suspects[_order[i]].name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          Text(
                            '${_inv.transcripts[_order[i]].length ~/ 2} asked',
                            style: const TextStyle(color: Palette.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Transcript
        Expanded(
          child: transcript.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '${script.emoji}\n${script.name} sits down across from you.\nStart with small talk to read their baseline.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Palette.textMuted, fontSize: 15, height: 1.5),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: transcript.length,
                  itemBuilder: (context, i) => _TranscriptLine(raw: transcript[i], suspect: script),
                ),
        ),
        // Actions
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: Palette.surface,
            border: Border(top: BorderSide(color: Palette.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final kind in AskKind.values)
                    Tooltip(
                      message: kind.tip,
                      triggerMode: TooltipTriggerMode.longPress,
                      child: ActionChip(
                        label: Text(kind.label),
                        onPressed: asked.contains(kind.name) || _inv.outOfQuestions ? null : () => _ask(kind),
                        backgroundColor: kind == AskKind.pressure ? Palette.red.withAlpha(30) : Palette.surfaceHigh,
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.description, size: 18),
                    label: const Text('Show evidence'),
                    onPressed: _inv.outOfQuestions ? null : _showEvidence,
                    backgroundColor: Palette.indigo.withAlpha(40),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Long-press a question to see why it works.',
                  style: TextStyle(color: Palette.textMuted, fontSize: 11.5)),
              const SizedBox(height: 8),
              ChunkyButton(label: 'Accuse ${script.name}', color: Palette.red, height: 46, onPressed: _accuse),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDebrief() {
    final guilty = file.suspects[file.guilty];
    final stars = _inv.stars;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ListView(
              children: <Widget>[
                const SizedBox(height: 12),
                Text(_inv.solved ? '🕵️' : '🗂️', textAlign: TextAlign.center, style: const TextStyle(fontSize: 64)),
                const SizedBox(height: 8),
                Text(
                  _inv.solved ? 'Confession!' : 'Case unsolved',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _inv.solved ? Palette.gold : Palette.red,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_inv.solved)
                  Text(
                    '${'★' * stars}${'☆' * (3 - stars)}  ·  ${_inv.questionsUsed} questions',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.gold, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                const SizedBox(height: 16),
                if (_inv.solved)
                  ContextCard(
                    label: '${guilty.name.toUpperCase()} CONFESSES',
                    icon: Icons.record_voice_over,
                    text: splitAnswer(guilty.confession!).$2,
                    accent: Palette.gold,
                  ),
                const SizedBox(height: 12),
                ContextCard(label: 'DEBRIEF', icon: Icons.lightbulb, text: file.debrief, accent: Palette.indigo),
                const SizedBox(height: 12),
                InfoBanner(
                  icon: Icons.insights,
                  color: Palette.teal,
                  text: 'Strong moves: ${_inv.goodMoves} · Pressure moves: ${_inv.pressureMoves}. '
                      '3 stars = solved in 9 questions or fewer with no pressure.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ChunkyButton(label: 'Done', color: Palette.green, onPressed: () => Navigator.of(context).maybePop()),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              _restart();
              setState(() => _briefed = true);
            },
            child: const Text('PLAY AGAIN',
                style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({required this.raw, required this.suspect});
  final String raw;
  final SuspectScript suspect;

  @override
  Widget build(BuildContext context) {
    final isQuestion = raw.startsWith('Q:');
    final body = raw.substring(2);
    if (isQuestion) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Palette.indigo.withAlpha(60),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(body, style: const TextStyle(color: Palette.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w600)),
        ),
      );
    }
    final (behavior, words) = splitAnswer(body);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${suspect.emoji} ${suspect.name}',
                style: const TextStyle(color: Palette.textMuted, fontSize: 11.5, fontWeight: FontWeight.w800)),
            if (behavior != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(behavior,
                    style: const TextStyle(color: Palette.orange, fontSize: 13, fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 3),
            Text('"$words"', style: const TextStyle(color: Palette.textPrimary, fontSize: 15, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  REAL LIFE: Two Truths and a Lie with friends
// ════════════════════════════════════════════════════════════════════════════

/// What you went on when you made a real-life guess.
enum LieClue {
  detail('Detail level', 'Rich vs. thin and vague', '🔬', true),
  checkable('Checkable facts', 'Could I verify it or not?', '🧾', true),
  consistency('Story didn\'t hold up', 'Changed, or didn\'t fit', '🧩', true),
  reaction('Reaction to my question', 'Stalled, dodged, over-explained', '⏸️', true),
  body('Body language', 'Hands, posture, fidgeting', '🙌', false),
  face('Face & eyes', 'Smile, eye contact, expression', '👀', false),
  gut('Just a feeling', 'No specific reason', '🎲', false);

  const LieClue(this.label, this.hint, this.emoji, this.verbal);
  final String label;
  final String hint;
  final String emoji;

  /// Clues that come from what they said or how they handled questions.
  final bool verbal;
}

class AskCard {
  const AskCard(this.title, this.example, this.why);
  final String title;
  final String example;
  final String why;

  static const List<AskCard> all = <AskCard>[
    AskCard('Ask for checkable details', '"Who else was there? Where exactly? What day was it?"',
        'Real memories come with names, places and times you could check. Liars stay vague, or pick details nobody can check ("some guy", "I was alone").'),
    AskCard('Ask something unexpected', '"What was the weather like?" · "What were you wearing?"',
        'People rehearse the main story, not the side details. Watch for a stall, or a fast "I don\'t remember" on something easy.'),
    AskCard('Ask for more', '"Tell me everything about that, even the small stuff."',
        'Real memories expand easily. Made-up ones stay thin, or get padded with feelings and opinions instead of facts.'),
    AskCard('Go backwards', '"What happened right before that? And before that?"',
        'Telling a story out of order is hard when it\'s invented. True stories survive being told backwards.'),
    AskCard('Ask how they know', '"How do you remember it was a Tuesday?"',
        'Truth-tellers can usually say where a memory comes from ("it was my mom\'s birthday"). Liars often can\'t.'),
    AskCard('Come back to it later', 'Two minutes later: "Wait, when was that again?"',
        'True details stay the same. Invented ones drift, or get said word-for-word like a script.'),
    AskCard('Ask them to place things', '"Where was everyone standing? Which side was the door on?"',
        'Laying out a scene is hard to fake on the spot. Real memories have a layout.'),
    AskCard('Pause after they answer', 'Say nothing. Just look interested for 3 seconds.',
        'Silence makes people fill the gap. Liars often add too much, or a detail that doesn\'t fit.'),
    AskCard('Hold back what you know', 'If you already know a fact, don\'t say it. Let them commit first.',
        'Then compare their story with what you know. This is the best-tested technique investigators use.'),
  ];
}

class RealLifeScreen extends StatefulWidget {
  const RealLifeScreen({super.key, required this.game});
  final GameState game;

  @override
  State<RealLifeScreen> createState() => _RealLifeScreenState();
}

class _RealLifeScreenState extends State<RealLifeScreen> {
  static const List<String> _confidenceLabels = <String>['Guessing', 'Fairly sure', 'Certain'];

  final TextEditingController _name = TextEditingController();
  int? _guess;
  LieClue? _clue;
  int? _confidence;
  String? _result;
  bool? _lastCorrect;
  int _card = 0;

  GameState get game => widget.game;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => _guess != null && _clue != null && _confidence != null;

  void _reveal(int lie) {
    final friend = _name.text.trim().isEmpty ? 'Friend' : _name.text.trim();
    final correct = _guess == lie;
    final clue = _clue!;
    game.recordRealLife(friend, correct: correct, clue: clue, confidence: _confidence);
    if (correct) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    final s = game.clueStats[clue]!;
    setState(() {
      _lastCorrect = correct;
      _result = (correct ? 'You caught $friend\'s lie! 🎯' : '$friend fooled you. The lie was #$lie.') +
          ' Going by ${clue.label.toLowerCase()}, you\'re now ${s[1]}/${s[0]}.' +
          (correct ? '' : ' Ask them what was true about the one you picked; that\'s where you learn.');
      _guess = null;
      _clue = null;
      _confidence = null;
      _card = (_card + 1) % AskCard.all.length;
    });
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  @override
  Widget build(BuildContext context) {
    final card = AskCard.all[_card];
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Palette.textMuted),
                ),
                const Expanded(
                  child: Text('Two Truths & a Lie',
                      style: TextStyle(color: Palette.textPrimary, fontSize: 23, fontWeight: FontWeight.w900)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const LieScienceScreen())),
                  child: const Text('THE SCIENCE', style: TextStyle(color: Palette.pink, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const InfoBanner(
              icon: Icons.groups,
              color: Palette.pink,
              text: 'This is where the real skill grows: real people, a committed guess, then the truth. A friend '
                  'says three things about themselves; two are true, one is a lie. Question them, then guess.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              style: const TextStyle(color: Palette.textPrimary),
              decoration: InputDecoration(
                labelText: 'Friend\'s name',
                labelStyle: const TextStyle(color: Palette.textMuted),
                filled: true,
                fillColor: Palette.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 16),
            _label('1. QUESTION THEM ABOUT ALL THREE'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.pink.withAlpha(28),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.pink.withAlpha(140)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('💬 ${card.title}',
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
                      ),
                      Text('${_card + 1}/${AskCard.all.length}', style: const TextStyle(color: Palette.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(card.example,
                      style: const TextStyle(color: Palette.pink, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35)),
                  const SizedBox(height: 6),
                  Text(card.why, style: const TextStyle(color: Palette.textPrimary, fontSize: 13.5, height: 1.4)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _card = (_card + 1) % AskCard.all.length),
                      icon: const Icon(Icons.skip_next, color: Palette.pink),
                      label: const Text('Another question',
                          style: TextStyle(color: Palette.pink, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label('2. WHICH ONE IS THE LIE?'),
            Row(
              children: <Widget>[
                for (var i = 1; i <= 3; i++) ...<Widget>[
                  if (i > 1) const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: Text('#$i'),
                      selected: _guess == i,
                      onSelected: (_) => setState(() {
                        _guess = i;
                        _result = null;
                      }),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _label('3. WHAT GAVE IT AWAY?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final c in LieClue.values)
                  ChoiceChip(
                    label: Text('${c.emoji} ${c.label}'),
                    selected: _clue == c,
                    onSelected: (_) => setState(() => _clue = c),
                  ),
              ],
            ),
            if (_clue != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_clue!.hint, style: const TextStyle(color: Palette.textMuted, fontSize: 12.5)),
              ),
            const SizedBox(height: 16),
            _label('4. HOW SURE ARE YOU?'),
            Row(
              children: <Widget>[
                for (var i = 0; i < 3; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(_confidenceLabels[i]),
                      selected: _confidence == i,
                      onSelected: (_) => setState(() => _confidence = i),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _label(_ready ? '5. NOW ASK THEM: WHICH ONE WAS THE LIE?' : '5. Answer 2–4 first, then ask them'),
            Row(
              children: <Widget>[
                for (var i = 1; i <= 3; i++) ...<Widget>[
                  if (i > 1) const SizedBox(width: 10),
                  Expanded(
                    child: ChunkyButton(
                      label: 'It was #$i',
                      color: Palette.pink,
                      height: 46,
                      onPressed: _ready ? () => _reveal(i) : null,
                    ),
                  ),
                ],
              ],
            ),
            if (_result != null) ...<Widget>[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.flag,
                color: _lastCorrect == true ? Palette.green : Palette.orange,
                text: _result!,
              ),
            ],
            const SizedBox(height: 22),
            RealLifeInsights(game: game, showFriends: true),
          ],
        ),
      ),
    );
  }
}

/// Your real-life record: overall vs chance, which clues work, and calibration.
class RealLifeInsights extends StatelessWidget {
  const RealLifeInsights({super.key, required this.game, this.showFriends = false});
  final GameState game;
  final bool showFriends;

  static String _pct(List<int> s) => s[0] == 0 ? '–' : '${(100 * s[1] / s[0]).round()}%';

  /// Advice from the clue stats, or null if there's not enough data yet.
  static String? takeaway(GameState game) {
    final tried = game.clueStats.entries.where((e) => e.value[0] >= 3).toList();
    if (tried.isEmpty) return null;
    double rate(List<int> s) => s[1] / s[0];
    tried.sort((a, b) => rate(b.value).compareTo(rate(a.value)));
    final best = tried.first;
    final worst = tried.last;
    final parts = <String>['Your best clue so far: ${best.key.emoji} ${best.key.label} (${_pct(best.value)}).'];
    if (tried.length > 1 && rate(worst.value) < 0.4) {
      parts.add('Stop trusting ${worst.key.label.toLowerCase()} (${_pct(worst.value)}).');
    }
    if (!best.key.verbal) {
      parts.add('Check that over more rounds; in studies, body and face clues are the least reliable.');
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final stats = game.realLifeStats;
    final total = stats.values.fold<int>(0, (a, s) => a + s[0]);
    final right = stats.values.fold<int>(0, (a, s) => a + s[1]);
    final advice = takeaway(game);
    final clues = LieClue.values.where((c) => (game.clueStats[c]?[0] ?? 0) > 0).toList()
      ..sort((a, b) => game.clueStats[b]![0].compareTo(game.clueStats[a]![0]));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('YOUR REAL-LIFE RECORD',
              style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          if (total == 0)
            const Text(
              'No rounds yet. Guessing blind gets about 33%. Your goal is to beat that, and to find out which clues '
              'actually work for you.',
              style: TextStyle(color: Palette.textMuted, fontSize: 14, height: 1.4),
            )
          else ...<Widget>[
            Text(
              '$right of $total caught (${(100 * right / total).round()}%)  ·  chance is 33%',
              style: TextStyle(
                color: right / total > 0.4 ? Palette.green : Palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            _Bar(value: right / total, color: right / total > 0.4 ? Palette.green : Palette.orange),
            if (clues.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              const Text('WHEN YOU WENT BY…',
                  style: TextStyle(color: Palette.pink, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 6),
              for (final c in clues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('${c.emoji} ${c.label}',
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 14.5)),
                      ),
                      Text(
                        '${game.clueStats[c]![1]}/${game.clueStats[c]![0]}  ${_pct(game.clueStats[c]!)}',
                        style: TextStyle(
                          color: game.clueStats[c]![1] / game.clueStats[c]![0] > 0.4 ? Palette.green : Palette.orange,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (game.confidenceStats.any((s) => s[0] > 0)) ...<Widget>[
              const SizedBox(height: 10),
              const Text('WHEN YOU FELT…',
                  style: TextStyle(color: Palette.pink, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 6),
              for (var i = 0; i < 3; i++)
                if (game.confidenceStats[i][0] > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(_RealLifeScreenState._confidenceLabels[i],
                              style: const TextStyle(color: Palette.textPrimary, fontSize: 14.5)),
                        ),
                        Text(
                          '${game.confidenceStats[i][1]}/${game.confidenceStats[i][0]}  ${_pct(game.confidenceStats[i])}',
                          style: const TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
              const Text(
                'Good lie-catchers are right more often when they feel certain. If "Certain" isn\'t beating '
                '"Guessing", your gut isn\'t calibrated yet.',
                style: TextStyle(color: Palette.textMuted, fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 10),
            InfoBanner(
              icon: Icons.lightbulb,
              color: Palette.gold,
              text: advice ?? 'Play 3+ rounds with the same clue to see if it works for you.',
            ),
            if (showFriends) ...<Widget>[
              const SizedBox(height: 14),
              const Text('BY FRIEND',
                  style: TextStyle(color: Palette.pink, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: 6),
              for (final e in (stats.entries.toList()..sort((a, b) => b.value[0].compareTo(a.value[0]))))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(e.key, style: const TextStyle(color: Palette.textPrimary, fontSize: 15))),
                      Text('${e.value[1]}/${e.value[0]}',
                          style: const TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// What the research says actually works for catching lies.
class LieScienceScreen extends StatelessWidget {
  const LieScienceScreen({super.key});

  static const List<(String, String, String)> _sections = <(String, String, String)>[
    ('🎲', 'Most people are near a coin flip',
        'Across hundreds of studies, people catch lies about 54% of the time. Police, judges and customs officers do '
            'about the same. Being "good at reading people" usually means being confident, not accurate.'),
    ('🤥', 'There is no Pinocchio\'s nose',
        'No single behavior means lying. Looking away, fidgeting and touching the face happen to honest people all the '
            'time, especially when they feel accused. Nervous is not the same as lying.'),
    ('👂', 'Words beat body language',
        'The clues that hold up best in research are in what people say: how much detail, whether it can be checked, '
            'and whether the story holds together. Body language gives tiny, unreliable signals.'),
    ('🧠', 'Make lying hard work',
        'Lying takes more mental effort than telling the truth. Unexpected questions, asking for more detail, or '
            'telling the story backwards add load. A liar starts to stall, stay vague or contradict themselves; '
            'a truth-teller just remembers more.'),
    ('🧾', 'Check what can be checked',
        'Truthful people tend to give details someone could verify: names, places, times, receipts, messages. Liars '
            'often give lots of detail that can\'t be checked ("I was alone", "some guy").'),
    ('🤫', 'Hold back what you know',
        'If you know a fact, don\'t reveal it. Ask open questions first and let them commit to a story, then compare. '
            'This is called Strategic Use of Evidence, and it has some of the strongest results of any method.'),
    ('📏', 'Baseline, then clusters',
        'Compare people to how THEY normally act, not to an average person. One odd moment means little; several '
            'changes at the same moment, on the same topic, mean more.'),
    ('🎯', 'Feedback is how you improve',
        'Without finding out if you were right, your skill doesn\'t improve; you just get more confident. Always '
            'commit to a guess before you learn the answer, and track what you went on. That\'s what Two Truths & '
            'a Lie is for.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Palette.textMuted),
                ),
                const Expanded(
                  child: Text('What Actually Works',
                      style: TextStyle(color: Palette.textPrimary, fontSize: 23, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final s in _sections)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Palette.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(s.$1, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(s.$2,
                              style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(s.$3, style: const TextStyle(color: Palette.textPrimary, fontSize: 14, height: 1.45)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PROGRESS CHART: daily accuracy, last 14 days
// ════════════════════════════════════════════════════════════════════════════

class ProgressChart extends StatefulWidget {
  const ProgressChart({super.key, required this.game});
  final GameState game;

  @override
  State<ProgressChart> createState() => _ProgressChartState();
}

class _ProgressChartState extends State<ProgressChart> {
  static const int days = 14;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final today = dayIndex();
    final log = widget.game.dayLog;
    final points = <({int day, int answered, int correct})>[
      for (var d = today - days + 1; d <= today; d++)
        (day: d, answered: log[d]?[0] ?? 0, correct: log[d]?[1] ?? 0),
    ];
    double? pct(Iterable<({int day, int answered, int correct})> pts) {
      final a = pts.fold<int>(0, (s, p) => s + p.answered);
      if (a == 0) return null;
      return pts.fold<int>(0, (s, p) => s + p.correct) / a;
    }

    final thisWeek = pct(points.skip(7));
    final lastWeek = pct(points.take(7));
    String fmt(double? v) => v == null ? '–' : '${(v * 100).round()}%';
    final selected = _selected == null ? null : points[_selected!];
    const barColor = Palette.blue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _MiniStat(label: 'Last 7 days', value: fmt(thisWeek))),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat(label: 'Week before', value: fmt(lastWeek))),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 18,
          child: Text(
            selected == null
                ? 'Daily accuracy. Tap a bar for details.'
                : selected.answered == 0
                    ? '${today - selected.day == 0 ? 'Today' : '${today - selected.day} days ago'}: no answers'
                    : '${today - selected.day == 0 ? 'Today' : '${today - selected.day} days ago'}: '
                        '${selected.correct}/${selected.answered} correct (${(100 * selected.correct / selected.answered).round()}%)',
            style: const TextStyle(color: Palette.textMuted, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var i = 0; i < points.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _selected = _selected == i ? null : i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1), // 2px gap between bars
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          Container(
                            height: points[i].answered == 0
                                ? 3
                                : math.max(4, 100 * points[i].correct / points[i].answered).toDouble(),
                            decoration: BoxDecoration(
                              color: points[i].answered == 0
                                  ? Palette.border
                                  : (_selected == i ? barColor : barColor.withAlpha(_selected == null ? 255 : 140)),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: Palette.border),
        const SizedBox(height: 4),
        const Row(
          children: <Widget>[
            Text('2 weeks ago', style: TextStyle(color: Palette.textMuted, fontSize: 11)),
            Spacer(),
            Text('today', style: TextStyle(color: Palette.textMuted, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CARD COUNTING TRAINER (Hi-Lo)
// ════════════════════════════════════════════════════════════════════════════

class PlayingCard {
  const PlayingCard(this.rank, this.suit);
  final String rank;
  final String suit;

  bool get red => suit == '♥' || suit == '♦';
  int get hiLo => hiLoValue(rank);
}

/// Hi-Lo: 2–6 = +1, 7–9 = 0, 10s, faces and aces = −1.
int hiLoValue(String rank) => switch (rank) {
      '2' || '3' || '4' || '5' || '6' => 1,
      '7' || '8' || '9' => 0,
      _ => -1,
    };

List<PlayingCard> shuffledDeck(math.Random rng) {
  const ranks = <String>['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
  const suits = <String>['♠', '♥', '♦', '♣'];
  return <PlayingCard>[
    for (final s in suits)
      for (final r in ranks) PlayingCard(r, s),
  ]..shuffle(rng);
}

class CardCountScreen extends StatefulWidget {
  const CardCountScreen({super.key, required this.game});
  final GameState game;

  @override
  State<CardCountScreen> createState() => _CardCountScreenState();
}

class _CardCountScreenState extends State<CardCountScreen> with DrillSession<CardCountScreen> {
  List<PlayingCard> _cards = <PlayingCard>[];
  int _shown = 0;
  Timer? _dealer;
  String _digits = '';
  bool _negative = false;
  int _answer = 0;

  @override
  GameState get game => widget.game;
  @override
  MemoryDrill get drill => MemoryDrill.cards;
  @override
  int get totalTrials => 3;

  int get _cardCount => math.min(52, 8 + 4 * level);
  Duration get _speed => Duration(milliseconds: math.max(450, 1600 - 110 * (level - 1)));
  bool get _showValues => level <= 2;
  int get _trueCount => _cards.fold<int>(0, (sum, c) => sum + c.hiLo);

  @override
  void initState() {
    super.initState();
    initSession();
  }

  @override
  void dispose() {
    _dealer?.cancel();
    super.dispose();
  }

  void _startTrial() {
    _dealer?.cancel();
    setState(() {
      _cards = shuffledDeck(rng).take(_cardCount).toList();
      _shown = 0;
      _digits = '';
      _negative = false;
      phase = DrillPhase.study;
    });
    _dealer = Timer.periodic(_speed, (_) {
      if (!mounted) return;
      if (_shown + 1 >= _cards.length) {
        _dealer?.cancel();
        setState(() => phase = DrillPhase.recall);
      } else {
        setState(() => _shown++);
      }
    });
  }

  void _press(String key) {
    if (phase != DrillPhase.recall) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (key == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        } else {
          _negative = false;
        }
      } else if (key == '±') {
        _negative = !_negative;
      } else if (key != 'ok' && _digits.length < 2) {
        _digits += key;
      }
    });
  }

  void _submit() {
    if (_digits.isEmpty) return;
    final value = int.parse(_digits) * (_negative ? -1 : 1);
    _answer = value;
    final diff = (value - _trueCount).abs();
    final passed = diff == 0;
    finishTrial(passed: passed, levelDelta: passed ? 1 : (diff > 2 ? -1 : 0), ip: passed ? 3 + level : 0);
  }

  String get _entryText => _digits.isEmpty ? (_negative ? '−' : '?') : '${_negative ? '−' : (_digits == '0' ? '' : '+')}$_digits';

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
            tip: 'Keep ONE number in your head: +1 for 2–6, 0 for 7–9, −1 for 10s, faces and aces. '
                'Start at 0. Level $level: $_cardCount cards, one every ${(_speed.inMilliseconds / 1000).toStringAsFixed(1)}s.',
            onStart: _startTrial,
            onLearn: openLesson,
          ),
        DrillPhase.study || DrillPhase.blank => _buildDeal(),
        DrillPhase.recall => _buildRecall(),
        DrillPhase.feedback => DrillFeedback(
            passed: lastPassed,
            headline: lastPassed ? 'Count is right: ${_signed(_trueCount)}' : 'The count was ${_signed(_trueCount)}',
            levelText: '${lastPassed ? '' : 'You said ${_signed(_answer)}. '}$levelChangeText',
            nextLabel: trial + 1 >= totalTrials ? 'Finish' : 'Deal again',
            onNext: () => nextTrial(_startTrial),
            child: _buildBreakdown(),
          ),
        DrillPhase.summary => buildSummary(_startTrial),
      },
    );
  }

  static String _signed(int v) => v > 0 ? '+$v' : (v < 0 ? '−${v.abs()}' : '0');

  Widget _buildDeal() {
    final card = _cards[_shown];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: <Widget>[
          Text(
            'CARD ${_shown + 1} OF ${_cards.length}',
            style: TextStyle(color: drill.color, fontWeight: FontWeight.w900, letterSpacing: 1.4),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_shown + 1) / _cards.length,
              minHeight: 6,
              backgroundColor: Palette.surfaceHigh,
              valueColor: AlwaysStoppedAnimation<Color>(drill.color),
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: _CardFace(key: ValueKey<int>(_shown), card: card),
          ),
          const SizedBox(height: 16),
          if (_showValues)
            Text(
              card.hiLo > 0 ? '+1' : (card.hiLo < 0 ? '−1' : '0'),
              style: TextStyle(
                color: card.hiLo > 0 ? Palette.green : (card.hiLo < 0 ? Palette.red : Palette.textMuted),
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            )
          else
            const Text('Keep counting…', style: TextStyle(color: Palette.textMuted, fontSize: 16)),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildRecall() {
    const keys = <String>['7', '8', '9', '4', '5', '6', '1', '2', '3', '±', '0', 'del'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: <Widget>[
          const Text("WHAT'S THE RUNNING COUNT?",
              style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          const SizedBox(height: 14),
          Text(_entryText, style: const TextStyle(color: Palette.textPrimary, fontSize: 56, fontWeight: FontWeight.w900)),
          const Text('Tap ± for a negative count.', style: TextStyle(color: Palette.textMuted, fontSize: 13)),
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
          ChunkyButton(label: 'Check count', color: drill.color, onPressed: _digits.isEmpty ? null : _submit),
        ],
      ),
    );
  }

  Widget _buildBreakdown() {
    final totals = <int>[];
    var running = 0;
    for (final c in _cards) {
      running += c.hiLo;
      totals.add(running);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text('EVERY CARD, WITH THE RUNNING COUNT',
            style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (var i = 0; i < _cards.length; i++)
              Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Palette.border),
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      '${_cards[i].rank}${_cards[i].suit}',
                      style: TextStyle(
                        color: _cards[i].red ? const Color(0xFFFF7A7A) : Palette.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(_signed(totals[i]), style: const TextStyle(color: Palette.textMuted, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const InfoBanner(
          icon: Icons.tips_and_updates,
          color: Palette.red,
          text: 'Pro trick: cancel pairs. A 5 and a king together are 0, so you can skip them.',
        ),
      ],
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({super.key, required this.card});
  final PlayingCard card;

  @override
  Widget build(BuildContext context) {
    final color = card.red ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A);
    final corner = TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900, height: 1);
    return Container(
      width: 160,
      height: 224,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 12,
            left: 14,
            child: Column(children: <Widget>[Text(card.rank, style: corner), Text(card.suit, style: corner)]),
          ),
          Center(child: Text(card.suit, style: TextStyle(color: color, fontSize: 80))),
          Positioned(
            bottom: 12,
            right: 14,
            child: RotatedBox(
              quarterTurns: 2,
              child: Column(children: <Widget>[Text(card.rank, style: corner), Text(card.suit, style: corner)]),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BLACKJACK TABLE: play with IP (play money only)
// ════════════════════════════════════════════════════════════════════════════

class Blackjack {
  Blackjack._();

  static const int minBet = 5;
  static const int maxBet = 500;
  static const int decks = 4;

  static int cardValue(String rank) => switch (rank) {
        'A' => 1,
        'J' || 'Q' || 'K' || '10' => 10,
        _ => int.parse(rank),
      };

  /// Best total and whether an ace is counted as 11.
  static ({int total, bool soft}) handValue(List<PlayingCard> hand) {
    var total = 0;
    var aces = 0;
    for (final c in hand) {
      total += cardValue(c.rank);
      if (c.rank == 'A') aces++;
    }
    if (aces > 0 && total + 10 <= 21) return (total: total + 10, soft: true);
    return (total: total, soft: false);
  }

  static bool isBlackjack(List<PlayingCard> hand) => hand.length == 2 && handValue(hand).total == 21;

  /// Basic strategy (4+ decks, dealer stands on soft 17, no splits).
  /// Returns 'Hit', 'Stand' or 'Double'.
  static String advice(List<PlayingCard> hand, PlayingCard dealerUp, {required bool canDouble}) {
    final v = handValue(hand);
    final d = dealerUp.rank == 'A' ? 11 : cardValue(dealerUp.rank);
    String dbl(String otherwise) => canDouble ? 'Double' : otherwise;
    if (v.soft) {
      final t = v.total;
      if (t >= 19) return 'Stand';
      if (t == 18) {
        if (d >= 3 && d <= 6) return dbl('Stand');
        if (d == 2 || d == 7 || d == 8) return 'Stand';
        return 'Hit';
      }
      if (t == 17) return (d >= 3 && d <= 6) ? dbl('Hit') : 'Hit';
      if (t == 15 || t == 16) return (d >= 4 && d <= 6) ? dbl('Hit') : 'Hit';
      return (d == 5 || d == 6) ? dbl('Hit') : 'Hit'; // soft 13–14
    }
    final t = v.total;
    if (t >= 17) return 'Stand';
    if (t >= 13) return d <= 6 ? 'Stand' : 'Hit';
    if (t == 12) return (d >= 4 && d <= 6) ? 'Stand' : 'Hit';
    if (t == 11) return d <= 10 ? dbl('Hit') : 'Hit';
    if (t == 10) return d <= 9 ? dbl('Hit') : 'Hit';
    if (t == 9) return (d >= 3 && d <= 6) ? dbl('Hit') : 'Hit';
    return 'Hit';
  }
}

enum _TablePhase { betting, player, dealer, settled }

class BlackjackScreen extends StatefulWidget {
  const BlackjackScreen({super.key, required this.game});
  final GameState game;

  @override
  State<BlackjackScreen> createState() => _BlackjackScreenState();
}

class _BlackjackScreenState extends State<BlackjackScreen> {
  final math.Random _rng = math.Random();
  List<PlayingCard> _shoe = <PlayingCard>[];
  int _shoeSize = 0;
  int _runningCount = 0;
  final List<PlayingCard> _player = <PlayingCard>[];
  final List<PlayingCard> _dealer = <PlayingCard>[];
  bool _holeHidden = true;
  _TablePhase _phase = _TablePhase.betting;
  int _bet = 25;
  int _staked = 0;
  String _message = '';
  bool _coach = false;
  bool _countHelper = false;
  bool _justShuffled = false;
  int _strategyMoves = 0;
  int _strategyCorrect = 0;

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    _shuffle();
    _bet = _bet.clamp(Blackjack.minBet, math.max(Blackjack.minBet, game.insightPoints));
  }

  void _shuffle() {
    _shoe = <PlayingCard>[for (var i = 0; i < Blackjack.decks; i++) ...shuffledDeck(_rng)]..shuffle(_rng);
    _shoeSize = _shoe.length;
    _runningCount = 0;
    _justShuffled = true;
  }

  PlayingCard _draw({bool visible = true}) {
    final c = _shoe.removeLast();
    if (visible) _runningCount += c.hiLo;
    return c;
  }

  double get _decksLeft => math.max(0.5, _shoe.length / 52);
  double get _trueCount => _runningCount / _decksLeft;

  void _deal() {
    if (_bet < Blackjack.minBet || _bet > game.insightPoints) return;
    if (_shoe.length < _shoeSize * 0.25) {
      _shuffle();
    } else {
      _justShuffled = false;
    }
    game.placeBet(_bet);
    _staked = _bet;
    _player
      ..clear()
      ..add(_draw())
      ..add(_draw());
    _dealer
      ..clear()
      ..add(_draw())
      ..add(_draw(visible: false));
    _holeHidden = true;
    _message = '';
    HapticFeedback.mediumImpact();

    final playerBj = Blackjack.isBlackjack(_player);
    final dealerBj = Blackjack.isBlackjack(_dealer);
    if (playerBj || dealerBj) {
      _revealHole();
      if (playerBj && dealerBj) {
        _settle(_staked, 'Both blackjack. Push.');
      } else if (playerBj) {
        _settle(_staked + (_staked * 3) ~/ 2, 'Blackjack! Pays 3 to 2: +${(_staked * 3) ~/ 2} IP on your $_staked bet.');
      } else {
        _settle(0, 'Dealer has blackjack.');
      }
      return;
    }
    setState(() => _phase = _TablePhase.player);
  }

  void _revealHole() {
    if (_holeHidden) {
      _holeHidden = false;
      _runningCount += _dealer[1].hiLo;
    }
  }

  void _trackStrategy(String move) {
    final best = Blackjack.advice(_player, _dealer.first, canDouble: _canDouble);
    _strategyMoves++;
    if (best == move) _strategyCorrect++;
  }

  bool get _canDouble => _player.length == 2 && game.insightPoints >= _staked;

  void _hit() {
    _trackStrategy('Hit');
    HapticFeedback.selectionClick();
    setState(() => _player.add(_draw()));
    if (Blackjack.handValue(_player).total > 21) {
      _revealHole();
      _settle(0, 'Bust. You went over 21.');
    }
  }

  void _stand() {
    _trackStrategy('Stand');
    _playDealer();
  }

  void _double() {
    if (!_canDouble) return;
    _trackStrategy('Double');
    game.placeBet(_staked);
    _staked *= 2;
    setState(() => _player.add(_draw()));
    if (Blackjack.handValue(_player).total > 21) {
      _revealHole();
      _settle(0, 'Doubled and busted.');
      return;
    }
    _playDealer();
  }

  Future<void> _playDealer() async {
    setState(() {
      _phase = _TablePhase.dealer;
      _revealHole();
    });
    while (Blackjack.handValue(_dealer).total < 17) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      setState(() => _dealer.add(_draw()));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final p = Blackjack.handValue(_player).total;
    final d = Blackjack.handValue(_dealer).total;
    if (d > 21) {
      _settle(_staked * 2, 'Dealer busts with $d. You win!');
    } else if (p > d) {
      _settle(_staked * 2, '$p beats $d. You win!');
    } else if (p == d) {
      _settle(_staked, 'Push at $p. Bet returned.');
    } else {
      _settle(0, 'Dealer wins, $d to $p.');
    }
  }

  void _settle(int returned, String message) {
    game.settleBlackjack(staked: _staked, returned: returned);
    if (returned > _staked) {
      HapticFeedback.mediumImpact();
    } else if (returned < _staked) {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _message = message;
      _phase = _TablePhase.settled;
      _bet = _bet.clamp(Blackjack.minBet, math.max(Blackjack.minBet, math.min(Blackjack.maxBet, game.insightPoints)));
    });
  }

  void _addChip(int amount) {
    HapticFeedback.selectionClick();
    setState(() => _bet = math.min(math.min(Blackjack.maxBet, game.insightPoints), _bet + amount));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: _phase == _TablePhase.betting || _phase == _TablePhase.settled,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              backgroundColor: Palette.surfaceHigh,
              content: Text('Finish the hand first.', style: TextStyle(color: Palette.textPrimary)),
            ));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E3B2E),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              _buildTopBar(),
              Expanded(child: _buildTable()),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final stats = game.blackjackStats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
          const Expanded(
            child: Text('BLACKJACK',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
          StatPill(emoji: '💡', label: '${game.insightPoints} IP', color: Palette.gold, tooltip: 'Your bankroll'),
          IconButton(
            tooltip: 'Table info',
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                backgroundColor: Palette.surface,
                title: const Text('Table rules', style: TextStyle(color: Palette.textPrimary)),
                content: Text(
                  '4-deck shoe, reshuffled when about 3/4 is used. Dealer stands on all 17s. Blackjack pays 3:2. '
                  'Double on your first two cards. No splitting.\n\n'
                  'Bets: ${Blackjack.minBet}–${Blackjack.maxBet} IP. Play money only. Out of IP? Train to earn more.\n\n'
                  'Your record: ${stats[0]} hands · net ${stats[1] >= 0 ? '+' : ''}${stats[1]} IP · biggest win ${stats[2]} IP'
                  '${_strategyMoves > 0 ? '\nThis session: ${(100 * _strategyCorrect / _strategyMoves).round()}% basic-strategy moves' : ''}',
                  style: const TextStyle(color: Palette.textMuted, height: 1.4),
                ),
                actions: <Widget>[
                  TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _handRow(List<PlayingCard> hand, {bool hideSecond = false}) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        for (var i = 0; i < hand.length; i++) _MiniCard(card: hand[i], hidden: hideSecond && i == 1),
      ],
    );
  }

  String _totalText(List<PlayingCard> hand) {
    final v = Blackjack.handValue(hand);
    return v.soft && v.total < 21 ? 'soft ${v.total}' : '${v.total}';
  }

  Widget _buildTable() {
    if (_player.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            game.insightPoints < Blackjack.minBet
                ? 'You\'re out of IP. Earn more in Cold Reading, Practice or the Memory Gym, then come back.'
                : 'Place your bet and tap Deal.\n\nTip: when the count is high, bet more.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
          ),
        ),
      );
    }
    final hideHole = _holeHidden;
    final dealerShown = hideHole ? <PlayingCard>[_dealer.first] : _dealer;
    final advice = _phase == _TablePhase.player ? Blackjack.advice(_player, _dealer.first, canDouble: _canDouble) : null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: <Widget>[
        Text('DEALER · ${_totalText(dealerShown)}${hideHole ? ' + ?' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        _handRow(_dealer, hideSecond: hideHole),
        const SizedBox(height: 22),
        if (_message.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Text(_message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        if (_message.isEmpty && _justShuffled && _phase == _TablePhase.player)
          const Text('Fresh shoe: the count starts at 0.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 22),
        _handRow(_player),
        const SizedBox(height: 8),
        Text('YOU · ${_totalText(_player)} · bet $_staked IP',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        if (_coach && advice != null) ...<Widget>[
          const SizedBox(height: 12),
          InfoBanner(icon: Icons.school, color: Palette.gold, text: 'Coach: basic strategy says $advice.'),
        ],
        if (_countHelper) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'Running count ${_runningCount >= 0 ? '+' : ''}$_runningCount · true count ${_trueCount.toStringAsFixed(1)} · '
            '${_decksLeft.toStringAsFixed(1)} decks left',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _buildControls() {
    final toggles = Row(
      children: <Widget>[
        Expanded(
          child: SwitchListTile(
            dense: true,
            value: _coach,
            onChanged: (v) => setState(() => _coach = v),
            title: const Text('Coach', style: TextStyle(color: Colors.white)),
          ),
        ),
        Expanded(
          child: SwitchListTile(
            dense: true,
            value: _countHelper,
            onChanged: (v) => setState(() => _countHelper = v),
            title: const Text('Show count', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
    final Widget actions;
    if (_phase == _TablePhase.player) {
      actions = Row(
        children: <Widget>[
          Expanded(child: ChunkyButton(label: 'Hit', color: Palette.green, height: 50, onPressed: _hit)),
          const SizedBox(width: 8),
          Expanded(child: ChunkyButton(label: 'Stand', color: Palette.red, height: 50, onPressed: _stand)),
          const SizedBox(width: 8),
          Expanded(
            child: ChunkyButton(label: 'Double', color: Palette.blue, height: 50, onPressed: _canDouble ? _double : null),
          ),
        ],
      );
    } else if (_phase == _TablePhase.dealer) {
      actions = const SizedBox(
        height: 55,
        child: Center(child: Text('Dealer is drawing…', style: TextStyle(color: Colors.white70, fontSize: 16))),
      );
    } else {
      final canAfford = game.insightPoints >= Blackjack.minBet;
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (final chip in <int>[5, 25, 100]) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: canAfford ? () => _addChip(chip) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: Text('+$chip'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: canAfford ? () => setState(() => _bet = Blackjack.minBet) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('Min'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ChunkyButton(
            label: canAfford ? 'Deal · bet $_bet IP' : 'Not enough IP',
            color: Palette.gold,
            textColor: const Color(0xFF1A1A1A),
            onPressed: canAfford && _bet <= game.insightPoints ? _deal : null,
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      color: const Color(0xFF0A2C22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[toggles, actions],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.card, this.hidden = false});
  final PlayingCard card;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    if (hidden) {
      return Container(
        width: 62,
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFF8E1B1B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: const Center(child: Text('?', style: TextStyle(color: Colors.white70, fontSize: 28, fontWeight: FontWeight.w900))),
      );
    }
    final color = card.red ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A);
    return Container(
      width: 62,
      height: 88,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const <BoxShadow>[BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(card.rank, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
          Expanded(child: Center(child: Text(card.suit, style: TextStyle(color: color, fontSize: 30)))),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  POKER SCHOOL: Texas Hold'em engine, opponents, drills
// ════════════════════════════════════════════════════════════════════════════

/// Cards are ints 0–51: rank = c ~/ 4 (0 = two … 12 = ace), suit = c % 4.
class Poker {
  Poker._();

  static const List<String> rankChars = <String>['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  static const List<String> suitChars = <String>['♠', '♥', '♦', '♣'];
  static const List<String> _single = <String>[
    'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Jack', 'Queen', 'King', 'Ace', //
  ];
  static const List<String> _plural = <String>[
    'Twos', 'Threes', 'Fours', 'Fives', 'Sixes', 'Sevens', 'Eights', 'Nines', 'Tens', 'Jacks', 'Queens', 'Kings', 'Aces', //
  ];
  static const List<String> categories = <String>[
    'High card', 'Pair', 'Two pair', 'Three of a kind', 'Straight', 'Flush', 'Full house', 'Four of a kind', //
    'Straight flush',
  ];

  static int rank(int c) => c ~/ 4;
  static int suit(int c) => c % 4;
  static int card(int rank, int suit) => rank * 4 + suit;
  static PlayingCard face(int c) => PlayingCard(rankChars[rank(c)], suitChars[suit(c)]);

  static const int _base = 1048576; // 16^5

  static int _score(int category, List<int> ranks) {
    var s = category;
    for (var i = 0; i < 5; i++) {
      s = s * 16 + (i < ranks.length ? ranks[i] + 1 : 0);
    }
    return s;
  }

  static int categoryOf(int score) => score ~/ _base;

  static int _kicker(int score, int i) {
    var v = score;
    for (var n = 0; n < 4 - i; n++) {
      v ~/= 16;
    }
    return v % 16 - 1;
  }

  /// Top card of the best straight in [ranks], or -1. A-2-3-4-5 counts (five high).
  static int _straightHigh(Set<int> ranks) {
    for (var h = 12; h >= 4; h--) {
      if (ranks.contains(h) &&
          ranks.contains(h - 1) &&
          ranks.contains(h - 2) &&
          ranks.contains(h - 3) &&
          ranks.contains(h - 4)) {
        return h;
      }
    }
    if (ranks.containsAll(<int>[12, 0, 1, 2, 3])) return 3;
    return -1;
  }

  /// The best 5-card hand in 5–7 cards, as a score: higher wins, equal ties.
  static int evaluate(List<int> cards) {
    final counts = List<int>.filled(13, 0);
    final suits = List<int>.filled(4, 0);
    for (final c in cards) {
      counts[rank(c)]++;
      suits[suit(c)]++;
    }
    final flushSuit = suits.indexWhere((n) => n >= 5);
    if (flushSuit >= 0) {
      final sf = _straightHigh(cards.where((c) => suit(c) == flushSuit).map(rank).toSet());
      if (sf >= 0) return _score(8, <int>[sf]);
    }
    final desc = <int>[for (var r = 12; r >= 0; r--) r];
    final quads = desc.where((r) => counts[r] == 4).toList();
    final trips = desc.where((r) => counts[r] == 3).toList();
    final pairs = desc.where((r) => counts[r] == 2).toList();
    final present = desc.where((r) => counts[r] > 0).toList();
    if (quads.isNotEmpty) {
      final q = quads.first;
      return _score(7, <int>[q, present.firstWhere((r) => r != q)]);
    }
    if (trips.isNotEmpty && (trips.length > 1 || pairs.isNotEmpty)) {
      final t = trips.first;
      final p = <int>[...trips.skip(1), ...pairs].reduce(math.max);
      return _score(6, <int>[t, p]);
    }
    if (flushSuit >= 0) {
      final fr = cards.where((c) => suit(c) == flushSuit).map(rank).toList()..sort((a, b) => b.compareTo(a));
      return _score(5, fr.take(5).toList());
    }
    final st = _straightHigh(present.toSet());
    if (st >= 0) return _score(4, <int>[st]);
    if (trips.isNotEmpty) {
      final t = trips.first;
      return _score(3, <int>[t, ...present.where((r) => r != t).take(2)]);
    }
    if (pairs.length >= 2) {
      final a = pairs[0];
      final b = pairs[1];
      return _score(2, <int>[a, b, present.firstWhere((r) => r != a && r != b)]);
    }
    if (pairs.length == 1) {
      final p = pairs.first;
      return _score(1, <int>[p, ...present.where((r) => r != p).take(3)]);
    }
    return _score(0, present.take(5).toList());
  }

  static String describe(int score) {
    final k0 = _kicker(score, 0);
    final k1 = _kicker(score, 1);
    return switch (categoryOf(score)) {
      8 => k0 == 12 ? 'Royal flush' : 'Straight flush, ${_single[k0]} high',
      7 => 'Four ${_plural[k0]}',
      6 => '${_plural[k0]} full of ${_plural[k1]}',
      5 => 'Flush, ${_single[k0]} high',
      4 => 'Straight, ${_single[k0]} high',
      3 => 'Three ${_plural[k0]}',
      2 => 'Two pair, ${_plural[k0]} and ${_plural[k1]}',
      1 => 'Pair of ${_plural[k0]}',
      _ => '${_single[k0]} high',
    };
  }

  /// "Pocket Kings", "Ace-Queen suited", "Nine-Four offsuit".
  static String startingName(int a, int b) {
    final hi = math.max(rank(a), rank(b));
    final lo = math.min(rank(a), rank(b));
    if (hi == lo) return 'Pocket ${_plural[hi]}';
    return '${_single[hi]}-${_single[lo]} ${suit(a) == suit(b) ? 'suited' : 'offsuit'}';
  }

  /// A simple starting-hand guide. [late] means you act last (the button).
  static bool playable(int a, int b, {required bool late}) {
    final hi = math.max(rank(a), rank(b));
    final lo = math.min(rank(a), rank(b));
    final suited = suit(a) == suit(b);
    if (hi == lo) return late || lo >= 5; // 7-7 and up anywhere
    if (hi == 12) return lo >= 10 || (lo >= 9 && suited) || (late && (suited || lo >= 8));
    if (hi == 11) return (lo >= 10 && suited) || (late && lo >= 9);
    if (late && suited && hi - lo == 1 && lo >= 3) return true; // 6-5 suited and up
    if (late && hi == 10 && lo == 9) return true; // Q-J
    return false;
  }

  static String preflopTip(int a, int b, {required bool late}) {
    final hi = math.max(rank(a), rank(b));
    final lo = math.min(rank(a), rank(b));
    final suited = suit(a) == suit(b);
    final play = playable(a, b, late: late);
    final String why;
    if (hi == lo) {
      why = lo >= 5
          ? 'Pairs of sevens and up are strong from anywhere.'
          : (late
              ? 'Small pairs are fine when you act last: you\'re hoping to hit three of a kind.'
              : 'Small pairs from up front lose money: you rarely hit three of a kind, and you act first.');
    } else if (hi == 12) {
      why = play
          ? 'Big aces play anywhere; weaker aces only when you act last, ideally suited.'
          : 'A weak ace up front gets you in trouble against players holding better aces.';
    } else if (suited && hi - lo == 1) {
      why = play
          ? 'Suited connectors make straights and flushes, and they\'re worth it when you act last.'
          : 'Suited connectors are only worth it when you act last and they\'re 6-5 or higher.';
    } else {
      why = play
          ? 'Two high cards are worth playing, especially when you act last.'
          : 'Most hands are folds. Good players fold about 3 of every 4 starting hands.';
    }
    return '${startingName(a, b)}: ${play ? 'play it' : 'fold it'}${late ? ' on the button' : ' up front'}. $why';
  }

  /// Chance to beat one random hand (ties count half), by simulation.
  static double equity(List<int> hole, List<int> board, math.Random rng, {int trials = 300}) {
    final used = <int>{...hole, ...board};
    final deck = <int>[
      for (var c = 0; c < 52; c++)
        if (!used.contains(c)) c,
    ];
    final need = 2 + (5 - board.length);
    var total = 0.0;
    for (var t = 0; t < trials; t++) {
      for (var i = 0; i < need; i++) {
        final j = i + rng.nextInt(deck.length - i);
        final tmp = deck[i];
        deck[i] = deck[j];
        deck[j] = tmp;
      }
      final runout = <int>[...board, ...deck.sublist(2, need)];
      final me = evaluate(<int>[...hole, ...runout]);
      final them = evaluate(<int>[deck[0], deck[1], ...runout]);
      if (me > them) {
        total += 1;
      } else if (me == them) {
        total += 0.5;
      }
    }
    return total / trials;
  }

  /// Unseen cards that turn [cards] into a straight or better: (flush outs, straight outs).
  static (int, int) drawOuts(List<int> cards) {
    var flush = 0;
    var straight = 0;
    for (var c = 0; c < 52; c++) {
      if (cards.contains(c)) continue;
      final cat = categoryOf(evaluate(<int>[...cards, c]));
      if (cat == 5 || cat == 8) {
        flush++;
      } else if (cat == 4) {
        straight++;
      }
    }
    return (flush, straight);
  }
}

enum PokerStreet { preflop, flop, turn, river, done }

/// One heads-up No-Limit Hold'em hand. Seat 0 is you, seat 1 the opponent.
class HoldemHand {
  HoldemHand({
    required List<int> stacks,
    required this.button,
    required math.Random rng,
    this.smallBlind = 5,
    this.bigBlind = 10,
  })  : stacks = List<int>.of(stacks),
        startStacks = List<int>.of(stacks) {
    _deck = List<int>.generate(52, (i) => i)..shuffle(rng);
    holes = <List<int>>[
      <int>[_deal(), _deal()],
      <int>[_deal(), _deal()],
    ];
    _post(button, smallBlind);
    _post(1 - button, bigBlind);
    lastRaise = bigBlind;
    toAct = button;
  }

  /// The button posts the small blind, acts first before the flop and last after it.
  final int button;
  final int smallBlind;
  final int bigBlind;
  final List<int> stacks;
  final List<int> startStacks;
  late final List<int> _deck;
  int _next = 0;
  late final List<List<int>> holes;
  final List<int> board = <int>[];

  /// Chips each seat has put in on the current street.
  final List<int> committed = <int>[0, 0];
  final List<bool> _acted = <bool>[false, false];
  int pot = 0;
  int toAct = 0;
  int lastRaise = 0;
  PokerStreet street = PokerStreet.preflop;

  /// 0 = you, 1 = opponent, -1 = split. Set when the hand ends.
  int? winner;
  bool endedByFold = false;

  int _deal() => _deck[_next++];

  void _post(int seat, int amount) {
    final a = math.min(amount, stacks[seat]);
    stacks[seat] -= a;
    committed[seat] += a;
    pot += a;
  }

  bool get over => street == PokerStreet.done;
  int net(int seat) => stacks[seat] - startStacks[seat];
  int toCall(int seat) => math.max(0, committed[1 - seat] - committed[seat]);
  int callAmount(int seat) => math.min(toCall(seat), stacks[seat]);
  bool canRaise(int seat) => stacks[seat] > toCall(seat) && stacks[1 - seat] > 0;
  int maxRaiseTo(int seat) => committed[seat] + stacks[seat];
  int minRaiseTo(int seat) => math.min(committed[1 - seat] + math.max(lastRaise, bigBlind), maxRaiseTo(seat));

  void fold() {
    if (over) return;
    _end(1 - toAct, byFold: true);
  }

  void checkOrCall() {
    if (over) return;
    final p = toAct;
    final amount = callAmount(p);
    stacks[p] -= amount;
    committed[p] += amount;
    pot += amount;
    if (committed[p] < committed[1 - p]) {
      // All-in for less: the uncalled part goes back.
      final extra = committed[1 - p] - committed[p];
      committed[1 - p] -= extra;
      stacks[1 - p] += extra;
      pot -= extra;
    }
    _acted[p] = true;
    _advance();
  }

  void raiseTo(int total) {
    if (over || !canRaise(toAct)) {
      checkOrCall();
      return;
    }
    final p = toAct;
    final target = total.clamp(minRaiseTo(p), maxRaiseTo(p));
    final size = target - committed[1 - p];
    if (size > lastRaise) lastRaise = size;
    final add = target - committed[p];
    stacks[p] -= add;
    committed[p] = target;
    pot += add;
    _acted[p] = true;
    _acted[1 - p] = false;
    toAct = 1 - p;
  }

  bool _streetComplete() {
    if (committed[0] != committed[1] && stacks[0] > 0 && stacks[1] > 0) return false;
    for (var p = 0; p < 2; p++) {
      if (stacks[p] == 0 || _acted[p]) continue;
      if (stacks[1 - p] == 0 && committed[p] >= committed[1 - p]) continue;
      return false;
    }
    return true;
  }

  void _advance() {
    if (_streetComplete()) {
      _nextStreet();
    } else {
      toAct = 1 - toAct;
    }
  }

  void _nextStreet() {
    committed[0] = 0;
    committed[1] = 0;
    _acted[0] = false;
    _acted[1] = false;
    lastRaise = bigBlind;
    if (street == PokerStreet.river) {
      _showdown();
      return;
    }
    street = PokerStreet.values[street.index + 1];
    if (street == PokerStreet.flop) {
      board.addAll(<int>[_deal(), _deal(), _deal()]);
    } else {
      board.add(_deal());
    }
    toAct = 1 - button;
    if (stacks[0] == 0 || stacks[1] == 0) _nextStreet(); // nobody can bet: run it out
  }

  int score(int seat) => Poker.evaluate(<int>[...holes[seat], ...board]);

  void _showdown() {
    final a = score(0);
    final b = score(1);
    _end(a > b ? 0 : (b > a ? 1 : -1), byFold: false);
  }

  void _end(int w, {required bool byFold}) {
    winner = w;
    endedByFold = byFold;
    if (w == -1) {
      final half = pot ~/ 2;
      stacks[button] += half;
      stacks[1 - button] += pot - half;
    } else {
      stacks[w] += pot;
    }
    street = PokerStreet.done;
  }
}

enum PokerAct { fold, check, call, raise }

class BotChoice {
  const BotChoice(this.act, this.equity, {this.raiseTo = 0, this.bluff = false});
  final PokerAct act;
  final double equity;
  final int raiseTo;
  final bool bluff;
}

/// A table opponent with a playing style, a baseline and tells.
class PokerBot {
  const PokerBot({
    required this.name,
    required this.emoji,
    required this.style,
    required this.blurb,
    required this.tight,
    required this.aggression,
    required this.bluff,
    required this.baseline,
    required this.strongTell,
    required this.bluffTell,
    required this.tellMeaning,
    this.pronoun = 'he',
  });

  final String pronoun;

  final String name;
  final String emoji;
  final String style;
  final String blurb;

  /// Extra equity this bot wants before calling.
  final double tight;
  final double aggression;
  final double bluff;
  final String baseline;
  final String strongTell;
  final String bluffTell;
  final String tellMeaning;

  static const double tellReliability = 0.8;

  static const List<PokerBot> all = <PokerBot>[
    PokerBot(
      name: 'Rex',
      emoji: '🗿',
      style: 'Tight & honest',
      blurb: 'Plays few hands and rarely bluffs. When he bets big, believe him.',
      tight: 0.08,
      aggression: 0.45,
      bluff: 0.05,
      baseline: 'sits still with his arms folded',
      strongTell: 'reaches for his chips before it\'s his turn',
      bluffTell: 'rubs the back of his neck',
      tellMeaning: 'Rex reaching for chips early meant a strong hand; neck rubbing (pacifying) meant he was nervous about a bluff.',
    ),
    PokerBot(
      name: 'Lola',
      emoji: '💃',
      style: 'Loose & chatty',
      blurb: 'Plays lots of hands and bluffs often. She talks nonstop, until she doesn\'t.',
      pronoun: 'she',
      tight: -0.04,
      aggression: 0.7,
      bluff: 0.25,
      baseline: 'chats nonstop about her weekend',
      strongTell: 'laughs and talks even more',
      bluffTell: 'suddenly goes quiet and stares at the table',
      tellMeaning: 'Lola going quiet was a break from her chatty baseline: bluffing. Extra chatter meant she was comfortable and strong.',
    ),
    PokerBot(
      name: 'Vic',
      emoji: '🎭',
      style: 'The actor',
      blurb: 'Acts weak when he\'s strong and strong when he\'s weak. Learn to flip it.',
      tight: 0.02,
      aggression: 0.6,
      bluff: 0.18,
      baseline: 'watches the board with a calm, blank face',
      strongTell: 'sighs and shrugs like he\'s disappointed',
      bluffTell: 'stares you down and slams his chips in',
      tellMeaning: 'Vic acts the opposite of his hand: the sigh and shrug meant strong; the stare-down meant a bluff. "Strong means weak, weak means strong."',
    ),
  ];

  /// What the bot does at the table this action: its baseline, or a tell.
  String behavior({required bool strong, required bool bluffing, required math.Random rng}) {
    if (strong && rng.nextDouble() < tellReliability) return strongTell;
    if (bluffing && rng.nextDouble() < tellReliability) return bluffTell;
    if (!strong && !bluffing && rng.nextDouble() < 0.06) return rng.nextBool() ? strongTell : bluffTell;
    return baseline;
  }

  BotChoice decide(HoldemHand h, math.Random rng) {
    const me = 1;
    final e = Poker.equity(h.holes[me], h.board, rng, trials: 250);
    final toCall = h.toCall(me);
    int sized(double fraction) => h.committed[1 - me] + math.max(h.bigBlind, ((fraction * (h.pot + toCall)) / 5).round() * 5);
    if (toCall == 0) {
      if (h.canRaise(me) && e > 0.68 - aggression * 0.1 && rng.nextDouble() < 0.45 + aggression * 0.5) {
        return BotChoice(PokerAct.raise, e, raiseTo: sized(0.6));
      }
      if (h.canRaise(me) && h.street != PokerStreet.preflop && e < 0.4 && rng.nextDouble() < bluff) {
        return BotChoice(PokerAct.raise, e, raiseTo: sized(0.55), bluff: true);
      }
      return BotChoice(PokerAct.check, e);
    }
    final needed = toCall / (h.pot + toCall);
    if (h.canRaise(me) && e > 0.8 - aggression * 0.05 && rng.nextDouble() < aggression) {
      return BotChoice(PokerAct.raise, e, raiseTo: sized(0.8));
    }
    if (e >= needed + tight) return BotChoice(PokerAct.call, e);
    if (h.canRaise(me) && e < 0.4 && rng.nextDouble() < bluff * 0.4) {
      return BotChoice(PokerAct.raise, e, raiseTo: sized(0.7), bluff: true);
    }
    return BotChoice(PokerAct.fold, e);
  }
}

enum PokerDrill {
  handName('Name That Hand', 'Find the best 5-card hand in 7 cards.', '🏷️'),
  winner('Who Wins?', 'Two hands, one board. Who takes the pot?', '⚔️'),
  preflop('Play or Fold?', 'Which starting hands are worth playing?', '🚦'),
  outs('Count the Outs', 'How many cards complete your draw?', '🎯'),
  odds('Call or Fold?', 'Outs vs. pot odds: the math of a call.', '🧮');

  const PokerDrill(this.title, this.subtitle, this.emoji);
  final String title;
  final String subtitle;
  final String emoji;

  static const int length = 10;
}

class PokerQuestion {
  const PokerQuestion({
    required this.prompt,
    required this.options,
    required this.correct,
    required this.explain,
    this.yours = const <int>[],
    this.theirs = const <int>[],
    this.board = const <int>[],
  });

  final String prompt;
  final List<int> yours;
  final List<int> theirs;
  final List<int> board;
  final List<String> options;
  final int correct;
  final String explain;

  static List<int> _deal(math.Random rng, int n) => (List<int>.generate(52, (i) => i)..shuffle(rng)).take(n).toList();

  static PokerQuestion make(PokerDrill drill, math.Random rng) => switch (drill) {
        PokerDrill.handName => _handName(rng),
        PokerDrill.winner => _winner(rng),
        PokerDrill.preflop => _preflop(rng),
        PokerDrill.outs => _outs(rng),
        PokerDrill.odds => _odds(rng),
      };

  static PokerQuestion _handName(math.Random rng) {
    final target = rng.nextInt(8);
    var cards = _deal(rng, 7);
    for (var i = 0; i < 6000 && Poker.categoryOf(Poker.evaluate(cards)) != target; i++) {
      cards = _deal(rng, 7);
    }
    final score = Poker.evaluate(cards);
    final cat = Poker.categoryOf(score);
    final others = <int>[
      for (var c = 0; c < 8; c++)
        if (c != cat) c,
    ]..sort((a, b) => (a - cat).abs().compareTo((b - cat).abs()));
    final picks = <int>[cat, ...others.take(3)]..shuffle(rng);
    return PokerQuestion(
      prompt: 'What\'s your best hand? (Your 2 cards plus the board.)',
      yours: cards.sublist(0, 2),
      board: cards.sublist(2),
      options: <String>[for (final c in picks) Poker.categories[c]],
      correct: picks.indexOf(cat),
      explain: 'Best five cards: ${Poker.describe(score)}.',
    );
  }

  static PokerQuestion _winner(math.Random rng) {
    var cards = _deal(rng, 9);
    for (var i = 0; i < 60; i++) {
      final a = Poker.categoryOf(Poker.evaluate(<int>[...cards.sublist(0, 2), ...cards.sublist(4)]));
      final b = Poker.categoryOf(Poker.evaluate(cards.sublist(2)));
      if ((a - b).abs() <= 1) break;
      cards = _deal(rng, 9);
    }
    final you = cards.sublist(0, 2);
    final them = cards.sublist(2, 4);
    final board = cards.sublist(4);
    final a = Poker.evaluate(<int>[...you, ...board]);
    final b = Poker.evaluate(<int>[...them, ...board]);
    final sameType = Poker.categoryOf(a) == Poker.categoryOf(b);
    return PokerQuestion(
      prompt: 'Who wins the pot?',
      yours: you,
      theirs: them,
      board: board,
      options: const <String>['You win', 'They win', 'Split pot'],
      correct: a > b ? 0 : (b > a ? 1 : 2),
      explain: 'You: ${Poker.describe(a)}. Them: ${Poker.describe(b)}.'
          '${sameType && a != b ? ' Same type of hand, so the higher cards (the kickers) decide.' : ''}'
          '${a == b ? ' The best five cards are equal, so the pot is split.' : ''}',
    );
  }

  static PokerQuestion _preflop(math.Random rng) {
    final late = rng.nextBool();
    final want = rng.nextBool();
    var cards = _deal(rng, 2);
    for (var i = 0; i < 500 && Poker.playable(cards[0], cards[1], late: late) != want; i++) {
      cards = _deal(rng, 2);
    }
    final play = Poker.playable(cards[0], cards[1], late: late);
    return PokerQuestion(
      prompt: late
          ? 'You\'re on the button: you act last after the flop. Play this hand?'
          : 'You\'re first to act at a full table. Play this hand?',
      yours: cards,
      options: const <String>['Play it', 'Fold it'],
      correct: play ? 0 : 1,
      explain: Poker.preflopTip(cards[0], cards[1], late: late),
    );
  }

  static PokerQuestion _outs(math.Random rng) {
    const targets = <int>[4, 8, 9, 15];
    final target = targets[rng.nextInt(targets.length)];
    var cards = _deal(rng, 5);
    var outs = (0, 0);
    for (var i = 0; i < 20000; i++) {
      cards = _deal(rng, 5);
      if (Poker.categoryOf(Poker.evaluate(cards)) > 1) continue;
      outs = Poker.drawOuts(cards);
      if (outs.$1 + outs.$2 == target) break;
    }
    while (outs.$1 + outs.$2 == 0) {
      cards = _deal(rng, 5);
      if (Poker.categoryOf(Poker.evaluate(cards)) > 1) continue;
      outs = Poker.drawOuts(cards);
    }
    final total = outs.$1 + outs.$2;
    final pool = <int>{total, 2, 4, 6, 8, 9, 12, 15}.toList()..remove(total);
    pool.sort((a, b) => (a - total).abs().compareTo((b - total).abs()));
    final options = <int>[total, ...pool.take(3)]..shuffle(rng);
    final parts = <String>[
      if (outs.$1 > 0) '${outs.$1} make a flush',
      if (outs.$2 > 0) '${outs.$2} make a straight',
    ];
    return PokerQuestion(
      prompt: 'You\'re on the flop. How many cards make you a straight or better?',
      yours: cards.sublist(0, 2),
      board: cards.sublist(2),
      options: <String>[for (final o in options) '$o outs'],
      correct: options.indexOf(total),
      explain: '${parts.join(' and ')}: $total outs. Rule of 4 and 2: about ${total * 4}% to hit by the river, '
          '${total * 2}% on the next card.',
    );
  }

  static PokerQuestion _odds(math.Random rng) {
    const outsChoices = <int>[4, 8, 9, 12, 15];
    const fractions = <double>[0.33, 0.5, 0.75, 1.0];
    for (;;) {
      final outs = outsChoices[rng.nextInt(outsChoices.length)];
      final allIn = rng.nextBool();
      final pot = 40 + 10 * rng.nextInt(17);
      final bet = math.max(10, ((pot * fractions[rng.nextInt(fractions.length)]) / 5).round() * 5);
      final need = bet / (pot + 2 * bet);
      final have = math.min(0.6, outs * (allIn ? 4 : 2) / 100);
      if ((have - need).abs() < 0.04) continue;
      final call = have > need;
      return PokerQuestion(
        prompt: allIn
            ? 'Flop. The pot is $pot. Your opponent goes all-in for $bet. You have $outs outs. Call or fold?'
            : 'Turn. The pot is $pot. Your opponent bets $bet. You have $outs outs. Call or fold?',
        options: const <String>['Call', 'Fold'],
        correct: call ? 0 : 1,
        explain: 'You pay $bet to win a pot of ${pot + 2 * bet}, so you need $bet ÷ ${pot + 2 * bet} = '
            '${(need * 100).round()}%. With $outs outs you have about ${(have * 100).round()}% '
            '(×${allIn ? 4 : 2}). ${call ? 'You win more often than you need: call.' : 'Too expensive for your draw: fold.'}',
      );
    }
  }
}

class PokerLesson {
  const PokerLesson(this.emoji, this.title, this.pages);
  final String emoji;
  final String title;
  final List<LessonPage> pages;

  static const List<PokerLesson> all = <PokerLesson>[
    PokerLesson('🃏', 'How a Hand Works', <LessonPage>[
      LessonPage('The goal',
          'Texas Hold\'em: win chips by having the best 5-card hand at the end, or by getting everyone else to fold. Each player gets 2 private cards. Five shared cards (the board) come out in the middle. Your hand is the best 5 cards out of your 2 plus the 5 on the board.'),
      LessonPage('Blinds',
          'Before the cards, two players post forced bets: the small blind and the big blind. They move around the table each hand, so there\'s always something to win.',
          'Blinds 5/10: the player left of the dealer button puts in 5, the next player puts in 10.'),
      LessonPage('Four rounds of betting',
          'Preflop (after your 2 cards), the flop (3 board cards at once), the turn (a 4th card) and the river (the 5th). Each round, everyone still in gets a turn to act.'),
      LessonPage('Your options',
          'Check: pass, if nobody has bet. Bet: put chips in. Call: match a bet. Raise: bet more than the current bet. Fold: give up the hand and any chips you put in.',
          'Someone bets and you have nothing? Fold. Nobody bet and you\'re unsure? Check.'),
      LessonPage('Showdown',
          'If more than one player is left after the river, everyone shows their cards. Best 5-card hand wins the pot. Exactly equal hands split it.'),
    ]),
    PokerLesson('🏆', 'Hand Rankings', <LessonPage>[
      LessonPage('The top four',
          'Royal flush: A-K-Q-J-10 of one suit.\nStraight flush: five in a row, same suit.\nFour of a kind: four cards of one rank.\nFull house: three of a kind plus a pair.',
          'K♥ K♠ K♦ 4♣ 4♥ is "Kings full of Fours".'),
      LessonPage('The middle',
          'Flush: any five of one suit.\nStraight: five in a row, any suits (A-2-3-4-5 counts, and so does 10-J-Q-K-A).\nThree of a kind: three cards of one rank.',
          'Flush beats straight because it\'s harder to make.'),
      LessonPage('The bottom',
          'Two pair: two different pairs.\nPair: two cards of one rank.\nHigh card: nothing, so your highest card plays.'),
      LessonPage('Ties and kickers',
          'Same type of hand? Compare the highest cards that are part of it, then the rest (the "kickers"). Only your best five cards count, never a sixth.',
          'K♠ K♦ A♣ beats K♥ K♣ Q♦: same pair, but the ace kicker wins.'),
    ]),
    PokerLesson('🚦', 'Which Hands to Play', <LessonPage>[
      LessonPage('Fold most hands',
          'The fastest way to lose is playing too many hands. Good players fold about 3 of every 4 starting hands and wait.'),
      LessonPage('Strong from anywhere',
          'Pairs 7-7 and up. A-K and A-Q. A-J and K-Q if they\'re suited (same suit).'),
      LessonPage('Position is power',
          'Acting last is a huge edge: you see what everyone else does first. The dealer button acts last after the flop. Play more hands on the button and fewer when you act first.'),
      LessonPage('Hands to add when you act last',
          'Small pairs (hoping for three of a kind), suited aces, suited connectors like 8-7 suited, and K-J, Q-J.'),
    ]),
    PokerLesson('🎯', 'Outs & Odds', <LessonPage>[
      LessonPage('Outs',
          'An out is a card that makes your hand. Four hearts after the flop? There are 13 hearts and you can see 4, so 9 outs.'),
      LessonPage('Common draws',
          'Flush draw: 9 outs. Open-ended straight draw (like 7-8-9-10, needing a 6 or a J): 8 outs. Gutshot (like 7-8-10-J, needing a 9): 4 outs. Flush draw plus straight draw: about 15.'),
      LessonPage('Rule of 4 and 2',
          'Multiply your outs by 4 on the flop (two cards to come) or by 2 on the turn (one card to come). That\'s your rough chance in percent.',
          '9 outs on the turn ≈ 18%.'),
      LessonPage('Pot odds',
          'Compare the price to your chance. Divide what you have to call by the total pot after you call. If your chance is bigger, call.',
          'Pot 100, bet 50. You call 50 to win a pot of 200: you need 25%. With 18%, fold.'),
    ]),
    PokerLesson('👀', 'Reading Players', <LessonPage>[
      LessonPage('Baseline first',
          'Same skill as the Cold Reading course. Watch how each player acts in ordinary hands: how they hold chips, how much they talk, how they bet. A tell only means something as a change from that.'),
      LessonPage('Classic tells',
          'Reaching for chips before it\'s their turn often means strong. A chatty player going suddenly quiet can mean a bluff. Shaky hands while betting are usually excitement about a strong hand, not fear.'),
      LessonPage('Strong means weak',
          'Many players act the opposite of their hand: they sigh and shrug with a monster, and stare you down when bluffing. Once you know someone does this, their act becomes the tell.'),
      LessonPage('Betting beats body language',
          'How someone bets is the most reliable tell: what they do with strong and weak hands, how big they bet, when they slow down. At the table, watch the chips first.'),
    ]),
    PokerLesson('🎭', 'Bluffing & Home Games', <LessonPage>[
      LessonPage('When to bluff',
          'Bluff against one or two players, not five. Bluff when the board looks scary (three of a suit, four to a straight, a pair) and your betting tells a story that makes sense.'),
      LessonPage('Who not to bluff',
          'Players who call everything. Against them, only bet your good hands and let them pay you.'),
      LessonPage('Keep your sizes the same',
          'Bet the same size with bluffs and strong hands so your bet size isn\'t a tell. About half to three-quarters of the pot is normal.'),
      LessonPage('Playing with friends',
          'Agree on the rules first: blinds, starting chips, when it ends. Play for chips or something fun. Then watch who bluffs a lot and who only bets big hands. That\'s your edge.'),
    ]),
  ];
}

class PokerSchoolScreen extends StatefulWidget {
  const PokerSchoolScreen({super.key, required this.game});
  final GameState game;

  @override
  State<PokerSchoolScreen> createState() => _PokerSchoolScreenState();
}

class _PokerSchoolScreenState extends State<PokerSchoolScreen> {
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

  void _push(Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Text(text,
            style: const TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );

  Widget _tile({required String emoji, required String title, required String subtitle, String? trailing, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(color: Palette.textPrimary, fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(subtitle, style: const TextStyle(color: Palette.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
                if (trailing != null)
                  Text(trailing, style: const TextStyle(color: Palette.gold, fontWeight: FontWeight.w800)),
                const Icon(Icons.chevron_right, color: Palette.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = game.pokerStats;
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Palette.textMuted),
                ),
                const Expanded(
                  child: Text('Poker School',
                      style: TextStyle(color: Palette.textPrimary, fontSize: 23, fontWeight: FontWeight.w900)),
                ),
                StatPill(emoji: '💡', label: '${game.insightPoints} IP', color: Palette.blue, tooltip: 'Insight Points'),
              ],
            ),
            const InfoBanner(
              icon: Icons.school,
              color: Palette.indigo,
              text: 'Texas Hold\'em, step by step: read the lessons in order, sharpen the basics in the drills, then '
                  'take a seat and read your opponent.',
            ),
            _section('LESSONS'),
            for (var i = 0; i < PokerLesson.all.length; i++)
              _tile(
                emoji: PokerLesson.all[i].emoji,
                title: '${i + 1}. ${PokerLesson.all[i].title}',
                subtitle: '${PokerLesson.all[i].pages.length} short cards',
                onTap: () => _push(PokerLessonScreen(lesson: PokerLesson.all[i])),
              ),
            _section('DRILLS · ${PokerDrill.length} QUESTIONS EACH'),
            for (final d in PokerDrill.values)
              _tile(
                emoji: d.emoji,
                title: d.title,
                subtitle: d.subtitle,
                trailing: game.pokerBest[d.name] == null ? null : 'best ${game.pokerBest[d.name]}/${PokerDrill.length}',
                onTap: () => _push(PokerDrillScreen(game: game, drill: d)),
              ),
            _section('THE TABLE · HEADS-UP, BLINDS 5/10'),
            for (final bot in PokerBot.all)
              _tile(
                emoji: bot.emoji,
                title: '${bot.name} · ${bot.style}',
                subtitle: bot.blurb,
                onTap: () => _push(PokerTableScreen(game: game, bot: bot)),
              ),
            if (stats[0] > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Your record: ${stats[0]} hands · won ${stats[1]} · net ${stats[2] >= 0 ? '+' : ''}${stats[2]} IP · '
                  'biggest pot ${stats[3]}',
                  style: const TextStyle(color: Palette.textMuted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class PokerLessonScreen extends StatefulWidget {
  const PokerLessonScreen({super.key, required this.lesson});
  final PokerLesson lesson;

  @override
  State<PokerLessonScreen> createState() => _PokerLessonScreenState();
}

class _PokerLessonScreenState extends State<PokerLessonScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final pages = widget.lesson.pages;
    final page = pages[_page];
    final last = _page == pages.length - 1;
    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: Palette.textMuted),
                  ),
                  Expanded(
                    child: Text('${widget.lesson.emoji} ${widget.lesson.title}',
                        style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w900, fontSize: 17)),
                  ),
                  Text('${_page + 1}/${pages.length}', style: const TextStyle(color: Palette.textMuted)),
                ],
              ),
              const SizedBox(height: 8),
              _Bar(value: (_page + 1) / pages.length, color: Palette.indigo),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(page.title,
                          style: const TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 14),
                      Text(page.body, style: const TextStyle(color: Palette.textPrimary, fontSize: 17, height: 1.5)),
                      if (page.example != null) ...<Widget>[
                        const SizedBox(height: 18),
                        InfoBanner(icon: Icons.style, color: Palette.gold, text: page.example!),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  if (_page > 0)
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() => _page--),
                        child: const Text('BACK', style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: ChunkyButton(
                      label: last ? 'Done' : 'Next',
                      color: Palette.indigo,
                      onPressed: () => last ? Navigator.of(context).pop() : setState(() => _page++),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of small cards with a label.
class _PokerCards extends StatelessWidget {
  const _PokerCards({required this.label, required this.cards, this.slots = 0, this.hidden = false});
  final String label;
  final List<int> cards;
  final int slots;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final count = math.max(cards.length, slots);
    return Column(
      children: <Widget>[
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (var i = 0; i < count; i++)
              if (i < cards.length)
                _MiniCard(card: Poker.face(cards[i]), hidden: hidden)
              else
                Container(
                  width: 62,
                  height: 88,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class PokerDrillScreen extends StatefulWidget {
  const PokerDrillScreen({super.key, required this.game, required this.drill});
  final GameState game;
  final PokerDrill drill;

  @override
  State<PokerDrillScreen> createState() => _PokerDrillScreenState();
}

class _PokerDrillScreenState extends State<PokerDrillScreen> {
  final math.Random _rng = math.Random();
  late PokerQuestion _q = PokerQuestion.make(widget.drill, _rng);
  int _index = 0;
  int _score = 0;
  int? _picked;
  bool _done = false;
  bool _newBest = false;

  void _pick(int i) {
    if (_picked != null) return;
    final right = i == _q.correct;
    if (right) {
      _score++;
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    setState(() => _picked = i);
  }

  void _next() {
    if (_index + 1 >= PokerDrill.length) {
      _newBest = widget.game.reportPokerDrill(widget.drill.name, _score);
      setState(() => _done = true);
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _q = PokerQuestion.make(widget.drill, _rng);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E3B2E),
      body: SafeArea(child: _done ? _buildDone() : _buildQuestion()),
    );
  }

  Widget _buildDone() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: <Widget>[
          const Spacer(),
          Text(_newBest ? '🏆' : widget.drill.emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 10),
          Text('$_score / ${PokerDrill.length}',
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            '${_newBest ? 'New best! ' : ''}+${_score * GameState.pokerDrillIp} IP',
            style: const TextStyle(color: Palette.gold, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          ChunkyButton(label: 'Done', color: Palette.gold, textColor: const Color(0xFF1A1A1A), onPressed: () => Navigator.of(context).pop()),
          TextButton(
            onPressed: () => setState(() {
              _index = 0;
              _score = 0;
              _picked = null;
              _done = false;
              _newBest = false;
              _q = PokerQuestion.make(widget.drill, _rng);
            }),
            child: const Text('AGAIN', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _q;
    final answered = _picked != null;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
              Expanded(
                child: Text(widget.drill.title.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              ),
              Text('${_index + 1}/${PokerDrill.length} · $_score ✓',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: <Widget>[
              Text(q.prompt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.35)),
              const SizedBox(height: 16),
              if (q.theirs.isNotEmpty) ...<Widget>[
                _PokerCards(label: 'THEIR CARDS', cards: q.theirs),
                const SizedBox(height: 14),
              ],
              if (q.board.isNotEmpty) ...<Widget>[
                _PokerCards(label: 'BOARD', cards: q.board),
                const SizedBox(height: 14),
              ],
              if (q.yours.isNotEmpty) _PokerCards(label: 'YOUR CARDS', cards: q.yours),
              const SizedBox(height: 18),
              for (var i = 0; i < q.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: answered ? null : () => _pick(i),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: !answered
                          ? Colors.black26
                          : (i == q.correct
                              ? Palette.green.withAlpha(90)
                              : (i == _picked ? Palette.red.withAlpha(90) : Colors.black12)),
                      side: BorderSide(color: answered && i == q.correct ? Palette.green : Colors.white30, width: 1.5),
                    ),
                    child: Text(q.options[i],
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              if (answered) ...<Widget>[
                const SizedBox(height: 6),
                InfoBanner(
                  icon: _picked == q.correct ? Icons.check_circle : Icons.cancel,
                  color: _picked == q.correct ? Palette.green : Palette.orange,
                  text: q.explain,
                ),
              ],
            ],
          ),
        ),
        if (answered)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ChunkyButton(
              label: _index + 1 >= PokerDrill.length ? 'See score' : 'Next',
              color: Palette.gold,
              textColor: const Color(0xFF1A1A1A),
              onPressed: _next,
            ),
          ),
      ],
    );
  }
}

class PokerTableScreen extends StatefulWidget {
  const PokerTableScreen({super.key, required this.game, required this.bot});
  final GameState game;
  final PokerBot bot;

  @override
  State<PokerTableScreen> createState() => _PokerTableScreenState();
}

class _PokerTableScreenState extends State<PokerTableScreen> {
  static const int maxStack = 500;
  static const int botBuyIn = 500;

  final math.Random _rng = math.Random();
  HoldemHand? _hand;
  int _botStack = botBuyIn;
  int _button = 1;
  bool _busy = false;
  bool _coach = true;
  double? _equity;
  String _message = '';
  String _behavior = '';
  final List<(String, double, bool)> _tellsShown = <(String, double, bool)>[];
  String _review = '';

  GameState get game => widget.game;
  PokerBot get bot => widget.bot;

  int get _playerStack => math.min(game.insightPoints, maxStack);
  bool get _canDeal => (_hand == null || _hand!.over) && !_busy && _playerStack >= 20;

  @override
  void initState() {
    super.initState();
    _behavior = bot.baseline;
    _message = 'Blinds 5/10. You bring up to $maxStack IP to the table; whatever you win or lose comes out of your IP.';
  }

  void _deal() {
    if (!_canDeal) return;
    var note = '';
    if (_botStack < 100) {
      _botStack = botBuyIn;
      note = '${bot.name} buys back in. ';
    }
    _button = 1 - _button;
    final hand = HoldemHand(stacks: <int>[_playerStack, _botStack], button: _button, rng: _rng);
    HapticFeedback.mediumImpact();
    setState(() {
      _hand = hand;
      _tellsShown.clear();
      _review = '';
      _behavior = bot.baseline;
      _message = note +
          (_button == 0
              ? 'You have the button: you post 5 and act first now, last after the flop.'
              : '${bot.name} has the button. You post the 10 big blind.');
    });
    _afterAction();
  }

  String _streetName(PokerStreet s) => switch (s) {
        PokerStreet.preflop => 'Preflop',
        PokerStreet.flop => 'The flop',
        PokerStreet.turn => 'The turn',
        PokerStreet.river => 'The river',
        PokerStreet.done => 'Showdown',
      };

  Future<void> _afterAction() async {
    final h = _hand!;
    while (!h.over && h.toAct == 1) {
      setState(() {
        _busy = true;
        _equity = null;
      });
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      final before = h.street;
      final toCall = h.toCall(1);
      final choice = bot.decide(h, _rng);
      final shown = bot.behavior(strong: choice.equity >= 0.7, bluffing: choice.bluff, rng: _rng);
      if (shown != bot.baseline) _tellsShown.add((shown, choice.equity, choice.bluff));
      String verb;
      switch (choice.act) {
        case PokerAct.fold:
          verb = 'folds';
          h.fold();
        case PokerAct.check:
          verb = 'checks';
          h.checkOrCall();
        case PokerAct.call:
          verb = 'calls ${h.callAmount(1)}';
          h.checkOrCall();
        case PokerAct.raise:
          h.raiseTo(choice.raiseTo);
          final total = h.committed[1];
          verb = h.stacks[1] == 0 ? 'goes ALL-IN ($total)' : (toCall == 0 ? 'bets $total' : 'raises to $total');
      }
      setState(() {
        _behavior = shown;
        _message = '${bot.name} $verb.${!h.over && h.street != before ? ' ${_streetName(h.street)}.' : ''}';
      });
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (h.over) {
      _finish();
    } else {
      final e = Poker.equity(h.holes[0], h.board, _rng, trials: 400);
      setState(() => _equity = e);
    }
  }

  void _playerAct(PokerAct act, [int raiseTo = 0]) {
    final h = _hand;
    if (h == null || h.over || h.toAct != 0 || _busy) return;
    HapticFeedback.selectionClick();
    final before = h.street;
    final toCall = h.toCall(0);
    String text;
    switch (act) {
      case PokerAct.fold:
        text = 'You fold.';
        h.fold();
      case PokerAct.check:
      case PokerAct.call:
        text = toCall == 0 ? 'You check.' : 'You call ${h.callAmount(0)}.';
        h.checkOrCall();
      case PokerAct.raise:
        h.raiseTo(raiseTo);
        text = h.stacks[0] == 0
            ? 'You go all-in.'
            : (toCall == 0 ? 'You bet ${h.committed[0]}.' : 'You raise to ${h.committed[0]}.');
    }
    setState(() {
      _equity = null;
      _message = '$text${!h.over && h.street != before ? ' ${_streetName(h.street)}.' : ''}';
    });
    _afterAction();
  }

  void _finish() {
    final h = _hand!;
    final net = h.net(0);
    _botStack = h.stacks[1];
    game.settlePoker(net: net, won: h.winner == 0, pot: h.pot);
    final String result;
    if (h.endedByFold) {
      result = h.winner == 0 ? '${bot.name} folds. You win ${h.pot}.' : 'You fold. ${bot.name} wins ${h.pot}.';
    } else {
      final you = Poker.describe(h.score(0));
      final them = Poker.describe(h.score(1));
      result = switch (h.winner) {
        0 => 'You win ${h.pot} with $you. ${bot.name} had $them.',
        1 => '${bot.name} wins ${h.pot} with $them. You had $you.',
        _ => 'Split pot: you both have $you.',
      };
    }
    final reviews = <String>[
      for (final t in _tellsShown)
        '"${t.$1}" → ${t.$3 ? '${bot.pronoun} was bluffing' : (t.$2 >= 0.7 ? '${bot.pronoun} was strong' : 'a false alarm, nothing behind it')}',
    ];
    HapticFeedback.mediumImpact();
    setState(() {
      _message = '$result ${net > 0 ? '+$net' : '$net'} IP.';
      _review = reviews.isEmpty ? '' : 'Tell check: ${reviews.join(' · ')}. ${bot.tellMeaning}';
    });
  }

  String _coachText(HoldemHand h, double e) {
    final made = h.board.isEmpty
        ? Poker.startingName(h.holes[0][0], h.holes[0][1])
        : Poker.describe(Poker.evaluate(<int>[...h.holes[0], ...h.board]));
    final pct = (e * 100).round();
    final toCall = h.toCall(0);
    final chart = h.board.isEmpty
        ? (Poker.playable(h.holes[0][0], h.holes[0][1], late: h.button == 0)
            ? ' Starting-hand chart: play it.'
            : ' Starting-hand chart: a fold.')
        : '';
    if (toCall == 0) {
      final advice = e >= 0.65 ? 'bet for value' : (e >= 0.5 ? 'check, or bet small' : 'check');
      return '$made. You beat a random hand about $pct% of the time. Coach: $advice.$chart';
    }
    final need = (100 * toCall / (h.pot + toCall)).round();
    final advice = e >= 0.75 ? 'raise' : (pct >= need ? 'call' : 'fold');
    return '$made. About $pct% vs a random hand; calling $toCall needs $need%. Coach: $advice.$chart';
  }

  int _sized(HoldemHand h, double fraction) {
    final toCall = h.toCall(0);
    final raw = h.committed[1] + ((fraction * (h.pot + toCall)) / 5).round() * 5;
    return raw.clamp(h.minRaiseTo(0), h.maxRaiseTo(0));
  }

  @override
  Widget build(BuildContext context) {
    final h = _hand;
    final inHand = h != null && !h.over;
    return PopScope<Object?>(
      canPop: !inHand && !_busy,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              backgroundColor: Palette.surfaceHigh,
              content: Text('Finish the hand first (or fold).', style: TextStyle(color: Palette.textPrimary)),
            ));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E3B2E),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                    Expanded(
                      child: Text('HOLD\'EM VS ${bot.name.toUpperCase()}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ),
                    StatPill(emoji: '💡', label: '${game.insightPoints} IP', color: Palette.gold, tooltip: 'Your bankroll'),
                  ],
                ),
              ),
              Expanded(child: _buildTable(h)),
              _buildControls(h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable(HoldemHand? h) {
    final showBot = h != null && h.over;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(bot.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${bot.name} · ${h?.stacks[1] ?? _botStack} chips${h != null && h.button == 1 ? ' · button' : ''}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  Text('${bot.name} $_behavior',
                      style: const TextStyle(color: Palette.highlight, fontStyle: FontStyle.italic, fontSize: 13.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (h != null)
          _PokerCards(
            label: showBot ? '${bot.name.toUpperCase()}\'S CARDS${h.endedByFold ? ' (training peek)' : ''}' : '',
            cards: h.holes[1],
            hidden: !showBot,
          ),
        const SizedBox(height: 14),
        _PokerCards(label: 'BOARD', cards: h?.board ?? const <int>[], slots: 5),
        const SizedBox(height: 8),
        Text(
          h == null ? '' : 'POT ${h.pot}${!h.over && (h.committed[0] + h.committed[1]) > 0 ? '  ·  this round: you ${h.committed[0]}, ${bot.name} ${h.committed[1]}' : ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
        const SizedBox(height: 10),
        if (_message.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Text(_message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.35)),
          ),
        if (_review.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          InfoBanner(icon: Icons.visibility, color: Palette.highlight, text: _review),
        ],
        const SizedBox(height: 12),
        if (h != null) _PokerCards(label: 'YOUR CARDS · ${h.stacks[0]} chips${h.button == 0 ? ' · button' : ''}', cards: h.holes[0]),
        if (h != null && !h.over && h.toAct == 0 && _coach && _equity != null) ...<Widget>[
          const SizedBox(height: 10),
          InfoBanner(icon: Icons.school, color: Palette.gold, text: _coachText(h, _equity!)),
        ],
        if (h == null || h.over) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            'Watch ${bot.name}\'s baseline: "${bot.baseline}". When that changes, ask yourself why. '
            'After each hand you\'ll see what any tell really meant.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _buildControls(HoldemHand? h) {
    final Widget actions;
    if (h != null && !h.over) {
      final myTurn = h.toAct == 0 && !_busy;
      final toCall = h.toCall(0);
      final canRaise = myTurn && h.canRaise(0);
      final half = _sized(h, 0.5);
      final pot = _sized(h, 1.0);
      final word = toCall == 0 ? 'Bet' : 'Raise to';
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ChunkyButton(
                  label: 'Fold',
                  color: Palette.red,
                  height: 48,
                  onPressed: myTurn && toCall > 0 ? () => _playerAct(PokerAct.fold) : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChunkyButton(
                  label: toCall == 0 ? 'Check' : 'Call ${h.callAmount(0)}',
                  color: Palette.green,
                  height: 48,
                  onPressed: myTurn ? () => _playerAct(PokerAct.call) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final (label, amount) in <(String, int)>[
                ('$word $half', half),
                if (pot != half) ('$word $pot', pot),
                ('All-in ${h.maxRaiseTo(0)}', h.maxRaiseTo(0)),
              ]) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: canRaise ? () => _playerAct(PokerAct.raise, amount) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size.fromHeight(44),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: FittedBox(child: Text(label)),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      );
    } else {
      actions = ChunkyButton(
        label: _playerStack >= 20 ? (h == null ? 'Deal' : 'Next hand') : 'Not enough IP (need 20)',
        color: Palette.gold,
        textColor: const Color(0xFF1A1A1A),
        onPressed: _canDeal ? _deal : null,
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      color: const Color(0xFF0A2C22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SwitchListTile(
            dense: true,
            value: _coach,
            onChanged: (v) => setState(() => _coach = v),
            title: const Text('Coach (hand strength, odds, advice)', style: TextStyle(color: Colors.white)),
          ),
          actions,
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  PROGRESS TAB: rank, daily missions, checkups, weak spots, records, badges
// ════════════════════════════════════════════════════════════════════════════

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.game});
  final GameState game;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
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

  void _openMode(PracticeMode mode) {
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
                        'Progress',
                        style: TextStyle(color: Palette.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 4),
                      Text('Proof you\'re getting better.', style: TextStyle(color: Palette.textMuted, fontSize: 14)),
                    ],
                  ),
                ),
                StatPill(emoji: '💡', label: '${game.insightPoints} IP', color: Palette.blue, tooltip: 'Insight Points'),
              ],
            ),
            const SizedBox(height: 16),
            _RankCard(game: game),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => RealLifeScreen(game: game)),
                ),
                child: RealLifeInsights(game: game),
              ),
            ),
            const SizedBox(height: 14),
            _MissionsCard(game: game),
            const SizedBox(height: 14),
            _CheckupCard(game: game, onStart: () => _openMode(PracticeMode.checkup)),
            const SizedBox(height: 14),
            _WeakSpotsCard(game: game, onTrain: () => _openMode(PracticeMode.weakSpots)),
            const SizedBox(height: 14),
            _MemoryRecordsCard(game: game),
            const SizedBox(height: 14),
            _BadgesCard(game: game),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing, this.color = Palette.border});
  final String title;
  final Widget child;
  final String? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
                ),
              ),
              if (trailing != null)
                Text(trailing!, style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, this.height = 8});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: Palette.surfaceHigh,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.game});
  final GameState game;

  void _showRanks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Ranks', style: TextStyle(color: Palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text(
                'Every lie-reading answer moves your Reader Rating. Getting a hard question right moves it up a lot; '
                'missing an easy one drops it. Easy questions stop helping once you\'re good, so the high ranks need '
                'the high levels.',
                style: TextStyle(color: Palette.textMuted, height: 1.4),
              ),
              const SizedBox(height: 12),
              for (final r in ReaderRank.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: <Widget>[
                      Text(r.emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              r.title,
                              style: TextStyle(
                                color: r == game.rank ? Palette.gold : Palette.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(r.blurb, style: const TextStyle(color: Palette.textMuted, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Text(
                        r.minRating == 0 ? 'start' : '${r.minRating}',
                        style: TextStyle(
                          color: game.peakRating >= r.minRating ? Palette.green : Palette.textMuted,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = game.rank;
    final next = r.next;
    final today = dayIndex();
    final weekDelta = game.rating - game.ratingOn(today - 7);
    final progress = next == null ? 1.0 : (game.rating - r.minRating) / (next.minRating - r.minRating);
    final points = <int>[];
    if (game.ratingLog.isNotEmpty) {
      final firstDay = game.ratingLog.keys.reduce(math.min);
      for (var d = math.max(today - 29, firstDay); d <= today; d++) {
        points.add(game.ratingOn(d));
      }
    }
    return Material(
      color: Palette.indigo.withAlpha(30),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showRanks(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.indigo.withAlpha(160), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(r.emoji, style: const TextStyle(fontSize: 46)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('READER RANK',
                            style: TextStyle(
                                color: Palette.indigo, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                        Text(r.title,
                            style: const TextStyle(color: Palette.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
                        Text(r.blurb, style: const TextStyle(color: Palette.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text('${game.rating}',
                          style: const TextStyle(color: Palette.textPrimary, fontSize: 28, fontWeight: FontWeight.w900)),
                      Text(
                        weekDelta == 0 ? 'this week: –' : 'this week: ${weekDelta > 0 ? '+' : ''}$weekDelta',
                        style: TextStyle(
                          color: weekDelta > 0 ? Palette.green : (weekDelta < 0 ? Palette.orange : Palette.textMuted),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Bar(value: progress, color: Palette.indigo, height: 10),
              const SizedBox(height: 6),
              Text(
                next == null
                    ? 'Top rank reached. Keep it there.'
                    : '${next.minRating - game.rating} points to ${next.emoji} ${next.title}',
                style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: points.length < 2
                    ? const Center(
                        child: Text(
                          'Answer questions on a couple of days to see your rating line.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Palette.textMuted, fontSize: 12.5),
                        ),
                      )
                    : CustomPaint(painter: _RatingChartPainter(points), size: Size.infinite),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap to see all ranks. Hard questions count more than easy ones.',
                style: TextStyle(color: Palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingChartPainter extends CustomPainter {
  _RatingChartPainter(this.points);
  final List<int> points;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = points.reduce(math.min) - 20;
    final hi = points.reduce(math.max) + 20;
    final span = math.max(1, hi - lo);
    const labelWidth = 34.0;
    final w = size.width - labelWidth;
    Offset at(int i) => Offset(
          labelWidth + (points.length == 1 ? w : w * i / (points.length - 1)),
          size.height - size.height * (points[i] - lo) / span,
        );

    final grid = Paint()
      ..color = Palette.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(labelWidth, 0), Offset(size.width, 0), grid);
    canvas.drawLine(Offset(labelWidth, size.height), Offset(size.width, size.height), grid);
    void label(String text, double y) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(color: Palette.textMuted, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, (y - tp.height / 2).clamp(0.0, size.height - tp.height)));
    }

    label('$hi', 0);
    label('$lo', size.height);

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(at(points.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = Palette.indigo.withAlpha(40));
    canvas.drawPath(
      line,
      Paint()
        ..color = Palette.indigo
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(at(points.length - 1), 4.5, Paint()..color = Palette.gold);
  }

  @override
  bool shouldRepaint(_RatingChartPainter old) => !listEquals(old.points, points);
}

class _MissionsCard extends StatelessWidget {
  const _MissionsCard({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final missions = game.todaysMissions;
    final done = missions.where(game.missionDone).length;
    return _Panel(
      title: 'TODAY\'S MISSIONS',
      trailing: '$done/3',
      color: done == 3 ? Palette.gold : Palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final m in missions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Text(m.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          m.title,
                          style: TextStyle(
                            color: game.missionDone(m) ? Palette.green : Palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            decoration: game.missionDone(m) ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _Bar(value: game.missionCount(m) / m.target, color: game.missionDone(m) ? Palette.green : Palette.gold),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    game.missionDone(m) ? '✓' : '${game.missionCount(m)}/${m.target}',
                    style: TextStyle(
                      color: game.missionDone(m) ? Palette.green : Palette.textMuted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            done == 3
                ? 'All done today. New missions tomorrow.'
                : '+${GameState.missionReward} IP each · +${GameState.allMissionsBonus} IP bonus for all three',
            style: const TextStyle(color: Palette.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _CheckupCard extends StatelessWidget {
  const _CheckupCard({required this.game, required this.onStart});
  final GameState game;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final history = game.checkups;
    final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
    final daysSince = history.isEmpty ? null : dayIndex() - history.last[0];
    final due = daysSince == null || daysSince >= 7;
    int pct(List<int> c) => (100 * c[1] / c[2]).round();
    return _Panel(
      title: 'WEEKLY CHECKUP',
      trailing: due ? 'Due now' : 'Next in ${7 - daysSince!}d',
      color: due ? Palette.indigo : Palette.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '24 questions, two from each of the 12 levels, including ones you haven\'t reached yet. No hints or feedback until the '
            'end. Take it once a week: if your score climbs, you\'re getting better.',
            style: TextStyle(color: Palette.textPrimary, fontSize: 13.5, height: 1.4),
          ),
          if (history.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: _MiniStat(label: 'First', value: '${game.firstCheckupPct}%')),
                const SizedBox(width: 8),
                Expanded(child: _MiniStat(label: 'Best', value: '${game.bestCheckupPct}%', color: Palette.gold)),
                const SizedBox(width: 8),
                Expanded(child: _MiniStat(label: 'Latest', value: '${pct(history.last)}%')),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 90,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final c in recent)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            Text('${pct(c)}', style: const TextStyle(color: Palette.textMuted, fontSize: 10.5)),
                            const SizedBox(height: 2),
                            Container(
                              height: math.max(4, 66 * pct(c) / 100).toDouble(),
                              decoration: BoxDecoration(
                                color: c == history.last ? Palette.indigo : Palette.indigo.withAlpha(120),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ChunkyButton(
            label: history.isEmpty ? 'Take your first Checkup' : 'Take the Checkup',
            color: Palette.indigo,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _WeakSpotsCard extends StatelessWidget {
  const _WeakSpotsCard({required this.game, required this.onTrain});
  final GameState game;
  final VoidCallback onTrain;

  @override
  Widget build(BuildContext context) {
    final weak = game.weakFlags();
    return _Panel(
      title: 'WEAK SPOTS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (weak.isEmpty)
            const Text(
              'Nothing stands out yet. Keep answering and the skills you miss most will show up here.',
              style: TextStyle(color: Palette.textMuted, height: 1.4),
            )
          else
            for (final f in weak)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(f.label,
                              style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          '${(100 * (game.flagAttempts[f]! - game.flagMisses[f]!) / game.flagAttempts[f]!).round()}% '
                          'of ${game.flagAttempts[f]}',
                          style: const TextStyle(color: Palette.orange, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _Bar(
                      value: (game.flagAttempts[f]! - game.flagMisses[f]!) / game.flagAttempts[f]!,
                      color: Palette.orange,
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          ChunkyButton(label: 'Train weak spots', color: Palette.teal, onPressed: onTrain),
        ],
      ),
    );
  }
}

class _MemoryRecordsCard extends StatelessWidget {
  const _MemoryRecordsCard({required this.game});
  final GameState game;

  static const Map<MemoryDrill, int> _typical = <MemoryDrill, int>{MemoryDrill.digits: 7, MemoryDrill.words: 7};

  @override
  Widget build(BuildContext context) {
    final drills = MemoryDrill.values.where((d) => d.leveled).toList();
    return _Panel(
      title: 'MEMORY RECORDS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final d in drills)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Icon(d.icon, color: d.color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(d.title,
                                  style: const TextStyle(color: Palette.textPrimary, fontWeight: FontWeight.w800)),
                            ),
                            Text(
                              game.memory.best[d] == 0 ? 'no record' : 'best ${d.levelLabel(game.memory.best[d]!)}',
                              style: TextStyle(color: d.color, fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _Bar(value: game.memory.best[d]! / d.maxLevel, color: d.color),
                        if (_typical[d] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Most people: about ${_typical[d]} ${d.unit}. Max here: ${d.maxLevel}.',
                              style: const TextStyle(color: Palette.textMuted, fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Text(
            '${game.memory.learnedCards()}/${MemoryContent.cards.length} study cards learned',
            style: const TextStyle(color: Palette.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _BadgesCard extends StatelessWidget {
  const _BadgesCard({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final all = Achievement.all;
    return _Panel(
      title: 'BADGES',
      trailing: '${all.where((a) => game.achievements.contains(a.id)).length}/${all.length}',
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.78,
        children: <Widget>[
          for (final a in all)
            _BadgeTile(achievement: a, earned: game.achievements.contains(a.id)),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.achievement, required this.earned});
  final Achievement achievement;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            backgroundColor: Palette.surfaceHigh,
            content: Text(
              '${achievement.emoji} ${achievement.title}: ${achievement.description}${earned ? ' ✓ Earned' : ''}',
              style: const TextStyle(color: Palette.textPrimary),
            ),
          ));
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: earned ? Palette.gold.withAlpha(30) : Palette.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: earned ? Palette.gold.withAlpha(160) : Palette.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Opacity(
              opacity: earned ? 1 : 0.25,
              child: Text(achievement.emoji, style: const TextStyle(fontSize: 26)),
            ),
            const SizedBox(height: 4),
            Text(
              earned ? achievement.title : '🔒 ${achievement.title}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: earned ? Palette.textPrimary : Palette.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pop-up at the top of the screen for badges, missions and rank-ups.
class _ToastBanner extends StatelessWidget {
  const _ToastBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Transform.translate(
            offset: Offset(0, -40 * (1 - v)),
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
          ),
          child: Material(
            color: Palette.surfaceHigh,
            elevation: 10,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.gold, width: 1.5),
              ),
              child: Text(
                text,
                style: const TextStyle(color: Palette.textPrimary, fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
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
