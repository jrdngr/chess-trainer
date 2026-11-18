# Openings for sale

What pawns buy on the Playbook tree: a curated list of openings. Code:
`Families.swift` (the list is `OPENING_LIST`), and the openings for sale in
`PlaybookMap.swift`. Tests: the `docs/rules/families.md` suite in
`Tests/SpecTests/Rules/FamiliesRules.swift`.

1. **The list is curated.** Each opening is named the way a player talks
   about the choice they made: the Italian, the London, the Najdorf, the
   Slav. An opening is everything from its named position on; the moves
   leading to it are fixed. A system played against several answers (the
   London, the Open Sicilian) starts at each of them. No opening sits
   inside another on the same side. As White: Italian, Ruy Lopez, Scotch,
   Vienna, King's Gambit, Open Sicilian, Alapin, Smith-Morra, Advance
   French, Advance Caro-Kann, Queen's Gambit, London, Catalan, English,
   King's Indian Attack. As Black against 1.e4: 1...e5, Najdorf, Dragon,
   Accelerated Dragon, French, Caro-Kann, Scandinavian, Pirc. Against 1.d4:
   Queen's Gambit Declined, Slav, Queen's Gambit Accepted, King's Indian,
   Grünfeld, Nimzo-Indian, Queen's Indian, Dutch.
2. **You have an opening** when a line of your Playbook is in it. You drill
   only the openings you have: Drill steers the opponent into them, and
   growth stays inside them (see [growth](growth.md)).
3. **The rest are for sale on the tree,** under the nearest opening of
   yours on their way, or else under their first move, which then shows as
   the way to them.
4. **Prices rise.** The first opening bought on a side costs 2,000, and
   each one after it 500 more. White and Black climb their own ladders.
5. **Buying adds the opening's lines:** from each of its starts, the most
   played reply and your most played answer in turn (as Black the calmest
   of the top three answers), for one fill of your moves, ending with the
   named opening or where no reply is common enough.
6. **Swap tokens.** You start with 1 and earn 1 more for every 3 openings
   bought, holding at most 1. A swap trades an opening you have for one for
   sale on the same side, free: the old one goes with every move, card and
   form inside it. Moves on the way to another opening you have stay.
7. **Choosing openings.** Welcome offers "Recommend some openings" (the
   Italian, 1...e5 and the Queen's Gambit Declined) or "Choose my
   openings": the tree in a choosing mode, with no prices, and three slots
   to fill: a White opening, a Black one against 1.e4 and one against 1.d4.
   The picks go in free with their lines (rule 5) and don't raise a price.
   There are no other ways in: after this, new openings come only from the
   tree. Code: `Choosing.swift`.
8. **Lines saved by hand stay inside your openings.** The board editor and
   Analysis save a line only when it is in an opening you have, or leads
   into one; anything else shows as not saved.
