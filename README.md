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

Each course has 2 lessons and an adaptive review; a final exam covers everything.

Baseline and statement questions always offer **"Nothing here"**, and some cases are
genuinely truthful, so you practice not crying wolf as well as catching lies.

## Practice

A third tab for extra reps that never cost hearts:

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
