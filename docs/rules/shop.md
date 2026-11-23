# The Pawn Shop

What pawns buy, and what stays locked until they do. Code: `Unlocks.swift`,
and `HeadlessApp.buy` in the Game target. Tests: the `docs/rules/shop.md`
suite in `Tests/SpecTests/Rules/ShopRules.swift`.

1. **The features**, each with its price and what it needs first: side
   picker 50; opening picker 100, after the side picker; Freeform 3,000,
   after the opening picker; the Pawns lens 100, then the Pieces lens 200,
   the Kings lens 300 and the Eval lens 500, each after the one before;
   Plan 1,000; Middlegame 8,000, after Freeform; Endgames 5,000,
   with Basic mates and From your games. Each lens has upgrades, bought
   after it: Pawn structure 400 and Endgame pawns 600 for Pawns, Square
   control 600 and Endgame pieces 800 for Pieces, Endgame kings 1,000 for
   Kings, Eval history 1,200 for Eval. All of them come to 22,850. King
   and pawn (5,000) and Rook endings (3,500) are Endgames families bought
   on their own, branching off Endgames on the tree. Each item's sheet says
   in a sentence what it does.
2. **Buying** takes the price off your pawns. An item is for sale only
   when every item it needs is yours and you have its price, and it is
   bought once.
3. **Opponent personalities and the cosmetics** (board, piece and deck
   styles, full UI styles, app icons) are shown with their prices
   (personalities 5,000, board, piece and deck styles 3,000 each, full UI
   styles 10,000, app icons 2,000) but aren't for sale yet. Personalities
   come after Middlegame on the tree.
4. **Home holds to what you own.** Without the side picker you play
   White. Without the opening picker you play Any Opening. Without
   Freeform you play Drill. The side picker offers White, Black and Either, and starts on Either
   when bought. Home shows a
   feature's control only once it is yours: the side picker, the Freeform
   switch, the opening picker, Middlegame and Endgames.
5. **Each lens shows once it is yours,** in Play, on the end screen and in
   Endgames, drawing only the parts that are yours. A lens's first part:
   Pawns tags weak and passed pawns, marks holes and arrows the best
   breaks; Pieces rings each piece by how active it is and badges each
   side's least active; Kings grades each king and shows its shield, its
   zone's attackers and the open lines to it; Eval shows the bar. Its
   upgrades add: Pawn structure, the structure's name; Square control,
   who holds each square; Eval history, the run's chart and the last move's
   cost. In an endgame a lens keeps its first part until its endgame
   upgrade is yours: Endgame pawns adds each passer's kind and its square,
   Endgame pieces judges rooks, bad bishops and kings, Endgame kings shows
   key squares, the opposition and cut-off lines. The key under the board
   lists only what the lens draws. Analysis has every lens and every part.
6. **Cash buys two things.** The unlock ($9.99) makes every feature in the
   tree yours; not the endgame families, the cosmetics or openings. It
   comes back to every profile from the App Store. Pawn packs: 2,000 for
   $1.99, 6,000 for $4.99, 13,000 for $9.99. Both are sold in the pawn
   sheet, which the pawn balance opens on Home and in the Shop, and which
   a price you can't pay yet opens from an item's sheet. The unlock shows
   there until the tree is yours. Each App Store transaction is credited once;
   an unlock seen again still grants items added to the tree since. The
   unlock starts the side picker on Either, as buying it does. A refunded
   unlock takes back the features only it gave; features bought with pawns
   and a refunded pack's pawns stay. A transaction is finished with the App
   Store only once its credit is saved, so one that wasn't comes back.
   Code: `Purchases.swift`, and `CashStore` in the app.
