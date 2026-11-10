# Notes from playing the app

Things I noticed while playing as a player. Shot names are in brackets.

## Overall impressions

- The core loop is fun once you're in it: the blunder moment (red squares, threat arrow, "Blunder on move N") is clear, and growth arrows on the board work well.
- The biggest problem is **naming and side confusion**. Opening names often don't match the side or the round:
  - Two tiles or rows share one name: "Italian · Shaky" twice in the tutorial [A45], and "Sicilian · Learning 195" twice for the owner [B04, B92, B94]. White's Smith-Morra and Black's Sicilian can't be told apart.
  - The end-screen title says "Any Opening" when a specific opening was played [A18, A31, B28].
  - The ratings rows on a Black game say "Italian Game" [A31].
  - The White Playbook lists QGD, Slav, Semi-Slav, Benoni and QGA, which read as Black openings [B40]. The Black Playbook lists King's Indian Attack [B44].
  - Import results say "Indian Defence · As White" and "French Defence · As White" [B48].
- **Eval sign and perspective** is unclear throughout:
  - Answer rows show normal book moves as red negatives (−0.1 for cxd4 at 99%) while the eval bar reads positive [A12, A35, B64, B125].
  - Material chips like "+3 black" sit beside the evals [B77].
- **Tip bubbles cover the controls they describe**: the lens bar [A30], the side switch [A23], the White/Black switch [A76] and answer rows [A10].
- Several numbers have no label: the "7"/"2" badge on end screens, "102"/"104" in the Growth header, "195" on the opening page and "0" in the Middlegame header.

## Visually broken

- [A10] The "Prep complete" callout is drawn over the "Adding new moves" header, so the two texts overlap.
- [B63] The "Autoplay" rim tab overlaps the "1. e4 c5 2. d4 cxd4" caption.
- [B64, B65] Move-strip chips sit on top of the "Adding new moves" rim tab, and the tab text peeks out between chips.
- [B33] During the end transition, the "Ended on move 5" banner is ghosted underneath the lens bar.
- [B71] During the Middlegame intro the board is mis-cropped inside its rim (rank 8 and the h-file are cut).
- [A37] After "1 more", the answer list scrolls inside a short box with the top row half cut off. Only 2 of 4 answers get board arrows.
- [A43] A long opening name wraps to 3 lines in the Analysis header and pushes the board down.
- [B14] The breadcrumb "Smith-Morra Gambit" is cut to "Smitl" by the Both/W/B control.

## Confusing flows and dead ends

- **Tutorial**
  - [A05] "Your line is done" and "Prep complete" appear after 2 moves, but the arrows keep asking for more moves.
  - [A07→A08] Off-arrow moves (d4, Bxf7+) are silently ignored, with no shake or cue.
  - [A51] After 5/5 games the header still says "Tutorial ▬ Skip".
- **Next run**
  - [A48, A49] After a complete prep, Next run autoplays the whole prep ("The moves up to your QGD were played for you") and lands on Prep complete again. There is nothing to play.
  - [B122–B124] The rating card (+32 → 212) shows for under a second before the round card. It's easy to miss.
- **Ending rounds**
  - [B33] ✕ mid-run ends the round immediately, with no "End round?" confirmation.
  - [B85, B88] Endgame "Give up" also has no confirmation.
- **Drill**
  - [B18] Home showed White, but the Drill started me as Black against 1.f4.
  - [B18] It went straight into "Adding new moves" on move 1, with no prep first.
- **Freeform off-prep**
  - [B31] Playing off prep (2.Nc3) gives no on-board feedback, only "1 miss so far" in a corner.
  - [B34] The end-screen "Move 2 · You played Nc3 · your prep Nf3 ›" row does nothing visible when tapped.
- **Growth**
  - [B67, B68] "Save Line" closes the sitting back to the Playbook with no toast. The line count changes silently (5→6). The difference between Save Line and Done is unclear.
  - [B125] Tapping a Recommendation drops straight into a Growth sitting with no intro.
  - [B125] The most-played move (c4, 56%) wears a red "Closes off your habit" tag, while a 6% move gets green "Your habit". The colours push toward the rarer move without explaining why.
- **Middlegame**
  - [B70, B71] It opens on a blank spinner and then a random deep position (Ruy › Berlin › Rio Gambit Accepted, move 14), with setup hidden behind a sliders icon.
  - [B77] Hanging a bishop (d5?? Nxe3) wasn't flagged; only the counter moved.
- **Playbook**
  - [B56, B57] The only item in the line page's "…" menu is "Delete everything as White". A two-tap confirm protects it, but it's surprising on a single line's page.
  - [B114] Profile Rename/Reset are only reachable by long-pressing — undiscoverable.
  - [B42] Tidy opened from the Black tab defaults to the White Ruy Lopez. The Tidy pill shows a green dot even when there is nothing to tidy.
- **Opening picker and search**
  - [B15] With the keyboard up, no search results are visible: the board, selection card and field fill the space.
  - [B08–B14] The board takes most of the browse sheet, the list starts below the fold, and the chip row is clipped ("Bo…").
- **Import**: [B48] Each row shows two checkbox-like squares (the selector and the side swatch). The "1...e5" row has no name, and no game counts are shown.

## Stats and number inconsistencies

- [B92 vs B01/B03] Stats shows a "1 day streak", the Home Milestones card shows "0 days", and the Milestones detail shows "3 days" as earned.
- [A56, B92] The activity grid covers 18 weeks while the headline says "N rounds in 30 days". The 30/90/Year switch sits outside the card, under the grid.
- [A18, B28, B34] End-screen "Moves survived" rows:
  - Every name the game passed through gets its own row (King's Pawn → Vienna → Petrov → Four Knights…), up to 11 rows for one game.
  - Many rows read "0 runs · 1 ended · best 0", which looks contradictory.
- [A77] The empty Stats "Play" chart is a blank dashed box, while Accuracy says "Nothing yet".
- [B117] Settings says "Last backup Nov 9 at 8:32 PM", but Restore says "iCloud is off on this device".
- [B28] An Ng4 at −0.94 counts as a "Blunder" and ends the run. The threshold feels harsh for about a one-pawn slip.

## Smaller notes

- [A41, B22] Lenses only work while held, and nothing says so; a tap flashes and vanishes. The Pieces lens rings nearly every piece and tints every square, which makes it very busy.
- [B22, B25] Opening Plan hides the turns/goal card, so you can't see both.
- [A57, B98, B105] Engine lines are shallow (d5–d7). At the start they show the same moves transposed with 4.Be3 everywhere. In the Najdorf the top line is 6.Bd3 Bg4 7.f3.
- [B96] The Reference explorer lists all 20 first moves, including ones under 1%, before reaching the games. Draw percentages are missing on most bars.
- [A75] On an empty Home, Freeform/Drill and the picker look active, and "No answer yet · First move 1.?" is cryptic.
- [B82] Endgame rows share names ("Key squares" ×2, "Opposition" ×2) and differ only by a Win/Hold Draw tag. The green "Win" reads like a past result.
- [B88] The endgame end screen is sparse: no move review and no correct technique.
- [B52] The mini boards for Black slots are drawn from White's side, and "1...e5 · 1 move" barely counts as an opening.
- [B03] Milestones have no earned vs in-progress labels, and tapping one does nothing.
- The app is dark-only (`.preferredColorScheme(.dark)` in `ChessPlaybookApp.swift`), so there are no light-mode shots.

## Not captured, and why

- **Missed mate**: I couldn't steer a run into one within the session.
- **Extensions pill and extension graph view**: the pill only shows when the profile has extensions, and the owner's profile has none. `ExtensionGraphView` wasn't reachable.
- **Play settings, engine level and tips sub-pages**: they don't exist; Settings has only Board, Play (Move scores, Moves per fill), Profiles, iCloud and Export.
- **Undo/Done in in-Play growth for the owner profile**: covered only by tutorial shots [A10–A15, A35–A39] and the Growth sitting [B64–B67].
- **Confirmed delete/reset dialogs**: I deliberately didn't confirm them.
- **Import step after "Add 1 opening"**: I didn't add, to avoid changing the Playbook.

Side effect, simulator only: closing the last Growth sitting with "tap Close" hit "Closes off your habit" and added 1.d4 Nf6 2.c4 to the simulator copy of the owner's profile. Nothing on a real device or in iCloud was touched.
