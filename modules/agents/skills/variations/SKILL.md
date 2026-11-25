---
name: variations
description: "Generate alternative wordings for a phrase, line, title or image in a piece of writing, each labelled with a probability and spread deliberately across the whole distribution, from the obvious pick to the far tail. Use when the user asks for variations, alternatives, other ways to say X, options for a line, or 'same way X is Y' examples, especially with 'probability', 'spread' or 'full tail'."
---

# Variations

Offer a spread of alternatives for one slot in a piece of writing. Label each with the probability
that you would have written it unprompted, and spread the options deliberately from the obvious
choice down to the far tail.

**Why the probabilities:** asked for "ten options", a model returns ten near-neighbours of its first
idea. Making it name a probability, and fill every band down to 0.001, forces it off the mode. The
unusual candidates are the reason to ask. The labels also tell the writer which lines a reader has
seen before.

## Process

1. **Find the slot.** Quote the sentence and mark exactly what varies, e.g. "I turn to GitHub for
   ___ who has reverse engineered it." Say what the slot has to do: its job in the argument, the
   tone, and the grammar it must fit (a noun phrase, a clause, a whole sentence).
2. **Read the house style** if there is one: the project's CLAUDE.md or AGENTS.md, and the
   `prose-conventions` skill. Every candidate must obey it: British spelling where that applies,
   no banned words, no em dashes, no "It's not X, it's Y". A tail option is bold, not sloppy.
3. **Generate about 10 candidates across the bands.** Space the probabilities roughly
   logarithmically, so the list reaches the tail and doesn't bunch at the top:

   | band | p | what lives here |
   |---|---|---|
   | mode | 0.3–0.4 | the safe rewrite, close to the original |
   | likely | 0.1–0.25 | the same idea, sharper or warmer |
   | plausible | 0.03–0.08 | a different angle: a character, a scene, a reframing |
   | tail | 0.005–0.02 | a surprising image or register shift that still fits |
   | far tail | ≤ 0.001 | the strange one: a pointed joke, an unexpected domain |

   Each probability is your own estimate of producing that line by default. The numbers needn't
   sum to 1. Make each band differ in kind, not just in wording: vary the mechanism, such as
   understatement, a concrete scene, scale contrast, a domestic image or a callback to earlier in
   the piece.
4. **Present a table** with the columns `p | Variation | Note`, sorted from the highest p to the
   lowest. The note is a few words on what the line does or risks ("implies the teenager without
   saying it", "sardonic; may read as a swipe"). Show the slot filled, not the bare fragment, when
   the grammar shifts.
5. **Recommend one or two picks** and give the reason in a sentence each. Usually one comes from
   the middle and one from the tail.
6. **If the user asks for "more visual"** or a particular axis, regenerate the whole spread along
   that axis: concrete images and scenes in place of abstractions, still labelled and still
   reaching the tail. Don't just append to the old list.
7. **When the user picks one, apply it.** Rework the sentence so the choice fits grammatically,
   and say so if the rework moved anything else. Edit with the Edit tool, show the final sentence,
   and leave the change uncommitted unless the repo's rules or the user say otherwise. Check
   `git status` first, because someone else may be editing the same file.

## Example

Slot: "I turn to GitHub for ___ who has reverse engineered it."

| p | Variation | Note |
|---|---|---|
| 0.40 | some bright student with more free time than sense | safe; close to the original |
| 0.15 | someone who should have been revising for their exams | implies the teenager |
| 0.05 | someone who treats a trillion-dollar company's secrets as a Sunday puzzle | scale contrast |
| 0.03 | the internet's unpaid research department | short, lightly sardonic |
| 0.005 | the kind of person who takes apart the toaster to see why the toast is brown | domestic image |
| 0.001 | someone whose bedroom has better lab kit than Google's lawyers think | a pointed joke |

Picked: "the internet's unpaid research department". Applied as: "I turn to GitHub, the internet's
unpaid research department, for someone who has reverse engineered it." GitHub became the
department, so the person moved to the end.
