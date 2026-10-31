# Tools

The screens around the modes: Stats, Import and Analysis, the Extensions
review, the Save sheet, and Play on the board. The rules are in
`src/model/stats.ts`, `gameAnalysis.ts`, `repair.ts`, `extensionGraph.ts`,
`extensions.ts` and `boardBuilder.ts`, and in `src/components/SaveSheet.tsx`.

## Stats

**TOOL-1** · port
The Stats tab opens on your favorites, best rated first, each with the rung
it holds; a favorite never rated is still listed, last. Under them come the
other openings Survival has rated, best first; one never rated is not listed.
Source: `stats.starredOpenings`, `stats.ratedOpenings`, `StatsScreen`
Cases: `stats.ladders`

**TOOL-2** · port
The charts read one window (30 days, 90 days or a year; 30 to start): rounds
played each day, the rating at each day's end (a day it did not move holds the
day before's, and an opening never rated has no line), and accuracy over the 7
days ending each day, with days that have nothing to average left out. The
count of recent rounds is over the same window.
Source: `stats.dailyRounds`, `stats.ratingOverTime`, `stats.rollingAccuracy`, `stats.recentRounds`
Cases: `stats.series`

**TOOL-3** · port
An opening's page says how it ranks among its siblings by rounds played
lately ("your second favorite Sicilian"); siblings never played are left out
of the count.
Source: `stats.favouriteness`
Cases: `stats.favouriteness`

**TOOL-4** · port
A chart's axis has a few round numbers that cover the range.
Source: `stats.niceTicks`
Cases: `stats.niceTicks`

## Import and Analysis

**TOOL-5** · port
Imported games for one side are folded into a tree of the positions you
reached, with games, wins, draws and losses at each and the moves you chose
there. Games of the other color are left out.
Source: `gameAnalysis.buildPlayerTree`
Cases: `gameAnalysis.buildPlayerTree`

**TOOL-6** · port
Analysis compares that tree with your Playbook, at positions reached in at
least 2 games, where it is your move: a gap is a position with nothing
prepared (scored by games, less the deeper it is, more the more you lost); a
deviation is one where you played something other than your prep (1.5 per
off-prep game); unplayed prep comes last. The 40 highest are shown.
Source: `gameAnalysis.analyseAgainstRepertoire`, `ImportScreen`
Cases: `gameAnalysis.analyseAgainstRepertoire`

**TOOL-7** · port
Coverage counts the games of your side that stayed in your Playbook for at
least 6 plies, and the average ply where games left it.
Source: `gameAnalysis.measureCoverage`
Cases: `gameAnalysis.measureCoverage`

**TOOL-8** · port
The evidence Autopilot reads (see AUTO-18): off-prep positions from your games
(weighted by games × 1.5 × (1 + how often they lost, a draw half a loss)) and
positions you kept reaching unprepared (weighted by games × (1 + that)), at 2
games or more; then every mistake logged in the app at a position where you
had a move, as an off-prep item weighted 2.5, newest first.
Source: `repair.buildRepairs`, `repair.costOf`, `store/recommendation.evidenceIn`
Cases: `repair.buildRepairs`, `const:DEFAULT_MIN_GAMES`

## Extensions review

**TOOL-9** · port
The review draws one opening as a grid: a column per half-move from the
opening's root, rows depth first, a node's first child carrying on along its
row and each other child on a new row below the subtree before it. At your
move the move you play comes first, then book moves, extensions, and mistakes
last; at the opponent's, book replies by share, extensions last. A move into
a position drawn higher up ends its row with a join; a line past 16 plies
ends in "+N". The Extensions filter keeps only the paths down to an extension.
Source: `extensionGraph.layoutGraph`, `extensionGraph.orderedKids`; extensions-design (10-24)
Cases: `extensionGraph.layoutGraph`, `extensionGraph.orderedKids`, `const:MAX_PLIES`

**TOOL-10** · port
Keep and Remove act on the whole extension a move belongs to, from its first
move off the book. Remove can be undone from its toast. A kept extension
reads as reviewed until a move under it is added after the keep. A mistake of
yours can be switched to the book's move.
Source: `extensionGraph.extensionRoots`, `extensionGraph.keptCurrent`, `ExtensionsScreen`
Cases: `extensionGraph.extensionRoots`, `extensionGraph.keptCurrent`

## The Save sheet

**TOOL-11** · port
Every line saved by hand goes through one sheet. It splits the line where it
leaves the book: the Playbook part, and the extension under it, which the
engine checks as the sheet opens, for at most 10 plies. A move of yours that
loses more than the blunder limit is flagged as a mistake, and either way you
can save the Playbook part alone or both. The checks are kept on the saved
moves, which is what later tells a saved mistake from a rare move.
Source: `SaveSheet`, `engine/lineChecks`, `extensions.lineKinds`
Cases: `extensions.lineKinds`, `extensions.bookLength`, `extensions.moveKind`, `e2e:play-game`

## Play on the board

**TOOL-12** · port
Building a Playbook on the board offers the book's moves here (those at
least the book share of games choose), most played first, as up to three
arrows with the highlighted move always among them.
Source: `boardBuilder.bookChoices`, `boardBuilder.arrowChoices`
Cases: `boardBuilder.bookChoices`, `boardBuilder.stylePick`, `const:BOOK_SHARE`

**TOOL-13** · port
A style picks the highlighted move: Popular the most played; Solid the
quietest and Attack the sharpest, by where the move leads (the reply and your
next move along the book's most played line); Gambit a move into a named
gambit; Fianchetto a fianchetto move or one into a named Fianchetto. Most
played breaks ties. Popular is always shown, and any other style that would
highlight a different move, or is the one picked.
Source: `boardBuilder.stylePick`, `boardBuilder.shownStyles`
Cases: `boardBuilder.stylePick`, `const:STYLES`

**TOOL-14** · port
Goals show where a side stands on the opening's three jobs, read off the
position: the minor pieces still at home, whether it has castled, and its
center pawns against the other side's.
Source: `boardBuilder.goals`
Cases: `boardBuilder.goals`
