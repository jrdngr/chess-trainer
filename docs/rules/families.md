# Opening families

What pawns buy on the Playbook tree. Code: `Families.swift`, and the
families for sale in `PlaybookMap.swift`. Tests: the
`docs/rules/families.md` suite in `Tests/SpecTests/Rules/FamiliesRules.swift`.

1. **A family is the first move that is yours.** As White, your first move
   (1.e4, 1.d4, ...); as Black, your answer to White's first move (1.e4 c5,
   1.d4 Nf6, ...). Everything under a family is a variation: free, and it
   grows only through the curve (see [growth](growth.md)).
2. **You have a family** when a line of your Playbook is in it.
3. **The rest are for sale on the tree.** Every first move played in at
   least 2% of games is a White family; under each, every answer played in
   at least 2% is a Black family. As White they sit in the top row; as
   Black under White's first move, which shows as a way to them when you
   have no answer to it yet.
4. **Prices rise.** The first family bought on a side costs 2,000, and each
   one after it 500 more. White and Black climb their own ladders.
5. **Buying adds the family's line:** the family, then the most played
   reply and your most played answer in turn (as Black the calmest of the
   top three answers), for one fill of your moves, ending with the named
   opening or where no reply is common enough.
6. **Swap tokens.** You start with 1 and earn 1 more for every 3 families
   bought, holding at most 1. A swap trades a family you have for one for
   sale, free: the old one goes with every move, card and form under it.
