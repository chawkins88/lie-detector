# MindHunter Academy

A Duolingo-style Flutter app that teaches baseline reading, micro-expressions,
behavioral clusters and statement analysis. Everything lives in
`lib/main.dart`: no packages, no servers, all state in memory.

## Get it on an Android phone

Every push to `main` builds an APK on GitHub Actions.

1. On the phone, sign in to GitHub in the browser and open this repo's **Actions** tab.
2. Open the latest green **Build MindHunter APK** run.
3. Under **Artifacts**, tap **MindHunterAcademy-apk** to download the .zip.
4. Open the .zip in Files, tap `MindHunterAcademy.apk`, and allow "Install unknown apps" when asked.

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
| Curriculum: 4 levels, 38 challenges (standard + High Cognitive Load) | `Curriculum` |
| Hearts, IP, streak, accuracy, weakness map | `GameState` |
| Retry queue, difficulty swap, weighted review builder | `QuestSession`, `QuestBuilder` |
| Mind Tree dashboard + persistent header | `MindTreeScreen`, `StatsHeader` |
| Quest flow, bottom feedback sheet, completion card | `QuestScreen`, `FeedbackSheet`, `QuestCompleteView` |

## Game rules

- 3 hearts. A wrong answer costs 1 heart and the challenge repeats at the end of the quest.
- Hearts regenerate 1 every 2 minutes, +1 on quest completion, or refill for 30 IP.
- IP: +10 per correct answer, +20 on High Cognitive Load questions, +5 on retries,
  +20 per completed quest, +15 for a flawless quest.
- Over 80% accuracy across your last 10 answers (minimum 5), upcoming questions
  swap to High Cognitive Load variants where the flag is buried in ordinary dialogue.
- Every miss is logged per flag (e.g. Verb Tense Shift). Review nodes guarantee
  extra drills on your weakest flag and weight the rest by your misses.
  Tap the chart icon in the header to see your Calibration Profile.
