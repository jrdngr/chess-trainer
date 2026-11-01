# Animations: web → iOS

Every motion in the web prototype, where it lives, and its native port.
All ported motion honors Reduce Motion (`accessibilityReduceMotion`), as the
web honors `prefers-reduced-motion`. Shared helpers are in `App/Motion/`.

## Keyframe animations (27)

| Web | Source | iOS | Status |
|---|---|---|---|
| `roundIntro` cover fade (2.5s) | styles.css, RoundIntro.tsx | `IntroCoverFade` | Ported |
| `riMode` mode name in | styles.css | `IntroModeIn` | Ported |
| `riOpening` opening name in | styles.css | `.arriving(delay: 0.25)` | Ported |
| `introPill` | styles.css | `IntroPillIn` | Ported |
| `introPulse` (board ring after replay) | styles.css | `IntroPulse` | Ported |
| `boardFlash` (notes, miss, verdict, end of book) | board.css | `BoardFlashFade` / `.boardFlash()` | Ported |
| `moveScore` (move score float) | board.css | `MoveScoreFloat` | Ported |
| `undefendedPulse` | board.css | `FlashRings` | Ported (earlier) |
| `ratingDelta` | styles.css | `DeltaPop` | Ported |
| `tierPop` | styles.css | `TierPop` | Ported |
| `stretchGlow` | styles.css | `StretchGlow` | Ported |
| `ratingFlash` | styles.css | `RatingFlash` | Ported |
| `ratingSpark` (16 sparks) | styles.css | `SparkBurst` | Ported |
| `ratingRing` | styles.css | `PromotionRing` | Ported |
| `ratingShine` | styles.css | `PromotionShine` | Ported |
| `ratingNumGlow` | styles.css | `NumberGlow` | Ported |
| `ratingArrive` | styles.css | `RestingRatingCard` (`Arriving`) | Ported |
| `ratingOverIn` / `ratingOverOut` | styles.css | `RatingOverBoard` | Ported |
| `ratingStamp` | styles.css | `RatingStamp` | Ported |
| `ratingRays` | styles.css | `RatingRays` | Ported |
| `shake` (clock out) | styles.css | `Shake` on `ClockHud`, `SurvivalClock` | Ported |
| `toastIn` | styles.css | `ToastHost` transition | Ported |
| `fade`, `slideUp`, `slideDown` (sheets) | styles.css | System sheets | Native equivalent |
| `spin` | styles.css | `ProgressView` | Native equivalent |

## Timed sequences (JS)

| Web | Source | iOS | Status |
|---|---|---|---|
| Round intro: announce 2500ms, replay 400ms/move, pulse 900ms | RoundIntro.tsx | `RunModel`, Drill/Growth intros | Ported |
| Rating playback: lead 700, grow 900, top 650, flash 760, regrow 700, hold 1100, ease-out count, haptics | RatingCard.tsx `usePlayback` | `RatingPlayer` | Ported |
| End card: wait → play → leave (320ms) → placed; verdict 2000ms | survival/End.tsx | `EndView` `RatingStage` | Ported |
| Survival miss 2000 / score 1400 / note 1600 / flash 1300 | SurvivalScreen.tsx | `RunModel` | Ported (earlier) |
| Drill flash 650 / 500, reply 450; board reply 350 | drill/*.tsx, BoardScreen.tsx | Drill models, BoardBuild | Ported (earlier) |

## Transitions

| Web | Source | iOS | Status |
|---|---|---|---|
| Piece slide 0.16s cubic(0.3,0.9,0.4,1) | board.css `.piece` | `PieceTracker` + `Motion.slide` | Ported |
| Board dim (`filter` 0.2s) | board.css `.dimmed` | `.dimmed()` | Ported |
| Board glow (`box-shadow` 0.8s) | board.css `.glow` | `glowBorder` animation | Ported |
| Eval bar width 0.35s | styles.css `.evalbar` | `EvalBar` | Ported (earlier) |
| Milestone / rank bar fill 0.7s | styles.css `.milestone .fill` | `RankBar` | Ported |
| Rating bar width (playback speed) | RatingCard.tsx | `RatingTrack` | Ported |
| Plan card chevron 0.15s | board.css `.plan-chev` | `PlanCard` | Ported |
| Press states (`:active` scale/background, 0.08–0.15s) on buttons, tiles, rows | styles.css | SwiftUI button styles | Native equivalent |
| Switch, segmented, nav color 0.15–0.18s | styles.css | `Toggle`, `SegmentedControl`, TabView | Native equivalent |
| `.build-replies` shadow 0.2s | board.css | — | Not ported (minor) |
| `.progress-fill` width 0.3s | styles.css | — | Unused on the web |

## Debug

`RATING_MOMENT=240,262` (Debug builds) plays that rating change on the end
screen: `OPEN_MODE=survival SURVIVAL_SCREEN=end SURVIVAL_PAST=3`.
