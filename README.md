# Cold Reading

A Duolingo-style Flutter app that teaches baseline reading, micro-expressions,
behavioral clusters and statement analysis. Everything lives in
`lib/main.dart`: no packages, no servers, all state in memory.

## Get it on an Android phone

Every push to `main` builds an APK on GitHub Actions.

1. On the phone, sign in to GitHub in the browser and open this repo's **Actions** tab.
2. Open the latest green **Build Cold Reading APK** run.
3. Under **Artifacts**, tap **ColdReading-apk** to download the .zip.
4. Open the .zip in Files, tap `ColdReading.apk`, and allow "Install unknown apps" when asked.

Every build is signed with the same key (`signing/app.keystore`), so new versions install
over old ones. It's a personal sideloading key, not a Play Store key.

## Run it from source

Needs Flutter 3.24 or newer (uses `PopScope.onPopInvokedWithResult`).

```bash
flutter create .        # generates the android/ and ios/ folders
flutter run             # pick your phone or emulator
```

Or paste `lib/main.dart` into any new Flutter project.

## What's inside

| Area | Where in `main.dart` |
| --- | --- |
| Curriculum: 8 levels, 102 challenges (standard + High Cognitive Load) | `Curriculum` |
| Hearts, IP, streak, accuracy, weakness map | `GameState` |
| Retry queue, difficulty swap, weighted review builder | `QuestSession`, `QuestBuilder` |
| Mind Tree dashboard + persistent header | `MindTreeScreen`, `StatsHeader` |
| Quest flow, bottom feedback sheet, completion card | `QuestScreen`, `FeedbackSheet`, `QuestCompleteView` |

## Courses

1. **The Baseline:** spot the moment behavior breaks from a person's normal.
2. **Micro-Expressions & Asymmetry:** name the emotion from a brief flash card.
3. **Cluster Decoding:** pick the 3 real stress signals out of 6.
4. **Statement Analysis:** pronoun drops, time gaps, tense shifts, non-answers.
5. **Verbal Tells:** qualifiers, oaths, distancing, minimizing, stalling.
6. **Truth Signals:** what real memories sound like versus credibility pitches.
7. **Interview Tactics:** choose the best next question or move.
8. **Digital Deception:** tells in texts, emails, reviews and DMs.
9. **Checkable Details:** truth comes with names, places and receipts; lies hide the key part where nobody can check.
10. **Making Lies Hard Work:** backwards stories, unexpected questions, and holding back your evidence.
11. **Myths & False Alarms:** eye direction, nose touching, crossed arms, and the Othello error.
12. **Deduction & Cold Reading:** combine small clues like Patrick Jane, and learn how "psychics" fake it.

Each course has 2 lessons (6 questions each) and an adaptive review (7); the final exam (12) covers everything.

Baseline and statement questions always offer **"Nothing here"**, and some cases are
genuinely truthful, so you practice not crying wolf as well as catching lies.

## Practice

A third tab for extra reps that never cost hearts:

- **The Consultant**: interview three suspects, switch between them, and get the guilty one to confess.
  Small talk, open story, reverse order, detail, unexpected questions and evidence build the case; pressure backfires.
- **Two Truths & a Lie**: a real-life trainer for playing with friends. Question cards tell you what
  to ask (checkable details, unexpected questions, telling it backwards, holding back what you know).
  Before the reveal you log what gave it away and how sure you were, so the app can show which clues
  actually work for you and whether your confidence means anything.
- **What Actually Works**: a short, research-based guide to catching real lies (and the myths).
- **Your progress**: daily accuracy for the last two weeks, this week vs. last.
- **Baseline Lab**: endless, freshly generated baseline cases with a best streak.
- **Speed Round**: 90 seconds across every unlocked level.
- **Survival**: three strikes, getting harder as your score climbs.
- **Mistake Review**: replays questions you got wrong until you get them right.
- **Daily Case File**: five new cases a day, with a bonus the first time.

Level 1 baseline questions are generated fresh every time: each person gets a random baseline
built from the same tells (neck rubbing, collar tugging, blink bursts, pauses…), every option
shows a tell, and only the baseline tells you which one, if any, is a real change.

## Memory Gym

A second tab that trains memory with techniques that hold up in research, not generic brain games:

- **Chunking Coach**: a five-stage guided course (pre-split numbers with how to say each chunk →
  meaning hints → split it yourself → split and pick meanings → no help), three in a row to advance.
- **How Memory Works**: a short guide to attention, meaning, pictures, self-testing, spacing and sleep.
- **Number Span**: chunking digits into meaningful groups.
- **Story Chain**: the link method, chaining words into one vivid story.
- **Memory Palace**: the method of loci along a 12-stop route through your own home.
- **Names & Faces**: name hooks that tie a name and a fact to a face.
- **Kim's Game**: spotting what changed or went missing in a grid.
- **Person Snapshot**: observation recall of a stranger's details, plus fact-vs-inference questions.
- **Spaced Review**: flashcards for every technique and Cold Reading concept, on a 1 → 3 → 7 → 14 → 30 day schedule.

Every drill has a short lesson and adjusts difficulty after each round (one level up when you
nail it, down when you miss), so you're always training at your edge. A daily workout of
about 5 minutes covers spaced review, Number Span and a rotating drill of the day.

Progress (both tabs) is saved on the phone with `shared_preferences`; nothing leaves the device.

## Deduction Lab & Poker Face

On the Practice tab.

- **Deduction Lab:** read someone's job from clues, Patrick Jane style. Two lessons
  (how Jane does it; what to look at), endless Case Files (20 jobs, 100 clues, one
  decoy per case), and a People Watching log for real-life guesses.
- **Poker Face:** bluffing for games (Two Truths & a Lie, poker, Werewolf, Among Us,
  surprise parties). Two lessons, a "Which Sounds True?" drill, and a tracker for how
  often you fool your friends.

## Poker School

On the Memory tab, below the Blackjack Table.

- **6 lessons:** how a hand works, hand rankings, which hands to play, outs & odds,
  reading players, bluffing & home games.
- **5 drills** (10 questions each): Name That Hand, Who Wins?, Play or Fold?,
  Count the Outs, Call or Fold? (pot odds).
- **Heads-up Hold'em table** (blinds 5/10, up to 500 IP) against Rex (tight & honest),
  Lola (loose & chatty) or Vic (the actor). Each has a baseline and tells that are right
  about 80% of the time; after each hand you see what any tell really meant.
  Optional coach shows your hand, win chance and pot odds.

Blackjack pays 3 to 2: a 10 IP bet wins 15 on a blackjack.

## Progress

The fourth tab shows whether you're actually getting better.

- **Reader Rating & ranks.** Every lie-reading answer moves an Elo-style rating
  (start 800). Hard, high-level questions move it the most; easy ones stop helping
  once you're good. Ranks: Rookie → Observer (900) → Analyst (1000) →
  Investigator (1100) → Profiler (1250) → Interrogator (1400) → Mentalist (1550)
  → Human Lie Detector (1700). The answer sheet shows the change after each answer.
- **Daily missions.** Three a day (one lie-reading, one memory, one other).
  +15 IP each, +40 for all three.
- **Weekly Checkup.** 24 questions, one normal and one hard from each of the 12 levels,
  no feedback until the end. Same shape every time, so scores compare fairly.
  Shows first / best / latest and what you missed.
- **Weak Spot Training.** Ten questions aimed at your three least accurate skills.
- **Memory records** and **43 badges**. Badges, missions and rank-ups pop up at
  the top of the screen when you earn them.

## Game rules

- 3 hearts. A wrong answer costs 1 heart and the challenge repeats at the end of the quest.
- Hearts regenerate 1 every 2 minutes, +1 on quest completion, or refill for 30 IP.
- IP: +10 per correct answer, +20 on High Cognitive Load questions, +5 on retries,
  +20 per completed quest, +15 for a flawless quest.
- Over 70% accuracy across your last 10 answers (minimum 4), upcoming questions
  swap to High Cognitive Load variants where the flag is buried in ordinary dialogue.
- Every miss is logged per flag (e.g. Verb Tense Shift). Review nodes guarantee
  extra drills on your weakest flag and weight the rest by your misses.
  Tap the chart icon in the header to see your Calibration Profile.
