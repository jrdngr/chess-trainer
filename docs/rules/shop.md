# The Pawn Shop

What pawns buy, and what stays locked until they do. Code: `Unlocks.swift`,
and `HeadlessApp.buy` in the Game target. Tests: the `docs/rules/shop.md`
suite in `Tests/SpecTests/Rules/ShopRules.swift`.

1. **The features**, each with its price and what it needs first: side
   picker 200; the Pawns lens 300, then the Pieces lens 500, the Kings lens
   800 and the Eval lens 1,500, each after the one before; Plan 1,000;
   opening picker 1,000, after the side picker; Freeform 3,000, after the
   opening picker; Middlegame 8,000, after the Pieces lens; Endgames 5,000,
   with Basic mates and From your games. All of them come to 21,300. King
   and pawn (5,000) and Rook endings (3,500) are Endgames families bought
   on their own, after Endgames, in their own row. Each item's sheet says
   in a sentence what it does.
2. **Buying** takes the price off your pawns. An item is for sale only
   when every item it needs is yours and you have its price, and it is
   bought once.
3. **Opening guides, opponent personalities and the cosmetics** (board,
   piece and deck styles, full UI styles, app icons) are shown with their
   prices (guides 2,000 each, personalities 5,000, board, piece and deck
   styles 3,000 each, full UI styles 10,000, app icons 2,000) but aren't
   for sale yet.
4. **Home holds to what you own.** Without the side picker you play
   White. Without the opening picker you play Any Opening. Without
   Freeform you play Drill. The side picker offers White, Black and Either. Home shows a
   feature's control only once it is yours: the side picker, the Freeform
   switch, the opening picker, Middlegame and Endgames.
5. **Each lens shows once it is yours,** in Play, on the end screen and in
   Endgames. Analysis has every lens.
6. **Streak freezes** are sold under the tree for 1,000 each, while you
   hold fewer than 2 (see [pawns](pawns.md)).
7. **Cash buys two things.** The unlock ($9.99) makes every feature in the
   tree yours; not the endgame families, the cosmetics or openings. It sits
   above the tree until it is yours, and comes back to every profile from
   the App Store. Pawn packs sit under the tree: 2,000 for $1.99, 6,000 for
   $4.99, 13,000 for $9.99. Each App Store transaction is credited once.
   Code: `Purchases.swift`, and `CashStore` in the app.
