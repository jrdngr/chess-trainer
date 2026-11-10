# UI review shots

iPhone 18 Pro, iOS 27.0, Debug build of main@e611e01. Pass A = fresh install; Pass B = owner profile 2026-11-06 written into the app container. Views are best guesses under ios/App/.

| File | Screen | How | View |
|---|---|---|---|
| A01-welcome.png | Welcome intro page | fresh install → launch | Onboarding/WelcomeView.swift |
| A02-your-openings.png | "Your openings" first question | Get started | Onboarding/OnboardingView.swift |
| A03-recommend-sets.png | Tutorial game 1 start, flash-card tip | Recommend some openings | Views/RunView.swift, Views/TipBubble.swift |
| A04-tutorial-first-move.png | Tutorial g1: prep-bar tip | play 1.e4 | Views/RunView.swift |
| A05-tutorial-move2.png | Tutorial g1: "Prep complete" + "Your line is done" tip | play 2.Nf3 | Views/RunView.swift, Views/BoardRim.swift |
| A06-tutorial-move3.png | Tutorial g1: ✓ common-move tip | play 3.Bc4 | Views/RunView.swift |
| A07-tutorial-move4.png | Tutorial g1: past the line | play 4.c3 | Views/RunView.swift |
| A08-tutorial-move5.png | Tutorial g1: round over, Next run tip, −24 score float | play 5.d3 | Views/RunView.swift, Motion/MoveScoreFloat.swift |
| A09-next-run.png | Tutorial g2 start (after Next run) | Next run | Views/RunView.swift |
| A10-run2-move2.png | Tutorial g2: growth "Adding new moves" + extend tip | play e4, Nf3 | Views/RunView.swift, Views/InlineFillPanel.swift |
| A11-growth-panel-settled.png | Growth panel settled | wait | Views/InlineFillPanel.swift |
| A12-growth-answer-panel.png | Growth answer row with eval | dismiss tip | Growth/HoleAnswers.swift |
| A13-growth-after-answer.png | Growth: 1 of 2 added, Done tip | tap Bc4 row | Views/InlineFillPanel.swift |
| A14-growth-answer-rows.png | Growth answer rows (c3) | dismiss tip | Growth/HoleAnswers.swift |
| A15-growth-2-of-2.png | Growth: "new moves are saved" tip | play c3 | Views/RunView.swift |
| A16-after-prep.png | Tutorial g2 after prep | play d3 | Views/RunView.swift |
| A17-run2-past-line.png | Tutorial g2: "End the run" tip, −5 float | O-O, Re1 | Views/RunView.swift |
| A18-after-run2-end.png | End-of-round screen top (tutorial) | tap ✕ | Views/EndView.swift, Survival/SurvivalEndParts.swift |
| A19-end-screen-middle.png | End-of-round middle | scroll | Survival/SurvivalEndParts.swift |
| A20-end-screen-bottom.png | End-of-round bottom (moves survived, copy) | scroll | Survival/SurvivalEndParts.swift |
| A21-home-tutorial-step3.png | Home during tutorial (2 of 5) | Back Home | Views/HomeView.swift |
| A22-play-as-sheet.png | "Play as" side sheet | tap Side | Common/SelectionSheets.swift |
| A23-home-black.png | Home: "Now play as Black" tip | pick Black | Views/HomeView.swift |
| A24-game3-start.png | Tutorial g3 (Black) start | Play | Views/RunView.swift |
| A25-game3-line.png | Tutorial g3: line played | ...e5, ...Nc6 | Views/RunView.swift |
| A26-game3-after-prep.png | Tutorial g3: after prep | wait | Views/RunView.swift |
| A27-game3-past-line.png | Tutorial g3: past the line | ...Bc5, ...Nf6 | Views/RunView.swift |
| A28-game3-scored-move.png | Tutorial g3: first scored move, ✓ ×2 streak | ...exd4 | Views/RunView.swift |
| A29-game3-move2.png | Tutorial g3: move-score tip | ...d5 | Views/RunView.swift |
| A30-game3-move3.png | Blunder ending: threat arrow, "Blunder on move 7" | ...gxf6 | Views/RunView.swift, Survival/EndVerdict.swift |
| A31-game3-end-top.png | End-of-round top after blunder | Continue | Views/EndView.swift |
| A32-game3-end-middle.png | End-of-round middle | scroll | Survival/SurvivalEndParts.swift |
| A33-game3-end-bottom.png | End-of-round bottom | scroll | Survival/SurvivalEndParts.swift |
| A34-home-tutorial-step4.png | Home tutorial step 4 tip | Back Home | Views/HomeView.swift |
| A35-game4-growth-any.png | Tutorial g4: pick-any growth, 3 answers | Play, ...e5 ...Nc6 | Views/InlineFillPanel.swift |
| A36-growth-three-answers.png | Growth answers without tip | dismiss tip | Growth/HoleAnswers.swift |
| A37-growth-one-more.png | Growth "1 more" expanded list (clipped) | tap 1 more | Growth/HoleAnswers.swift |
| A38-game4-second-answer.png | Growth second answer step | play ...Nf6 | Growth/HoleAnswers.swift |
| A39-game4-growth-done.png | Growth done: "Keep playing" tip | tap Bc5 row | Views/RunView.swift |
| A40-game4-freeplay.png | Tutorial g4 freeplay | ...d6 | Views/RunView.swift |
| A41-lens-eval.png | Lens held (pawns/pieces/kings/eval) and Plan toggled | hold lens buttons / tap Plan | Views/LensBar.swift, Views/LensMarksView.swift, Analysis/PlanCard.swift |
| A41-lens-kings.png | Lens held (pawns/pieces/kings/eval) and Plan toggled | hold lens buttons / tap Plan | Views/LensBar.swift, Views/LensMarksView.swift, Analysis/PlanCard.swift |
| A41-lens-pawns.png | Lens held (pawns/pieces/kings/eval) and Plan toggled | hold lens buttons / tap Plan | Views/LensBar.swift, Views/LensMarksView.swift, Analysis/PlanCard.swift |
| A41-lens-pieces.png | Lens held (pawns/pieces/kings/eval) and Plan toggled | hold lens buttons / tap Plan | Views/LensBar.swift, Views/LensMarksView.swift, Analysis/PlanCard.swift |
| A41-lens-plan.png | Lens held (pawns/pieces/kings/eval) and Plan toggled | hold lens buttons / tap Plan | Views/LensBar.swift, Views/LensMarksView.swift, Analysis/PlanCard.swift |
| A42-game4-blunder.png | Tutorial g4 blunder | ...Nb4 | Views/RunView.swift |
| A43-analyze-from-blunder.png | Analyze from blunder | Analyze | Analysis/AnalysisTab.swift |
| A44-home-tutorial-step5.png | Home tutorial step 5 tip (pick an opening) | Back, Back Home | Views/HomeView.swift |
| A45-opening-picker-tutorial.png | Opening picker during tutorial (Black) | tap Any Opening | Common/BrowsePicker.swift |
| A46-home-qgd-picked.png | Home with QGD picked | pick QGD | Views/HomeView.swift |
| A47-game5-past-prep.png | Tutorial g5: past prep tip + Next run | Play, ...d5 ...e6 | Views/RunView.swift |
| A48-next-run-rating-1.png | Next run sequence frames | tap Next run | Views/RunView.swift, Views/RatingPlayback.swift |
| A48-next-run-rating-2.png | Next run sequence frames | tap Next run | Views/RunView.swift, Views/RatingPlayback.swift |
| A48-next-run-rating-3.png | Next run sequence frames | tap Next run | Views/RunView.swift, Views/RatingPlayback.swift |
| A49-next-run-rating-end.png | Next run end state (prep autoplayed) | wait | Views/RunView.swift |
| A50-tutorial-done-end.png | End screen, tutorial done | ✕ | Views/EndView.swift |
| A51-home-after-tutorial.png | Home after tutorial (5 of 5) | Back Home | Views/HomeView.swift |
| A52-playbook-tip.png | Playbook first-visit tip | Playbook tab | Playbook/PlaybookView.swift |
| A53-playbook-tip2.png | Playbook tip 2 (Import) | dismiss tip | Playbook/PlaybookView.swift |
| A54-playbook-tip4.png | Playbook tip (tap/swipe opening) | dismiss tip | Playbook/PlaybookView.swift |
| A55-playbook-white-after-tutorial.png | Playbook after tips | dismiss | Playbook/PlaybookView.swift |
| A56-stats-new-player-2.png | Stats after tutorial (scrolled) | Stats tab, scroll | Stats/StatsView.swift |
| A56-stats-new-player-3.png | Stats after tutorial (scrolled) | Stats tab, scroll | Stats/StatsView.swift |
| A56-stats-new-player-4.png | Stats after tutorial (scrolled) | Stats tab, scroll | Stats/StatsView.swift |
| A56-stats-new-player.png | Stats after tutorial (scrolled) | Stats tab, scroll | Stats/StatsView.swift |
| A57-analysis-new-player.png | Analysis, new player | Analysis tab | Analysis/AnalysisTab.swift |
| A58-settings-new-player-2.png | Settings, new player (top, scrolled) | Home ⚙ | Shell/SettingsSheet.swift |
| A58-settings-new-player.png | Settings, new player (top, scrolled) | Home ⚙ | Shell/SettingsSheet.swift |
| A60-choose-own-white.png | Choose my own: three slots | wipe, Get started, Choose my own | Onboarding/TutorialOpeningsViews.swift |
| A61-choose-white-list.png | Choose White list | tap White slot | Onboarding/TutorialOpeningsViews.swift |
| A62-choose-more-openings.png | More openings browser | More openings | Common/BrowsePicker.swift |
| A63-choose-more-after-e4.png | Browser after 1.e4 | tap 1.e4 | Common/BrowsePicker.swift |
| A64-choose-own-white-picked.png | Slots with Ruy Lopez picked | pick Ruy Lopez | Onboarding/TutorialOpeningsViews.swift |
| A65-choose-against-e4.png | Choose against 1.e4 | tap slot | Onboarding/TutorialOpeningsViews.swift |
| A66-choose-against-d4.png | Choose against 1.d4 | pick Sicilian, tap slot | Onboarding/TutorialOpeningsViews.swift |
| A67-choose-own-all-picked.png | All slots picked | pick Slav | Onboarding/TutorialOpeningsViews.swift |
| A68-choose-own-continue.png | Tutorial starts with chosen Ruy | Continue | Views/RunView.swift |
| A70-skip-first.png | Skip → "Choose your openings" (+ sheet) | wipe, Get started, Skip | Playbook/PlaybookSheets.swift |
| A71-suggest-set.png | Suggest a set: styles | Suggest a set | Onboarding/StarterSetViews.swift |
| A72-pick-openings.png | Pick openings browser | Pick openings | Onboarding/PickOpeningsView.swift |
| A73-play-on-board.png | Play on the board builder | Play on the board | Common/BoardBuildView.swift |
| A74-import-games.png | Import my games | Import my games | Import/ImportView.swift |
| A75-home-empty.png | Home empty state | close sheet | Views/HomeView.swift |
| A76-playbook-empty.png | Playbook empty state | Playbook tab | Playbook/PlaybookView.swift |
| A77-stats-empty-2.png | Stats empty state (top, scrolled) | Stats tab | Stats/StatsView.swift |
| A77-stats-empty.png | Stats empty state (top, scrolled) | Stats tab | Stats/StatsView.swift |
| A78-analysis-empty.png | Analysis empty state | Analysis tab | Analysis/AnalysisTab.swift |
| B01-home-top.png | Home, owner profile (fits one page) | profile loaded into container, launch | Views/HomeView.swift |
| B02-recommendations-more.png | Recommendations "More" page | Home › More | Home/RecommendationsCard.swift |
| B03-milestones-detail.png | Milestones detail sheet | Home › Milestones | Home/MilestonesCard.swift |
| B04-picker-white.png | Opening picker (White) | Home › Any Opening | Common/BrowsePicker.swift |
| B05-picker-show-all.png | Picker "Show all" | Show all 11 | Common/BrowsePicker.swift |
| B06-picker-black.png | Picker Black tab | Black | Common/BrowsePicker.swift |
| B07-picker-recent.png | Picker Recent page | Show all 1 | Common/BrowsePickerParts.swift |
| B08-picker-browse.png | Browse all openings | Browse all openings | Common/BrowseList.swift |
| B09-browse-mylines.png | Browse: My lines | My lines chip | Common/BrowseList.swift |
| B10-browse-suggestions.png | Browse: Suggestions | Suggestions chip | Common/BrowseList.swift |
| B11-browse-shelves.png | Browse: Shelves | Shelves chip | Common/BrowseList.swift |
| B12-browse-book.png | Browse: Book | Book chip | Common/BrowseList.swift |
| B13-browse-sicilian-family.png | Browse: Sicilian family rows | Book › Sicilian | Common/BrowseList.swift |
| B14-browse-smith-morra.png | Browse: Smith-Morra family | tap Smith-Morra | Common/BrowseList.swift |
| B15-picker-search.png | Picker search with keyboard | search "caro" | Common/BrowsePicker.swift |
| B16-picker-search-results.png | Search results | dismiss keyboard | Common/BrowsePicker.swift |
| B17-picker-search-pick.png | Search result picked | tap Caro-Kann Main Line | Common/BrowsePicker.swift |
| B18-play-drill-start.png | Play Drill start (growth on move 1) | Home › Play (Drill, Any) | Views/RunView.swift |
| B19-play-after-done.png | Play after Done: turns/goal card | Done | Views/RunView.swift, Survival/GoalCard.swift |
| B20-play-move-score-float.png | Move score float | ...d5 | Motion/MoveScoreFloat.swift |
| B21-play-midrun.png | Mid-run | ...Nf6 | Views/RunView.swift |
| B22-play-eval-lens.png | Eval lens held | hold Eval | Views/EvalLensViews.swift |
| B23-play-pawns-lens.png | Pawns lens held | hold Pawns | Views/LensMarksView.swift |
| B24-play-kings-lens.png | Kings lens held | hold Kings | Views/LensMarksView.swift |
| B25-play-plan-lens.png | Plan lens | tap Plan | Analysis/PlanCard.swift |
| B26-play-blunder.png | Blunder on move 3 | ...Ng4 | Views/RunView.swift |
| B27-end-rating-anim.png | End-of-round, transition frame | Continue | Views/EndView.swift |
| B28-end-scroll-2.png | End-of-round top / scrolled (engine vs you, moves survived) | scroll | Survival/SurvivalEndParts.swift |
| B28-end-top.png | End-of-round top / scrolled (engine vs you, moves survived) | scroll | Survival/SurvivalEndParts.swift |
| B29-home-freeform-ruy.png | Home: Freeform + Ruy Lopez selected | Side White, Freeform, pick Ruy | Views/HomeView.swift, Home/PlaySelector.swift |
| B30-play-freeform-start.png | Freeform run start | Play | Views/RunView.swift |
| B31-play-off-prep.png | Off-prep moment (2.Nc3), "1 miss so far" | e4, Nc3 | Views/RunView.swift |
| B32-play-freeform-mid.png | Freeform mid-run, ×2 streak | Nf3, Bc4 | Views/RunView.swift |
| B33-freeform-end-top.png | Freeform end top (no End-round confirm) | tap ✕ | Views/EndView.swift |
| B34-freeform-end-scroll-2.png | Freeform end scrolled: missed prep, moves survived | scroll | Survival/SurvivalEndParts.swift |
| B34-freeform-end-scroll-3.png | Freeform end scrolled: missed prep, moves survived | scroll | Survival/SurvivalEndParts.swift |
| B40-playbook-white.png | Playbook White | Playbook tab | Playbook/PlaybookView.swift |
| B41-playbook-black.png | Playbook Black | Black | Playbook/PlaybookView.swift |
| B42-playbook-tidy.png | Tidy page (nothing to tidy) | Tidy pill | Playbook/TidyView.swift |
| B43-tidy-opening-menu.png | Tidy opening chooser | tap opening field | Common/BrowsePicker.swift |
| B44-playbook-more-menu.png | Playbook … menu | … | Playbook/PlaybookView.swift |
| B45-import-step1.png | Import step 1 | … › Import my games | Import/ImportView.swift |
| B46-import-username.png | Import username entered | type DrNykterstein | Import/ImportView.swift |
| B47-import-loading.png | Import loading | Find my openings | Import/ImportParts.swift |
| B48-import-results.png | Import results | wait | Import/ImportParts.swift |
| B49-import-row-tapped.png | Import row selected | tap row | Import/ImportParts.swift |
| B50-playbook-plus-sheet.png | Playbook + sheet | + | Playbook/PlaybookSheets.swift |
| B51-suggest-set-styles.png | Suggest a set styles | Suggest a set | Onboarding/StarterSetViews.swift |
| B52-suggest-set-classical.png | Classical set detail | Classical | Onboarding/StarterSetViews.swift |
| B53-opening-page.png | Opening page (Sicilian) | tap Sicilian Defence | Playbook/OpeningPage.swift |
| B54-opening-page-menu.png | Opening page … menu | … | Playbook/OpeningPage.swift |
| B55-line-page.png | Line page (Smith-Morra Accepted) | tap line | Playbook/RepertoireBrowser.swift |
| B56-line-page-menu.png | Line page … menu (Delete everything as White) | … | Playbook/RepertoireBrowser.swift |
| B57-delete-white-confirm.png | Delete-White confirm sheet (not confirmed) / line page | tap Delete everything | Playbook/PlaybookSheets.swift |
| B57-line-page-move2.png | Delete-White confirm sheet (not confirmed) / line page | tap Delete everything | Playbook/PlaybookSheets.swift |
| B59-whole-tree.png | Whole tree page | Whole tree | Playbook/RepertoireBrowser.swift |
| B60-node-menu.png | Node menu (e4) | … on row | Playbook/NodeMenu.swift |
| B61-add-note-sheet.png | Add note sheet | Add note | Playbook/NodeMenu.swift |
| B62-whole-tree-menu.png | Whole tree … menu | … | Playbook/RepertoireBrowser.swift |
| B63-grow-intro.png | Growth sitting intro (autoplay) | Opening page › Grow | Growth/GrowthSitting.swift, Growth/GrowthModel+Intro.swift |
| B64-grow-hole.png | Growth hole: answers with habit tags | wait | Growth/GrowthPhaseView.swift, Growth/HoleAnswers.swift |
| B65-grow-reveal.png | Growth reveal / next hole | tap cxd4 | Growth/GrowthReveal.swift |
| B67-grow-end.png | Growth end: added, Undo / Add more / Play from here | Done | Growth/GrowthModel+End.swift |
| B68-after-save-line.png | Back on Playbook after Save Line | Save Line | Playbook/PlaybookView.swift |
| B70-middlegame-loading.png | Middlegame loading spinner | Home › Middlegame | Middlegame/MiddlegameView.swift |
| B71-middlegame-start.png | Middlegame intro autoplay | wait | Middlegame/MiddlegameView.swift |
| B72-middlegame-settled.png | Middlegame settled | wait | Middlegame/MiddlegameView.swift |
| B73-middlegame-setup-sheet.png | Middlegame setup sheet | sliders icon | Middlegame/MiddlegameSetupView.swift |
| B74-middlegame-plan.png | Middlegame round with goal card | close setup | Middlegame/MiddlegameView.swift |
| B75-middlegame-plan-card.png | Middlegame plan card | Plan | Analysis/PlanCard.swift |
| B76-middlegame-eval-lens.png | Middlegame eval lens | hold Eval | Views/EvalLensViews.swift |
| B77-middlegame-after-move.png | Middlegame after hanging a piece (no flag) | d5 | Middlegame/MiddlegameView.swift |
| B78-middlegame-blunder.png | Middlegame blunder | fxe3, Qd4 | Middlegame/MiddlegameView.swift |
| B79-middlegame-end.png | Middlegame end top | Continue | Middlegame/HandoffViews.swift |
| B80-middlegame-end-2.png | Middlegame end scrolled | scroll | Middlegame/HandoffViews.swift |
| B81-middlegame-end-handoff.png | Middlegame end: Handoff tab | Handoff | Middlegame/HandoffViews.swift |
| B82-endgames-library.png | Endgames library | Home › Endgames | Endgame/EndgameView.swift |
| B83-endgames-library-2.png | Endgames library scrolled | scroll | Endgame/EndgameView.swift |
| B83-endgames-library-3.png | Endgames library scrolled | scroll | Endgame/EndgameView.swift |
| B84-endgame-lesson-1.png | Endgame lesson pages (Queen mate; Win) | Queen mate › Next… | Endgame/EndgameView.swift |
| B84-endgame-lesson-2.png | Endgame lesson pages (Queen mate; Win) | Queen mate › Next… | Endgame/EndgameView.swift |
| B84-endgame-lesson-3.png | Endgame lesson pages (Queen mate; Win) | Queen mate › Next… | Endgame/EndgameView.swift |
| B84-endgame-lesson-4.png | Endgame lesson pages (Queen mate; Win) | Queen mate › Next… | Endgame/EndgameView.swift |
| B84-endgame-lesson-p11.png | Endgame lesson pages (Queen mate; Win) | Queen mate › Next… | Endgame/EndgameView.swift |
| B84-endgame-lesson-p4.png | Endgame lesson pages (Queen mate; Win) | Queen mate › Next… | Endgame/EndgameView.swift |
| B85-endgame-win-round.png | Win-it round start | Play it | Endgame/EndgameGame.swift |
| B86-endgame-plan-lens.png | Endgame plan lens | Plan | Endgame/EndgameGame.swift |
| B87-endgame-win-midround.png | Win-it mid-round | Qc2 | Endgame/EndgameGame.swift |
| B88-endgame-end.png | Endgame end (Resigned) | Give up | Endgame/EndgameGame.swift |
| B89-endgame-hold-lesson-end.png | Hold-it lesson last page (Opposition) | Library › Opposition Hold Draw | Endgame/EndgameView.swift |
| B90-endgame-hold-round.png | Hold-it round | Play it | Endgame/EndgameGame.swift |
| B91-endgame-hold-end.png | Hold-it end | Give up | Endgame/EndgameGame.swift |
| B92-stats-1.png | Stats, owner profile (top → bottom) | Stats tab, scroll | Stats/StatsView.swift |
| B92-stats-2.png | Stats, owner profile (top → bottom) | Stats tab, scroll | Stats/StatsView.swift |
| B92-stats-3.png | Stats, owner profile (top → bottom) | Stats tab, scroll | Stats/StatsView.swift |
| B93-stats-opening-detail-2.png | Stats opening detail (King's Pawn Game) | tap Rated row | Stats/OpeningStatsView.swift |
| B93-stats-opening-detail-3.png | Stats opening detail (King's Pawn Game) | tap Rated row | Stats/OpeningStatsView.swift |
| B93-stats-opening-detail.png | Stats opening detail (King's Pawn Game) | tap Rated row | Stats/OpeningStatsView.swift |
| B94-stats-your-openings.png | Stats "Your openings" show all | Show all 11 | Stats/YourOpeningsView.swift |
| B95-analysis-start.png | Analysis start | Analysis tab | Analysis/AnalysisTab.swift |
| B96-analysis-explorer.png | Analysis reference explorer | scroll | Analysis/ExplorerPanel.swift |
| B97-analysis-reference-games.png | Analysis reference games | scroll | Analysis/ReferenceGamesData.swift |
| B98-analysis-top-engine-lines.png | Analysis top with engine lines | scroll to top | Analysis/EngineViews.swift |
| B99-analysis-line-loaded.png | Analysis with Najdorf line loaded | ANALYSIS_LINE hook | Analysis/AnalysisTab.swift |
| B100-analysis-named-lines.png | Analysis named lines | ANALYSIS_SCROLL=named | Analysis/NamedLines.swift |
| B101-analysis-bottom.png | Analysis bottom | ANALYSIS_SCROLL=bottom | Analysis/AnalysisTab.swift |
| B102-analysis-sheet-pgn.png | PGN sheet | ANALYSIS_SHEET=pgn | Analysis/PgnSheet.swift |
| B103-analysis-sheet-line.png | Named line sheet | ANALYSIS_SHEET=line | Analysis/AnalysisSheets.swift |
| B104-analysis-sheet-save.png | Save line sheet | ANALYSIS_SHEET=save | Common/SaveSheet.swift |
| B105-analysis-sheet-game.png | Reference game sheet | ANALYSIS_SHEET=game (start position) | Analysis/AnalysisSheets.swift |
| B106-board-builder.png | Board builder ("On the board") | Playbook … › Play on the board | Common/BoardBuildView.swift |
| B110-settings-1.png | Settings (top, scrolled) | Home ⚙ | Shell/SettingsSheet.swift |
| B110-settings-2.png | Settings (top, scrolled) | Home ⚙ | Shell/SettingsSheet.swift |
| B111-settings-export.png | Export page | Settings › Export | Shell/ExportView.swift |
| B112-export-share-sheet.png | Export share sheet (dismissed, nothing shared) | Everything | Shell/ExportView.swift |
| B113-new-profile-dialog.png | New profile dialog (cancelled) | New profile | Shell/SettingsSheet.swift |
| B114-profile-context-menu.png | Profile context menu | long-press Main | Shell/SettingsSheet.swift |
| B115-rename-profile-dialog.png | Rename profile dialog (cancelled) | Rename | Shell/SettingsSheet.swift |
| B116-reset-profile-confirm.png | Reset profile confirm (cancelled) | long-press › Reset | Shell/SettingsSheet.swift |
| B117-restore-icloud.png | Restore from iCloud | Restore from iCloud | Shell/RestoreView.swift |
| B120-play-prep-in-progress.png | Drill run in prep | OPEN_MODE=autopilot RATING_MOMENT=180,212; e4 Nf3 Bb5 Ba4 | Views/RunView.swift |
| B121-play-prep-complete.png | Prep complete + Next run | O-O | Views/RunView.swift |
| B122-next-run-rating-card.png | Next run rating card (+32 → 212) | Next run, ~0.3s | Views/RatingCardView.swift |
| B123-next-run-round-card.png | Next run round card | ~0.8s | Views/RunView.swift |
| B124-next-run-new-board.png | New run board | ~1.5s | Views/RunView.swift |
| B125-growth-from-recommendation.png | Growth sitting from a Recommendation | Home › Indian Defence row | Growth/GrowthSitting.swift |
