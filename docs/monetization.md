# Monetization: what it is for

How the app earns money and how pawns flow, agreed on 2026-11-17. Nothing
here is built yet. When a part is built, its rules go in `rules/`, each
with a test. The numbers below are starting values. They come from the
pawn-rate calculator in [tools/pricing](../tools/pricing/README.md),
which recomputes earnings from headless runs (`swift run playbook
measure`), so a value or price change needs no new games.

## Intent

- **No ads, ever.**
- **One purchase most people make.** A one-time $10 unlock gives the whole
  feature tree in the Pawn Shop. Everything else in the app is bought with
  pawns, and pawns can be earned by playing.
- **Cash buys only two things:** the $10 unlock and pawn packs. There is no
  pawn multiplier and no pawn grant with the unlock.
- **Drilling is the baseline.** Short prep-only runs are how a player
  drills openings when they need help, and their earning rate is what
  everything else is balanced against. They are never made worse.
- **Playing on pays more.** Long runs, mates and held draws earn clearly
  more than drilling, so a player is never better off stopping early or
  stalling.
- **Moments never involve money.** There's nothing to buy around a moment.

## Earning targets

Rates are measured against prep-only drilling (1x). Full runs and
Middlegame are measured at a new player's pace past prep, which is slower
than the owner's.

| What | Target |
| --- | --- |
| Long runs (20 or more of your moves past prep) | 1.5x |
| Shorter full runs | 1.25x |
| A run ending in your mate | 2x |
| Middlegame | 1x |
| Freeform | the same as Drill for the same run length |
| White and Black | the same |
| Weaker levels | may earn less: playing better pays more |
| Each Endgames family | its bounties add up to about half its price |
| The streak at its cap | about 5 minutes of drilling a day |
| The feature tree | about 6 hours of typical full runs at a fast pace |

## How pawns are earned

1. **Prep complete pays 1 pawn per prep move asked**, all at once when the
   prep completes. The pawns build up on screen as the prep is played, one
   per correct move: a pawn pops out of the square the move landed on and
   flies to a pot (a pawn and its count) beside the prep bar, which bumps
   and counts up. The prep bar keeps its usual colors. At prep complete the
   pot's pawns fly to the pawn counter. A miss loses the whole pot and
   nothing else: the missed segment turns red, the pot drains, and the rest
   of the run still pays. When growth opens at the end of the prep, the pot
   breathes while it waits for the first growth move, and Done with nothing
   added drains it.
2. **Distance markers** pay 20 for every 5 of your moves past prep,
   up to 200 a run. In Middlegame they pay 40%. They stop once
   the game reaches the endgame, and after a run's 10th marker, so stalling
   a won game earns nothing.
3. **Checkmate** pays 100, less 2 for each of your moves in the endgame
   before the mate, down to 25: finishing quickly pays most. **Held the
   draw** pays 20, under any win, and only when you were at −3 or worse in
   the endgame. Other draws pay nothing extra.
4. **Other events** keep paying: blunder punished 3, found moment 6,
   mission done 6, reached the endgame 3.
5. **Endgames pays bounties, not rounds.** Each ending pays once for its
   first clear (250), its first mission (100) and mastery (500). Mastered
   means 3 successes in a row, each on a different day. After mastery, a
   tune-up comes due 14 days later, then the interval doubles after each
   pass up to 90 days. A passed tune-up pays 100. A failed one pays nothing
   and comes back in 3 days, and mastery is kept. A plain dot with no count
   shows on the Endgames tile while a tune-up is due. Each From your games
   position pays 100 once, on its first conversion.
6. **The streak** pays once a day: 10 on day 1, 10 more each day, up to 90.

## How pawns are spent

### The feature tree (or $10)

| Item | Price |
| --- | --- |
| Side picker | 50 |
| Opening picker | 100 |
| Freeform | 3,000 |
| Pawns lens | 100 |
| Pawn structure (Pawns upgrade) | 400 |
| Endgame pawns (Pawns upgrade) | 600 |
| Pieces lens | 200 |
| Square control (Pieces upgrade) | 600 |
| Endgame pieces (Pieces upgrade) | 800 |
| Kings lens | 300 |
| Endgame kings (Kings upgrade) | 1,000 |
| Eval lens | 500 |
| Eval history (Eval upgrade) | 1,200 |
| Plan | 1,000 |
| Middlegame | 8,000 |
| Endgames (Basic mates, From your games) | 5,000 |
| All of it | 22,850 |

Lenses are free to use once owned. The base lenses are cheap so players
use them early; each lens's first part is its most useful one, and its
upgrades add the rest.

### Openings

- **Openings come from a curated list,** each named the way players talk
  about their choice: the Italian, the London, the Najdorf, the Slav. An
  opening is everything from its named position on. You drill only what
  you picked: an Italian player never drills 1...c5.
- **A new player starts with 3 openings:** one White, one Black against
  1.e4 and one Black against 1.d4.
- **Each opening after that costs pawns** on a rising ladder: 2,000 for the
  first, then 500 more for each one after. White and Black have separate
  ladders. The $10 unlock includes no openings.
- **Pawns buy breadth, play earns depth.** On the Playbook tree, an opening
  for sale costs its ladder price. Variations inside an opening you own are
  free and open only through growth's level gates. There's no early unlock.
- **Swap tokens.** A player starts with 1 and earns 1 more for every 3
  openings bought, holding at most 1. Swapping an opening out deletes its
  progress.
- **Trials** let a player walk any opening for sale for free before buying it.
  See [trials.md](trials.md).

### Other content

| Item | Price |
| --- | --- |
| Endgame family: King and pawn | 5,000 |
| Endgame family: Rook endings | 3,500 |
| Opponent personalities | 5,000 |
| Board, piece or deck style, each | 3,000 |
| Full UI style, each | 10,000 |
| App icon, each | 2,000 |

Cosmetics and personalities are pawn-only.

### In play

- **Continue after a blunder** costs 500, once per run. It takes the
  blunder back. Moves after it don't count toward your best, and events
  still pay.
- **Streak freeze** costs 1,000. You can hold 2, and one is used
  automatically on a missed day.
- **Streak repair** costs 2,000. It's offered for one missed day only, all
  through the next day, shown quietly on the streak ring and never as a
  popup. It restores the streak but pays nothing for the missed day.
- Frozen and repaired days count toward the streak's length and show on
  the ring as frozen.
- There are no paid hints.

### Pawn packs

| Pack | Pawns |
| --- | --- |
| $2 | 2,000 |
| $5 | 6,000 |
| $10 | 13,000 |

Bigger packs give more pawns per dollar. $10 of packs always buys less than
the feature tree, so the $10 unlock is always the better deal, and it's
shown above the packs. There's no $1 pack. A $20 pack comes when cosmetics
and personalities ship.

## Choosing openings

1. **Welcome has two buttons.** "Recommend some openings" gives the
   Classical set. "Choose my openings" opens the picker.
2. **The picker is the Playbook tree** in a choosing mode, the same screen
   used later to buy and try openings. A bar at the bottom holds three
   slots: White, against 1.e4 and against 1.d4. Tapping an opening fills its
   slot, and Done appears once all three are filled.
3. **There are no other ways in.** The other starter sets, playing lines on
   the board and importing games are gone. After onboarding, new openings
   come only from the Playbook tree.

## When it lands

Every saved profile is wiped and everyone starts over. There's no migration
and no special case for old saves. Profiles become a testing tool, so how
purchases work across profiles doesn't matter.
