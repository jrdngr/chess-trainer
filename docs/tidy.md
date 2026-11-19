# Tidy: what it is for

Tidy finds the places where your Playbook could converge, and lets you
switch to the move that brings your lines together. Agreed on 2026-11-19.
Its rules go in `rules/tidy.md`, each with a test.

## Intent

- **Growth still decides the Playbook.** At a growth hole you were already
  offered the move that converges, drawn green, and you picked another.
  Tidy offers that move again in hindsight. A switch only takes your move
  out and puts the offered one in its place.
- **One place for all of it.** You could find these spots in the tree
  yourself and delete the branch, but that's hard work, and after a game you
  won't remember where the spot was. Tidy finds them for you.
- **Never a worse move.** A switch is only offered when it's at least as
  good as your move. Keeping your lines together is never worth a bad
  position.

## How Tidy works

1. **Where it lives.** The Playbook tab shows a wand and a count in a box
   to the right of its title, like the Pawn Shop's pawn counter. It shows
   only when Tidy has something to list. The opening page doesn't have Tidy.
2. **What it looks at.** Every move you've chosen in your Playbook, on both
   sides, in one list. Your first move of a game is never a find, because two
   first moves are two openings, not a loose end.
3. **What counts as a find.** Another move is a find when it's closer to the
   rest of your lines than yours:
   - **Transposes:** it reaches a position already in your Playbook.
   - **Heads toward:** after a common reply, one of your moves reaches a
     position already in your Playbook. This ranks below a direct
     transposition.

   A move you play in similar positions elsewhere (a habit) isn't a reason
   to switch.
4. **Eval decides.** When more than one move would tidy a position, the one
   the engine rates highest is offered. A move rated clearly worse than
   yours is never offered. A move the book lacks must pass the engine
   before it shows.
5. **The list.** The screen opens with one line: "Simplify your Playbook by
   switching to lines that transpose into each other." It sits in its own
   card. Each find is a card with two boards from the position where the
   lines split: **Current line** on the left, **Target line** on the right.
   A stepper under them plays both lines a move at a time (one step is one
   move by either side). The target line steps until it reaches the
   position you already have, then 3 more moves from your Playbook, or as
   many as you have there if fewer. The current line steps the same number
   of moves, following your move and the reply played most; if it ends
   first, its board stops there. Squares of moves that go are red; the new
   move's squares are green. When the target line reaches a position you
   already have, its board gets a green edge, and its later moves show gray
   because you know them. The card has no other text, and its one button
   reads **Switch these moves**. Biggest savings first.
6. **Switch.** The card's one action. The offered move becomes yours there;
   your move goes, with everything under it. A toast offers Undo. The
   position's card starts over and the misses logged against it are
   cleared. Ratings lost to the miss stay lost.
7. **Holes after a switch.** A switch can leave a move with no answer under
   it. The growth curve fills it like any other hole.
