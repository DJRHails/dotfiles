---
name: prose-conventions
description: Writing style conventions for prose, essays, and non-fiction. Apply when writing or editing text. Covers voice, sentence structure, AI patterns to avoid, and editorial principles.
---

# Prose Conventions

Apply these principles when writing or editing prose. The author is British — use British spelling (colour, organise, centre) and idioms.

## Orwell's Rules ("Politics and the English Language")

1. Avoid cliched metaphors, similes, and figures of speech
2. Use short words instead of long ones when possible
3. Cut unnecessary words
4. Use active voice instead of passive voice when possible
5. Avoid foreign phrases, scientific words, or jargon if an everyday English equivalent exists
6. Break any rule to avoid saying something "outright barbarous"

## Paul Graham

Write like you speak.

## The Economist Style Guide

1. Do not be stuffy — write as anyone would speak in common conversation
2. Do not be hectoring or arrogant — let your analysis show weakness, don't call it "silly"
3. Do not be too pleased with yourself — don't boast of predictions or scoops
4. Do not be too chatty — "Surprise, surprise" is irritating, not informative
5. Do not be too didactic — avoid sentences starting with Compare, Consider, Expect, Imagine, Note, Remember
6. Be lucid — simple sentences help; avoid complicated constructions and gimmicks

## Sentence Craft

1. **No sentence longer than 40 words** — Aim for 25-35. Shorter for emphasis.
2. **Read aloud to check rhythm**
3. **Check every instance of 'this'** — Replace with the actor, or clarify (e.g., "This change in policy...")
4. **Conjunctions must send the right signal** — Therefore = Cause + Effect. However = contrast.
5. **Connect sentences by referencing** — Each sentence should refer to the theme or rheme of the previous
6. **Remove gerunds (-ing words)** — Be active, not passive
7. **Flip the order** — Right branch sentences (subject-verb-object first) are more assertive
8. **Verb early** — Put the verb as close to the start of the sentence as possible. Early verbs make sentences easier to parse.
9. **Subject = focus** — Make the thing you care about the subject of the main clause. "The model achieves 95% accuracy" not "95% accuracy is achieved by the model."
10. **Parallelism in lists** — Sibling items must match in grammar, capitalisation, and structure. If the first item is an imperative verb, every item is an imperative verb.
11. **Algorithms don't try, think, or want** — Attribute intentions to researchers, not methods. "Our model tries to learn X" → "We train the model to learn X." Sloppy attribution undermines interpretability and fairness claims.

## Common Issues to Fix

- **Passive voice**: "is logged and analysed" -> "the system logs and analyses it"
- **Chatty fillers**: "Here's the kicker:", "And here's the twist:", "Of course,"
- **Unnecessary words**: "currently", "precisely", "genuinely", "literally", "actually", "a bit", "fortunately", "very", "really", "extremely"
- **Redundant phrases**: "a minority — a small but eager subset" (pick one)
- **Long sentences**: Split sentences over 40 words. Long sentences with simple words are fine; long sentences packed with dense content should be split. One sentence, one idea.
- **Repeated words**: Watch for repeated "twist", "however", etc. in the same section. Do not repeat similar-sounding words in the same sentence.
- **Vague 'this'**: Always clarify what "this" refers to
- **Filler phrases**: "In order to" -> "To"; "Due to the fact that" -> "Because"; "It is important to note that" -> cut entirely; "Note that" / "Observe that" -> cut, just state the observation; "Try to X" -> "X"
- **Excessive hedging**: "It could potentially possibly be argued that X might have some effect" -> "X may affect Y". Limit "may" and "can" — hedge words should almost always be dropped. Either commit to the claim or cut it.
- **Sycophantic tone**: "Great question!", "You're absolutely right!", "I hope this helps!" -- chatbot residue; delete on sight
- **Bare comparatives**: "improves performance", "is more efficient" — compared to what? Always specify both sides of a comparison.
- **Scare quotes**: Do not use quotation marks to smuggle imprecise words in. If a term needs scare quotes, find a precise term instead.
- **Unnecessary sentences**: Ask of every sentence: "Is this necessary? Can I phrase this more simply?" Cut sentences that add no information.
- **"Etc." and "and so on"**: Be exhaustive or pick representative examples. Trailing off signals lazy thinking.
- **Number threshold**: Write whole numbers below ten as words; use numerals for 10 and above. Be consistent throughout the document.
- **Vague praise**: "interesting", "fascinating", "groundbreaking" — without argument, these are empty. Explain *why* a result matters: first result, best performance, or new knowledge.

## AI Writing Patterns to Avoid

These patterns signal machine-generated text. Never use them.

### Banned Punctuation & Syntax

- **Excessive em dashes** — use them sparingly. Prefer `;`.
- **"It's not X, it's Y"** — formulaic contrast
- **"You're not X, you're Y"** — formulaic contrast
- **"No X. No Y. Just Z."** — rule-of-threes literary variant
- **"An X with Y and Z"** — dismissive constructions
- **Mid-sentence self-questioning** — "And honestly? That's amazing."
- **doesn't just** — "doesn't just" is a cliche
- **Copula avoidance** — "serves as", "stands as", "marks", "represents", "boasts", "features", "offers" instead of "is"/"are"/"has". Use the copula.

### Banned Vocabulary

| Never use | Why |
|-----------|-----|
| `delve` | 2,700% spike post-ChatGPT |
| `tapestry`, `woven` | False complexity signals |
| `intricate`, `interplay` | Same |
| `underscore`, `highlight`, `showcase` | AI emphasis verbs |
| `meticulous`, `adept`, `swift` | Precision/speed cliches |
| `navigate` (metaphorical) | "Navigate challenges" |
| `landscape` (metaphorical) | "The AI landscape" |
| `robust` | Meaningless intensifier |
| `leverage` (verb) | Corporate AI-speak |
| `nuanced` | Usually isn't |
| `consult` | Corporate AI-speak |
| `shaped by`, `shaped this` | Corporate AI-speak |
| `additionally` | AI's favourite conjunction |
| `crucial`, `pivotal`, `vital` | Inflated importance |
| `enduring`, `lasting` | Legacy puffery |
| `foster`, `cultivate` | AI growth verbs |
| `enhance` | Vague improvement |
| `garner` | AI synonym for "get" |
| `vibrant`, `rich` (figurative) | Promotional tone |
| `nestled`, `breathtaking`, `stunning` | Travel-brochure AI |
| `testament` | "stands as a testament to" |
| `align with` | Corporate AI-speak |
| `profound` | Almost never earned |
| `interesting`, `fascinating` | Empty praise — explain *why* it matters |
| `groundbreaking` | Let the reader judge significance |
| `complex`, `rich` (as praise) | Vacuous; describe what makes it so |

### Banned Atmospheric Words

- ghosts, shadows, whispers, echoes (spectral obsession)
- "liminal" — overused atmosphere word
- forced quietness — "soft hum of distant conversation" at a loud party
- synesthesia abuse — "the texture of embarrassment," "Thursday tastes of almost-Friday"

### Banned Rhetorical Moves

- **Compulsive tricolons** — not everything needs three items
- **Empty profundity** — "carve your code into my core, etched like prophecy"
- **Mixed metaphors** — piling concepts until collapse
- **Sensory abstractions** — attaching physical senses to abstract concepts
- **Synonym cycling** — calling the same thing "the protagonist", "the main character", "the central figure", "the hero" across consecutive sentences. Pick one name and stick with it.
- **False ranges** — "from X to Y, from A to B" where X/Y aren't on a meaningful scale. "From the Big Bang to dark matter" is not a range.

### Content Inflation Patterns

- **Significance puffery** — "marking a pivotal moment in the evolution of...", "underscoring its vital role in..." Strip these. State what happened; let the reader judge importance.
- **Vague attribution** — "Experts believe", "Industry observers note", "Several sources suggest". Name the source or cut the claim.
- **Formulaic challenges sections** — "Despite challenges... continues to thrive." State the specific problem and what was done about it.
- **Generic positive conclusions** — "The future looks bright", "Exciting times lie ahead." End with a concrete fact, not optimism.

## Paragraph Craft

1. **Lead and end with strong sentences** — The first sentence of a paragraph states the point. The last sentence drives it home. Middle sentences elaborate.
2. **No orphan words** — A single word alone on the last line of a paragraph wastes space and looks ugly. Shorten a sentence in the paragraph to fix the layout.
3. **Explain uncommon terminology on first use** — Define jargon, acronyms, or domain-specific terms the first time they appear.

## Academic & Conference Papers

These rules apply to formal academic writing. They override the conversational register elsewhere in this guide.

### General

1. **Expand contractions** — "it's" -> "it is", "don't" -> "do not"
2. **Unfold possessive apostrophes** — "the model's accuracy" -> "the accuracy of the model". Formal register; aids non-native readers.
3. **Do not start every sentence with "We"** — Vary sentence openings. "We train... We evaluate... We find..." is monotonous.
4. **Do not begin sentences with conjunctions** — No "And", "But", or "Or" at the start of a sentence in formal writing.
5. **Minimum 3 sentences per paragraph** — A 1-2 sentence paragraph signals an underdeveloped idea. Occasional exceptions for transitions.
6. **Describe what your method does, not what it doesn't** — Positive framing. "Our method avoids X, Y, Z" tells the reader nothing about what the method *is*.
7. **No hostages to fortune** — Avoid claims vulnerable to easy disagreement. Replace absolute claims with qualified ones ("many" instead of "most"). If you cannot defend a one-line boast, cut it.
8. **Run a spell checker before final submission** — Overleaf misses errors that dedicated tools (e.g. Grammarly, LanguageTool) catch.

### Abstract

Structure the abstract as a 2-minute spotlight talk:

1. Contextualise the problem (1-2 sentences)
2. Identify the gap in existing approaches (1 sentence)
3. State the contribution (1 sentence)
4. Key results with concrete numbers (2-3 sentences)

Include quantitative results directly — do not tease them. Avoid generic openings that could apply to any ML paper.

### Introduction

- **Arrive at the contribution quickly** — Lengthy front-matter bores reviewers. State what you did within the first page.
- **Lead with a compelling real-world example** — Then formalise the abstract problem. Close the loop by addressing the motivating case in experiments.
- **Anticipate critical questions** — Answer them before the reader raises them.

### Layout

- **Minimise white space** — Dense layouts let you fit more content in page-limited submissions. Applies to figures, captions, section headers, and paragraph spacing.
- **Eye-catching first-page figure** — Most readers decide whether to continue based on the first page. A clear, compelling figure earns their attention.
- **Spend writing time in proportion to reading time** — Title, abstract, and introduction receive the most reader attention. Spend equal effort on each. (Adapted from Jitendra Malik.)
- **Balanced sections** — Section titles should belong to the same scope. A section should contain more than one subsection.

### Citations

- **Citation grammar** — A parenthetical citation must be removable without breaking the sentence. "Wilson et al. (2016) showed..." not "(Wilson et al. 2016) showed..."
- **Cite generously** — Especially work by likely reviewers. Fill the references section; blank bibliography pages signal carelessness.
- **Cite throughout the paper** — Not only in the Related Work section. Recent work (last 5-10 years) deserves inline citations.

### Captions

- **1-3 lines** — Avoid paragraph-length captions. The main text carries the argument.
- **State direction** — Clarify whether higher or lower is better when the answer is ambiguous.

## Essay Style

- Prose should be elegant and essayistic, with a tone that feels like a particularly thoughtful friend talking you through an idea.
- Use well-chosen concrete examples. Illustrate a point about the anxiety of status by describing the experience of walking through an airport or attending a dinner party. This grounds abstract ideas in recognisable emotional moments.
    - Do not ask readers to accept an abstract principle on its own terms.
- Write the way a brilliant after-dinner speaker talks: digressive and funny, happy to make a bold claim and then back it up with a surprising example rather than a footnote.
- Reframe — take a familiar experience and make the reader see it differently. The reader should take pleasure in the shift in perspective.
- Write with genuine warmth towards human fallibility. Do not be cynical. Find contradictions and confusion endearing rather than contemptible. Make the reader feel understood rather than judged.

## Technical Writing

- Concrete numbers beat vague claims. "2% error with 1.5KB" not "very efficient."
- One good analogy is worth five paragraphs of explanation.
- No throat-clearing ("In this post we will explore..."). Just start.
- No "In conclusion", "Let's dive in", or "Consider".

## Exemplar Quotes

These show the target register — witty, concrete, self-aware:

- "The difference between hope and despair is a different way of telling stories from the same facts"
- "Anyone who isn't embarrassed of who they were last year probably isn't learning enough"
- "The human mind does not run on logic any more than a horse runs on petrol."
- "A flower is simply a weed with an advertising budget."
- "It is much easier to be fired for being illogical than it is for being unimaginative."
- "It is better to be vaguely right than precisely wrong."
- "Most of our childhood is stored not in photos, but in certain biscuits, lights of day, smells, textures of carpet."

## A Note on Rules

This guide contains internal tensions. "Theme or rheme" is jargon in a guide that bans jargon.

Style guides are heuristics, not laws. Break any rule when following it would make the writing worse — Orwell's sixth rule applies to the whole document. The point is awareness: know when you're breaking a rule and why.

When editing AI-generated or AI-assisted text, do a final pass: ask "What still reads as obviously machine-generated?" Fix those tells, then check once more.

When editing, preserve the author's voice. Do not:

- **Standardise punctuation that carries tone** — a casual hyphen-dash or exclamation mark often signals self-aware humour. "even if I know a few!" is wry; "even if I know a few." is flat.
- **Remove personality for consistency** — mechanical uniformity kills voice. A deliberate exclamation or informal dash is not an error.
- **Over-correct based on word counts** — if a "long sentence" reads well aloud, leave it.

The author has a penchant for semi-colons; leave them be.

Ask: does this change make the writing better, or just more uniform?

## References

- [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) — comprehensive catalogue of AI text patterns, maintained by WikiProject AI Cleanup
- [Shomir Wilson: Guide for Scholarly Writing](https://shomir.net/scholarly_writing.html) — detailed academic writing guide covering language, figures, citations, and LaTeX
- [Zachary Lipton: Heuristics for Scientific Writing](https://www.approximatelycorrect.com/2018/01/29/heuristics-technical-scientific-writing-machine-learning-perspective/) — ML-focused writing heuristics covering abstracts, introductions, and positioning
