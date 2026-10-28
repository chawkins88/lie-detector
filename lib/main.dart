// ════════════════════════════════════════════════════════════════════════════
//  MindHunter Academy
//  A Duolingo-style trainer for reading people, spotting deception and
//  mastering statement analysis.
//
//  • Single file, no third-party packages, no network, all state in memory.
//  • Run:  flutter create mindhunter_academy
//          replace mindhunter_academy/lib/main.dart with this file
//          flutter run
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MindHunterApp());
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
  statement('Statement Analysis', Icons.format_quote);

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
  nonAnswer('Non-Answer Assertion', ChallengeType.statement);

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
        prompt: 'Which moment breaks the baseline?',
        context: context,
        options: moments,
        correct: <int>{answer},
        insight: insight,
        highLoad: highLoad,
      );

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
        options: emotions,
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
  }) =>
      Challenge(
        id: id,
        level: 3,
        type: ChallengeType.cluster,
        flag: Flag.clusterBuilding,
        prompt: 'Tap exactly 3 genuine stress indicators to build the cluster.',
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
  }) =>
      Challenge(
        id: id,
        level: 4,
        type: ChallengeType.statement,
        flag: flag,
        prompt: 'Tap the sentence with the structural flaw.',
        context: question,
        options: sentences,
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

  int get requiredSelections => correct.length;
  bool get isMultiSelect => type == ChallengeType.cluster;

  String get correctAnswerText {
    final indices = correct.toList()..sort();
    final lines = indices.map((i) => switch (type) {
          ChallengeType.statement => 'Sentence ${i + 1}: "${options[i]}"',
          ChallengeType.cluster => '• ${options[i]}',
          ChallengeType.baseline => 'Moment ${String.fromCharCode(65 + i)}: ${options[i]}',
          ChallengeType.microExpression => options[i],
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
        for (var n = 0; n < order.length; n++)
          if (correct.contains(order[n])) n,
      },
      insight: insight,
      highLoad: highLoad,
    );
  }
}

class LevelInfo {
  const LevelInfo(this.number, this.title, this.subtitle, this.color);
  final int number;
  final String title;
  final String subtitle;
  final Color color;
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
    LevelInfo(1, 'The Baseline', 'Intro to the grammar of behavior', Palette.green),
    LevelInfo(2, 'Micro-Expressions & Asymmetry', 'Catch emotion leaking in under a second', Palette.blue),
    LevelInfo(3, 'Cluster Decoding', 'Build behavioral sentences, not single words', Palette.purple),
    LevelInfo(4, 'Statement Analysis', 'The Master Class: the structure of a lie', Palette.orange),
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
      id: 'exam',
      level: 4,
      title: 'MindHunter Exam',
      description: 'The final adaptive exam across all four levels, calibrated to your profile.',
      icon: Icons.emoji_events,
      isReview: true,
      questLength: 5,
    ),
  ];

  static final List<Challenge> challenges = <Challenge>[
    // ── LEVEL 1 · THE BASELINE ─────────────────────────────────────────────
    Challenge.baseline(
      id: 'b1',
      flag: Flag.vocalShift,
      context: 'Marcus is questioned about a break-in at his office.\n\n'
          'BASELINE: In ten minutes of small talk he speaks slowly in a low, even monotone. His volume never '
          'changes and his hands rest on the table.',
      moments: <String>[
        'Asked if he has ever been arrested → slow, low and even: "Once, in college. A bar fight."',
        'Asked what he did Friday night → same low tone, but words come quicker: "Home. Movie. Bed."',
        'Asked if he knows the alarm code → slow, flat, hands on the table: "Everyone on my team does."',
        'Asked about the missing laptop → slow monotone, a long explanation of who had keys that week.',
      ],
      answer: 1,
      insight: 'Only the Friday answer changes his voice: same pitch, faster rate. The other answers sound '
          'suspicious (an arrest, knowing the code, a long explanation) but his delivery never leaves baseline. '
          'Judge the change in behavior, not how incriminating the words sound. A rate change tied to one topic '
          'marks a hot spot to probe, not proof of a lie.',
    ),
    Challenge.baseline(
      id: 'b2',
      flag: Flag.gestureShift,
      context: 'Dana is asked about leaked client files.\n\n'
          'BASELINE: Dana is an animated talker. Both hands move constantly while she speaks, on every topic.',
      moments: <String>[
        'Asked if she has seen the client list → hands sweep wide: "Sure, we all use it every day."',
        'Asked about the leak → hands chop the air angrily: "Whoever did this should be fired."',
        'Asked if she opened the folder Tuesday → answers fully, palms resting still on her knees.',
        'Asked who else had access → hands circle as she rattles off five coworkers by name.',
      ],
      answer: 2,
      insight: 'Illustrator suppression. For a naturally expressive person, hands that suddenly go still signal '
          'cognitive load or the "freeze" response. The angry chopping looks dramatic, but it is still Dana '
          'gesturing the way she always does.',
    ),
    Challenge.baseline(
      id: 'b3',
      flag: Flag.pacifying,
      context: 'Ray is interviewed about cash missing from his register.\n\n'
          'BASELINE: Ray sits calmly with hands loosely folded. He rarely touches his face, neck or hair.',
      moments: <String>[
        'Asked who closed the register → hands folded, calmly names his shift partner, Luis.',
        'Asked if he is short on money → hands folded, a small laugh: "Doesn\'t everybody?"',
        'Asked about the camera outage → unfolds his hands and runs a thumb along his collar.',
        'Asked when he last counted the cash → hands folded: "Around four, I think. Maybe four-thirty."',
      ],
      answer: 2,
      insight: 'Touching the neck or collar is a pacifier: a self-soothing reflex after a stressor. Against a '
          'hands-folded baseline it stands out. Blaming a coworker, joking about money and hedging ("I think") '
          'feel suspicious, but none of them is a change in Ray\'s body.',
    ),
    Challenge.baseline(
      id: 'b4',
      flag: Flag.ocularShift,
      context: 'Priya is asked about a meeting with a competitor.\n\n'
          'BASELINE: Priya blinks at a normal rate and holds comfortable eye contact throughout small talk.',
      moments: <String>[
        'Asked if she knows anyone at Halvorsen Corp → steady gaze: "A few people, from conferences."',
        'Asked about her bonus → steady eye contact, normal blinks, calls it "honestly disappointing."',
        'Asked if she met them last month → holds eye contact, but blinks in a quick burst of five.',
        'Asked where she had lunch that day → steady eye contact, names a café across the street.',
      ],
      answer: 2,
      insight: 'A sudden burst of blinks is a classic eye-behavior shift; blink rate often surges with stress or '
          'heavy thinking. Knowing people at the competitor or resenting a bonus are motives, not behavior changes.',
    ),
    Challenge.baseline(
      id: 'b5',
      flag: Flag.postureShift,
      context: 'Tom is interviewed about a skipped safety inspection.\n\n'
          'BASELINE: Tom leans forward, torso open, both feet pointed at the interviewer.',
      moments: <String>[
        'Asked if he skipped the inspection → leans in and frowns: "Absolutely not. Ask anyone."',
        'Asked who signed the form → stays leaning in, but both feet slide to point at the door.',
        'Asked about the accident report → leans in, open torso, names the injured worker.',
        'Asked about his safety training → feet forward, open torso, says he "mostly" remembers it.',
      ],
      answer: 1,
      insight: 'Foot orientation. We point our feet toward where we want to go. The upper body stayed engaged, '
          'but the feet turned toward the exit. Feet are often the most honest part of the body because we rarely '
          'think to control them.',
    ),
    // High Cognitive Load · Level 1
    Challenge.baseline(
      id: 'b6',
      flag: Flag.vocalShift,
      highLoad: true,
      context: 'Elena is questioned about an unauthorized login.\n\n'
          'BASELINE: Elena naturally talks fast, high-pitched, and laughs constantly, even about serious subjects. '
          'She jokes through the entire warm-up.',
      moments: <String>[
        'Asked about the login → rapid and high, laughing: "Wasn\'t me, I can barely use email!"',
        'Asked if anyone knows her password → still quick, a beat lower, and no laugh this time.',
        'Asked about her manager → fast, high, an eye-roll and a laugh: "She\'s a nightmare."',
        'Asked if she was online at 2 AM → fast and giggling: "At 2 AM? I\'m always asleep by then!"',
      ],
      answer: 1,
      insight: 'For a fast, high, joking baseline, the anomaly runs the other way: a lower voice and a missing laugh. '
          'Repeating the question ("At 2 AM?") is a verbal stall worth noting, but her delivery stayed on baseline.',
    ),
    Challenge.baseline(
      id: 'b7',
      flag: Flag.ocularShift,
      highLoad: true,
      context: 'Kenji is asked about deleted server logs.\n\n'
          'BASELINE: Kenji naturally avoids eye contact. He looks down while thinking and pushes his glasses up every '
          'few sentences. Quiet but cooperative.',
      moments: <String>[
        'Asked if he ran the delete command → eyes on the table, pushes up his glasses: "No."',
        'Asked about the backup schedule → glances away, pauses a long time, adjusts his glasses.',
        'Asked who has admin access → looks up and holds her gaze the whole time he lists names.',
        'Asked about the deleted logs → stares at his hands, then pushes his glasses up twice.',
      ],
      answer: 2,
      insight: 'Overcompensation. People who believe "liars look away" may hold unnaturally steady eye contact. '
          'For someone whose baseline is looking down, a sudden held gaze is the anomaly, even on a question that '
          'sounds harmless.',
    ),
    Challenge.baseline(
      id: 'b8',
      flag: Flag.postureShift,
      highLoad: true,
      context: 'Sofia is asked about a client meeting that never appeared on the calendar.\n\n'
          'BASELINE: Sofia rocks gently in her chair, twirls her necklace and shifts position every minute or so. '
          'Restless, but relaxed.',
      moments: <String>[
        'Asked who she met Thursday → rocks gently, twirling her necklace: "Just a client lunch."',
        'Asked why it isn\'t on the calendar → shifts in her seat: "I forgot to add it, honestly."',
        'Asked for the client\'s name → answers calmly, hands in her lap, perfectly still.',
        'Asked about her sales numbers → rocks, laughs, changes position twice while answering.',
      ],
      answer: 2,
      insight: 'The freeze response. When a restless person suddenly goes still, the body may be "freezing" to avoid '
          'detection. Calm stillness looks innocent, which is exactly why it\'s easy to miss.',
    ),
    Challenge.baseline(
      id: 'b9',
      flag: Flag.pacifying,
      highLoad: true,
      context: 'Victor is asked about a duplicated invoice.\n\n'
          'BASELINE: Victor is loud and confident. He sits wide, arms spread across both armrests, points while he '
          'talks and laughs loudly.',
      moments: <String>[
        'Asked about the duplicate payment → points at her, booming: "Ask accounting, not me!"',
        'Asked if he approved it → arms wide, a loud laugh, then a quick tug at his collar.',
        'Asked about the vendor → leans back, arms spread, loudly calls them "total amateurs."',
        'Asked if he would take a polygraph → laughs loudly, arms wide: "Bring it. Any day."',
      ],
      answer: 1,
      insight: 'Collar ventilation is a pacifier that releases built-up stress, and Victor never does it at baseline. '
          'Blame-shifting and bravado sound guilty, but they are how Victor always talks.',
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
  GameState() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
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
  static const int minSamplesForScaling = 5;
  static const double highLoadThreshold = 0.8;

  int hearts = maxHearts;
  int insightPoints = 0;
  int streak = 0;
  DateTime? _lastActiveDay;

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
    notifyListeners();
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

    notifyListeners();
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
    notifyListeners();
    return true;
  }

  bool _touchStreak() {
    final today = DateUtils.dateOnly(DateTime.now());
    final last = _lastActiveDay;
    if (last != null) {
      final gap = today.difference(last).inDays;
      if (gap == 0) return false;
      streak = gap == 1 ? streak + 1 : 1;
    } else {
      streak = 1;
    }
    _lastActiveDay = today;
    return true;
  }

  void _tick() {
    if (hearts >= maxHearts) {
      _nextHeartAt = null;
      return;
    }
    final now = DateTime.now();
    _nextHeartAt ??= now.add(heartRegenInterval);
    if (!now.isBefore(_nextHeartAt!)) {
      hearts++;
      _nextHeartAt = hearts < maxHearts ? now.add(heartRegenInterval) : null;
    }
    notifyListeners(); // keeps the regen countdown live
  }

  @override
  void dispose() {
    _ticker?.cancel();
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

  /// Difficulty scaling: if the player is above 80% accuracy, swap the
  /// upcoming standard question for a High Cognitive Load variant of the same
  /// level (same flag when possible). Returns true if a swap happened.
  bool escalateCurrentIfNeeded(GameState game, math.Random rng) {
    final item = current;
    if (item.isRetry || item.challenge.highLoad || !game.highLoadActive) return false;

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
        items: pool.take(node.questLength).map((c) => QuestItem(c.shuffled(rng))).toList(),
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
      items: picks.map((c) => QuestItem(c.shuffled(rng))).toList(),
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

class MindHunterApp extends StatefulWidget {
  const MindHunterApp({super.key});

  @override
  State<MindHunterApp> createState() => _MindHunterAppState();
}

class _MindHunterAppState extends State<MindHunterApp> {
  final GameState _game = GameState();

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindHunter Academy',
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
      ),
      home: MindTreeScreen(game: _game),
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
          text: 'High Cognitive Load is ON. Your accuracy is above 80%, so new questions bury the flags deeper.',
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
            ? '🎓 Certified MindHunter.\nReplay any node to keep your edge sharp.'
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
          'MindHunter Academy',
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
    final type = ChallengeType.values[node.level - 1];

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
            content: Text('A cluster needs exactly 3. Deselect one first.',
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
                    ? 'HIGH COGNITIVE LOAD: accuracy above 80%. Flags are now buried in ordinary dialogue.'
                    : 'High Cognitive Load scenario',
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              ),
            if (calibrated != null && challenge.flag == calibrated && !item.isRetry)
              InfoBanner(
                icon: Icons.track_changes,
                color: Palette.gold,
                text: 'Calibration drill: ${calibrated.label}',
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> body = switch (challenge.type) {
      ChallengeType.baseline => _baselineBody(),
      ChallengeType.microExpression => _microBody(),
      ChallengeType.cluster => _clusterBody(),
      ChallengeType.statement => _statementBody(),
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
    ];
  }

  List<Widget> _microBody() {
    final rows = (challenge.options.length + 1) ~/ 2;
    return <Widget>[
      MicroFlashCard(
        description: challenge.context,
        exposure: Duration(seconds: challenge.highLoad ? 5 : 8),
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
    return <Widget>[
      ContextCard(
        label: 'BEHAVIOR LOG',
        icon: Icons.assignment,
        text: challenge.context,
        accent: Palette.purple,
      ),
      const SizedBox(height: 14),
      Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'STRESS INDICATORS',
              style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
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
    return <Widget>[
      InterviewerBubble(question: challenge.context),
      const SizedBox(height: 16),
      const Text(
        'SUBJECT\'S STATEMENT',
        style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1),
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
  const InterviewerBubble({super.key, required this.question});
  final String question;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const CircleAvatar(
          radius: 22,
          backgroundColor: Palette.orange,
          child: Icon(Icons.mic, color: Colors.white),
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
              border: Border.all(color: Palette.orange.withAlpha(110), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'INTERVIEWER',
                  style: TextStyle(color: Palette.orange, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.1),
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
  const MicroFlashCard({super.key, required this.description, required this.exposure, required this.revealed});
  final String description;
  final Duration exposure;
  final bool revealed;

  @override
  State<MicroFlashCard> createState() => _MicroFlashCardState();
}

class _MicroFlashCardState extends State<MicroFlashCard> with SingleTickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(vsync: this, duration: widget.exposure);
  bool _reflashUsed = false;

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
  });

  final bool correct;
  final Challenge challenge;
  final int ipGain;
  final int heartsLeft;
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
                    correct ? '+$ipGain IP' : '−1 ❤️',
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
              '🚩 ${challenge.flag.label}',
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
            if (!correct) ...<Widget>[
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
