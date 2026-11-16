# The Pawn Shop

What pawns buy, and what stays locked until they do. Code: `Unlocks.swift`,
and `HeadlessApp.buy` in the Game target. Tests: the `docs/rules/shop.md`
suite in `Tests/SpecTests/Rules/ShopRules.swift`.

1. **The features**, each with its price and what it needs first: side
   picker 5; the Pawns lens 10, then the Pieces lens 20, the Kings lens 30
   and the Eval lens 60, each after the one before; Plan 40; opening
   picker 50, after the side picker; Freeform 120, after the opening
   picker; Recommendations 150, after Freeform; Middlegame 300, after the
   Pieces lens; Endgames 300. Each item's sheet says in a sentence what it
   does.
2. **Buying** takes the price off your pawns. An item is for sale only
   when every item it needs is yours and you have its price, and it is
   bought once.
3. **Opening guides, opponent personalities and the cosmetics** (board,
   piece and deck styles, full UI styles, app icons) are shown with their
   prices but aren't for sale yet.
4. **Home holds to what you own.** Without the side picker you play
   White. Without the opening picker you play Any Opening. Without
   Freeform you play Drill, and Either is not a side. Home shows a
   feature's control only once it is yours: the side picker, the Freeform
   switch, the opening picker, Middlegame, Endgames and Recommendations.
   Profiles from before the shop own every feature (see [saves](saves.md)).
5. **Each lens shows once it is yours,** in Play, on the end screen and in
   Endgames. Analysis has every lens.
