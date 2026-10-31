# Choosing an opening

The selection every mode reads, the quick sheet that sets it, and Browse, the
full picker. The catalogue is `src/model/picker.ts` with hand data in
`src/model/pickerData.ts`; Browse's lists are `src/model/browse.ts`; the
screens are `src/components/Selection.tsx` and
`src/components/BrowsePicker.tsx`.

## The selection

**PICK-1** · port
The selection is a side (White, Black or Random) and an opening: Any
opening, Any favorite, or a line of moves (NAME-7). It starts as Random and
Any opening. The selection bar shows it as a trail of short names, a line
played past its name adding its moves ("Slav › Modern Line › 3...Bf5").
Source: `selection.DEFAULT_SELECTION`, `Selection.selectionTrail`; browse-openings-redesign (10-20)
Cases: `openingTree.nodeById`, `browse.lineName`, `const:DEFAULT_SELECTION`, `const:ANY_FAVORITE`

## The quick sheet

**PICK-2** · port
Tapping the selection bar drops the quick sheet from the top: a White / Black
/ Random switch, then Any opening and Any favorite, then Favorites (most
recently played first, the first 6 and "Show all N"), then First move (1.e4,
1.d4, 1.c4, 1.Nf3, which keep the current side: as White you play it, as
Black you face it), and Browse all openings. A favorite sets its own side.
Any tap selects and closes.
Source: `Selection.QuickPicker`, `picker.sideForPick`; quick-opening-picker (10-04)
Cases: `picker.sideForPick`, `anyFavorite.favoritesIn`

## The catalogue

**PICK-3** · port
The picker lists the book's names as families (by first move: 1.e4, 1.d4,
Flank), branches and lines, a name "Family: Branch, Line" naming one level
per part. The big families are split into hand-made groups, each defined by a
key position, with membership by reachability; an entry reachable from
another group notes "also via". An entry the book never names on its own
stands for its shallowest line. Each entry has a side (whoever played the
move it is named at, with hand corrections; a line takes its branch's side),
a hand-rated sharpness from 1 to 5, and a difficulty from 1 to 5: how many
lines you would need to know (your most played move at your turns, every
reply played 10% or more at theirs, as deep as the book names lines under
it), ranked among entries of its level.
Source: `picker.pickerCatalog`, `picker.nameLevels`, `picker.groupFamily`, `picker.theoryLines`, `pickerData.ts`; opening-picker-redesign (09-25)
Cases: `picker.entry`, `picker.family`, `picker.nameLevels`, `const:FAMILY_SHARPNESS`, `const:SHARPNESS_OVERRIDES`, `const:BRANCH_SIDES`, `const:FAMILY_GROUPS`

## Browse

**PICK-4** · port
Browse keeps a board on screen that you can play on at any time; the name
bar above it names what is on it, with a favorite star and Choose. Tapping a
row plays its line onto the board and opens what is under it; nothing is
selected by a tap. Choose selects exactly the board's line (by the book's own
move order where it has the position) with its side, and closes; the close
button leaves the selection as it was. Under the board are the Next moves
and five lists by chip: My lines, Suggestions, Shelves, Recent, Book, plus
search. The list pages filter by side.
Source: `BrowsePicker`; browse-openings-redesign (10-20)
Cases: `browse.nextMoves`

**PICK-5** · port
Next moves lists the book's moves from the board's position, most played
first, each with its share, the name it goes to (its own, or the names a
couple of plies on), and a mark where your Playbook plays it.
Source: `browse.nextMoves`, `browse.repMoves`
Cases: `browse.nextMoves`

**PICK-6** · port
My lines is your Playbook as names: each side, then its openings (favorites
first), their variations, and the lines of an opening that has none, each
named for where it goes and told apart by the move it splits off at.
Source: `browse.myLines`, `openings.linesOf`
Cases: `browse.myLines`

**PICK-7** · port
Suggestions is one list of up to 30, each with why it is there: it fills a
hole ("1...Nf6 in 41% of book games", "Nothing yet against 1.Nf3"), it is
like what you play ("Transposes into your X", "Same structure as your X"), or
it suits your style ("Sharp like your X"). Each gets one score, need + 0.6 ×
fit + 0.35 × style, and shows whichever part is biggest; the list is dealt
best first but never three of one reason in a row. White style matches stay
on the first move of the opening they are like.
Source: `browse.suggestions`, `browse.mixLabels`; browse-openings-redesign (10-20)
Cases: `browse.suggestions`, `browse.mixLabels`

**PICK-8** · port
Shelves are hand-made lists: Gambits, Systems, Solid, Sharp, Classical,
Hypermodern, Offbeat, Trappy. Recent lists the openings you played lately,
newest first, under Today, This week and Earlier. Book lists every family
under its first move, most played first. Search matches names, ECO codes,
moves and initials ("qga"), your own lines first, then the book's,
shallowest and most played first.
Source: `browse.SHELVES`, `browse.shelfRows`, `browse.recentItems`, `browse.bookItems`, `browse.searchItems`
Cases: `browse.shelfRows`, `browse.recentItems`, `browse.bookItems`, `browse.searchItems`, `browse.shortName`, `const:SHELVES`

## Conflicts for the owner

None found so far in this area.
