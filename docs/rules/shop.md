# The Pawn Shop

What pawns buy, and what stays locked until they do. Code: `Unlocks.swift`,
and `HeadlessApp.buy` in the Game target. Tests: the `docs/rules/shop.md`
suite in `Tests/SpecTests/Rules/ShopRules.swift`.

1. **The features**, each with its price and what it needs first: side
   picker 5; lenses 15; opening picker 50, after the side picker; Freeform
   120, after the opening picker; Recommendations 150, after Freeform;
   Middlegame 300, after lenses; Endgames 300.
2. **Buying** takes the price off your pawns. An item is for sale only
   when every item it needs is yours and you have its price, and it is
   bought once.
3. **Opening guides, opponent personalities and the cosmetics** (board,
   piece and deck styles, full UI styles, app icons) are shown with their
   prices but aren't for sale yet.
4. **Home holds to what you own.** Without the side picker you play
   White. Without the opening picker you play Any Opening. Without
   Freeform you play Drill, and Either is not a side. Middlegame, Endgames,
   Recommendations and the lenses are closed until bought. Profiles from
   before the shop own every feature (see [saves](saves.md)).
