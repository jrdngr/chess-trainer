# Behavior spec

What the app does, rule by rule, for the native port to match. The plan
behind it is [docs/native-port/plan.md](../native-port/plan.md).

The prototype's code is the source of truth for what happens. A rule says it
in words, names where it comes from, and names the golden cases that pin it
down. Where the code and a decision note disagree, the rule follows the code
and the conflict is listed for the owner at the end of the area's file.

## A rule

```markdown
**RUN-12** · port
A move your prep doesn't have, where it has one, is a miss: rated down and
logged for review, whatever the engine says of it.
Source: `survivalController.judgedMove`; survival-mode-redesign (09-25)
Cases: `survival/miss-then-moments-and-a-blunder`, `e2e:survival-runs`
```

- **ID**: the area's prefix and a number. Numbers are never reused; a rule
  that goes away is marked drop rather than deleted.
- **Status**: `port` (the native app does this), `drop` (dead or superseded),
  or `change` (an intended difference, with what changes). Only the owner moves
  a rule to drop or change.
- **Source**: the code that does it, and the decision note that says why,
  when there is one.
- **Cases**: what pins it down, each in backticks:
  - a function case set by its `fn`, from `spec/cases/functions/*.json`
    (`survival.moveScore`);
  - a scenario by `area/name`, from `spec/cases/scenarios/*.json`
    (`survival/clean-prep-into-the-book`);
  - an end-to-end trace by `e2e:name`, from `e2e/traces/`
    (`e2e:autopilot-first-runs`);
  - a constant by `const:NAME`, from `spec/constants.json` (`const:BOOK_SHARE`).

  A rule with no case is a gap. `npm run spec:coverage` lists the gaps, and
  `npm test` fails when a rule names a case that does not exist.

Numbers in rules are today's values. Where a rule names a constant, the
constant in `spec/constants.json` is what counts.

## Areas

| File | Prefix | What it covers |
| --- | --- | --- |
| [autopilot.md](autopilot.md) | AUTO | What Autopilot recommends, where each run starts, and Any favorite |
| [drill.md](drill.md) | DRILL | Drill positions and Drill lines |
| [end.md](end.md) | END | What a run logs when it ends, the end screen, and Grow this line |
| [growth.md](growth.md) | GROW | Growth's rows and a sitting: holes, batches, Undo, the edge of the book |
| [learning.md](learning.md) | LEARN | Cards and their schedule, and ratings per opening |
| [naming.md](naming.md) | NAME | Position keys, book names and families, the opening catalogue, regions |
| [playbook.md](playbook.md) | BOOK | The Playbook tree, move sources, extension kinds, the prepared floor, mistakes |
| [run.md](run.md) | RUN | A Survival run, which is also every Autopilot round: prep, the book phase, misses, pops, blunders and the end |
