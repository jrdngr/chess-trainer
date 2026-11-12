# Freeform

Runs when Home's switch is on Freeform. Code: `freeRound` (`Rounds.swift`),
`freeformSource` (`Freeform.swift`) and `beginFree` (`OpeningRun.swift`).
Tests: the `docs/rules/freeform.md` suite in
`Tests/SpecTests/Rules/FreeformRules.swift`.

1. **Every run starts from move one.** Nothing is played for you. As Black,
   the opponent's first move is already on the board when the run's card is
   dealt.
2. **The side is the picked one.** On Either it is the side the
   recommendation picks (see [next run](next-run.md)); with nothing to
   recommend, there is no run.
3. **Any of your lines is yours to play.** No line is drawn. At each of its
   turns the opponent picks among the replies your Playbook holds there, so
   it follows you into whichever line you play.
4. **The opponent weighs its replies.** Each reply weighs its share of
   strong players' games (with a floor, so rare replies still come up),
   times how much the lines past it need practice: their weakness times how
   long they have been left.
5. **Gaps due a new move pull.** A gap due a new move (see
   [growth](growth.md)) adds its reply to the opponent's choices, though no
   line of yours meets it yet, and every reply on the way to it weighs 6
   times as much.
6. **Home's pick steers, never binds.** On the way into the opening picked
   on Home, the opponent keeps to that opening's own move order where it
   can, then to any move order that still reaches it. You can leave it at
   any move.
7. **Off your lines, nothing more is graded.** Once you play a move your
   Playbook doesn't have there, no later move of the run is graded, even
   back in your lines.
8. **Past your lines the run goes on as in Drill.** The opponent plays book
   moves, then the engine (see [opponent](opponent.md)). A run that reaches
   a hole can grow there (see [growth](growth.md)).
