# Onboarding

The first screens a new profile sees: building the first Playbook. The
screens are `src/screens/OnboardingScreen.tsx`; what they put in is
`onboarded` in `src/store/useStore.ts`; the sets are
`src/model/starterSets.ts`.

## When it is asked

**ONB-1** · port
Onboarding is asked of a profile that has never answered it and holds
nothing: no Playbook, no cards, no imported games, no answers. It offers
Suggest a set, Pick openings, Play on the board, and Skip for now. Skipping
is an answer: it puts nothing in and is never asked again, short of a full
reset.
Source: `useStore.needsOnboarding`, `useStore.freshProfile`, `OnboardingScreen`; onboarding-redesign (10-23)
Cases: `onboarding.onboarded`, `e2e:autopilot-first-runs`

## The three ways in

**ONB-2** · port
There are six starter sets, Classical, System, Solid, Aggressive, Fianchetto
and Mirror, each with a description and openings for three slots: As White,
Against 1.e4 and Against 1.d4. An opening is named by the move order the book
names it at, and shown by the set's own label where it has one ("1...e5",
"Berlin", "London System"), else by the book's name. The set's page shows each
opening's count of your own moves.
Source: `starterSets.STARTER_SETS`, `starterSets.setOpenings`, `starterSets.countOwnMoves`
Cases: `starterSets.set`, `starterSets.countOwnMoves`, `const:STARTER_SETS`, `const:SLOT_LABELS`, `const:SLOT_COLOR`

**ONB-3** · port
An opening picked on its own belongs to the side that played its last move,
except the two the book names a move late: the King's Indian (1.d4 Nf6 2.c4
g6 3.Nc3) is Black's and the Scotch (…3.d4 exd4) is White's.
Source: `onboarding.playerOf`, `starterSets.seedFor`
Cases: `onboarding.playerOf`, `starterSets.seedFor`, `const:NAMED_LATE`

**ONB-4** · port
Play on the board saves whole lines you played, each with the engine's loss
on your moves. What it lists is each opening a saved line ends in, by the
Playbook's own names, with your moves on the way to it; one called by Black's
first move ("1...e5") is starred at that move.
Source: `OnboardingScreen.boardRows`, `BoardScreen` (hold); extensions-design (10-24)
Cases: `onboarding.onboarded`

## What goes in

**ONB-5** · port
A starter set or a picked opening goes in as exactly its own moves and
nothing past them; the rest comes in through Growth. Lines from the board go
in whole. Moves are marked Opening picker or Play on the board by where they
came from, and a move order that is not legal is left out. Each line that
added moves is logged as an add.
Source: `useStore.onboarded`; onboarding-redesign (10-25)
Cases: `onboarding.onboarded`, `onboarding.onboarded (a starter set)`

**ONB-6** · port
Every set or picked opening the catalogue has is starred. The selection
becomes one side when every starred opening is that side's, else Random; one
opening selects itself and several select Any favorite. Lines from the board
star nothing on their own, and with nothing starred the selection stays as it
was.
Source: `useStore.onboarded`, `onboarding.selectionFor`; any-favorite
Cases: `onboarding.selectionFor`, `onboarding.onboarded`, `onboarding.onboarded (a starter set)`

**ONB-7** · port
Nothing goes in until you leave the ready screen. It lists every opening
waiting to go in with its count of your moves ("6 moves across 3 openings"),
shows the first Autopilot round they would make, and offers Add more
openings (back to Pick openings, where any can be dropped), Play your first
run, and Go to Home. Backing out keeps what was picked.
Source: `OnboardingScreen.Ready`, `OnboardingScreen.ready`; onboarding-redesign (10-25)
Cases: `e2e:autopilot-first-runs`

## Settled

- The Classical set's 1...e5 is listed as King's Pawn Game, as the code does it. The owner ruled on 10-31 that the code is the truth: the test in `openings.test.ts` covers deeper lines only.
