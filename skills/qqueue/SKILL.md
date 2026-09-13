---
name: qqueue
description: "A one-question-at-a-time Q&A process for design sessions, decision reviews, and working through code-review findings. Present exactly one concise question with all context needed to answer it, numbered options with the recommendation always option 1, then wait for the answer. Use when asked for qqueue, a question queue, or straight questions, to run a design or Q&A session one question at a time, or to work through an existing list of review findings or open decisions."
---

# Question Queue

Run a decision session one question at a time: a design review, a Q&A, or a walk through an
existing list of code-review findings. The deliverable is the user's decisions, not prose.

## The loop

1. Collect the open decisions up front — from the task, the context already in the
   conversation, or a findings list the user hands over. Give each a short ID — `Q1`, `Q2`, ... in
   ask order — so answers can refer back to it.
2. Ask exactly one question per turn, then stop and wait for the answer. Never bundle
   questions.
3. Apply the answer before writing the next question. If an answer settles or reshapes a
   later question, drop or rewrite that question.
4. Ask as plain numbered text in the chat. Do not use AskUserQuestion or any other
   option-picker tool.

## Question format

Every question has the same shape:

```
Question <current> of <number of questions>
Q<n> — <subject>

Context:

- <only the facts that change the answer>
- <if confusable with a nearby question, one bullet on how this one differs>

Options:

1. <recommended choice> (recommended)
   - <what it means, 1-3 bullets>
2. <alternative>
   - <what it costs>

Recommendation: option 1. <one or two lines of why.>
```

Rules:

- Provide multiple options when there are multiple justifiable choices. If there are two
  competing approaches with opposite pros/cons, present both as options.
- Do not provide extra options just to fill out the list. Every option should have some kind
  of advantage over other options.
- The recommendation is always option 1, marked `(recommended)`, and restated in the closing
  `Recommendation:` line with a short why.
- Context is self-contained: the user can answer without scrolling back or opening files.
- Each option states its tradeoff, not just its name.
- A single option is fine when the real question is "confirm or object".

### Subquestions

A decision may be split into subquestions, asked one at a time — but only when a single
question would carry too much for a human to process at once: too many interacting choices,
or context that cannot be trimmed further.

- Derive IDs from the parent: `Q4a`, `Q4b`, ...
- Each subquestion uses the full question format above.
- Answers to earlier subquestions become context bullets for later ones.
- Do not pad. A decision that fits in one question stays one question.

## Style

- Very concise. Bullets over prose.
- No agent-speak, no hedging, no filler.
- Trim context to what changes the answer. When in doubt, cut.

## Working through findings

When invoked on an existing review or findings list produced by another skill or process:

- One finding per question. Restate the finding in a line or two; do not assume the user has
  the list open.
- Options are resolutions: the recommended fix as option 1, alternatives after, and
  "ignore / won't fix" as an explicit numbered option.
- Add a short progress line under the header, e.g. `3 of 7 remaining`.

## Ending

When the questions are exhausted, stop. No summary, decision log, or file unless the user
asked for one when invoking the skill.
