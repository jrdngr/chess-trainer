# Tidy: what it is for

Tidy finds the places where your Playbook could converge, and lets you
switch to the move that brings your lines together. Agreed on 2026-11-19; habit, labels, colors and tips added 2026-11-20.
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

   - **Habit:** you play this move in your other lines, in similar
     positions. A fianchetto counts as one habit, whichever piece goes
     first. A habit ranks below both, and is never offered in place of a
     move that is itself a habit.
4. **Eval decides.** When more than one move would tidy a position, the one
   the engine rates highest is offered. A move rated clearly worse than
   yours is never offered. A move the book lacks must pass the engine
   before it shows.
5. **The list.** No description card: the labels explain each find. Each
   find is a card with two boards from the position where the lines split:
   **Current line** on the left, and on the right a label saying why:
   **Joins your line** (transposes, teal), **Can join your line** (heads
   toward, blue) or **Your usual move** (habit, amber). The label and the
   Switch button take the kind's color; on the boards, red is still the
   moves that go and green the new move.
   A stepper under them plays both lines a move at a time (one step is one
   move by either side). The target line steps until it reaches the
   position you already have, then 3 more moves from your Playbook, or as
   many as you have there if fewer. The current line steps the same number
   of moves, following your move and the reply played most; if it ends
   first, its board stops there. Squares of moves that go are red; the new
   move's squares are green. When the target line reaches a position you
   already have, its board gets a green edge, and its later moves show gray
   because you know them. For a heads-toward find, the steps include the
   moves that lead to your position. A habit's stepper has one step, the
   switch, and nothing past it. The card has no other text, and its one
   button reads **Switch these moves**. Biggest savings first, habits
   last.
6. **Switch.** The card's one action. The offered move becomes yours there;
   your move goes, with everything under it. A toast offers Undo. The
   position's card starts over and the misses logged against it are
   cleared. Ratings lost to the miss stay lost.
7. **Holes after a switch.** A switch can leave a move with no answer under
   it. The growth curve fills it like any other hole.
8. **Tips.** The Tidy button explains itself the first time it shows:
   "Tidy finds moves that bring your lines together so you have less to
   remember." Each kind explains itself the first time a card of that kind
   shows, and several chain on one visit:
   - Joins your line: "This move transposes. It reaches a position you
     already play, so two lines become one."
   - Can join your line: "This move leads to transposition. It can reach a
     position you already play once you add a few more moves."
   - Your usual move: "This move is a habit. You play it in your other
     lines."
