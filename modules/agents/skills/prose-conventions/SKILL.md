---
name: prose-conventions
description: Writing style conventions for prose, essays, and non-fiction. Apply when writing or editing text. Covers voice, sentence structure, AI patterns to avoid, and editorial principles.
---

# Prose Conventions

Apply these principles when writing or editing prose. The author is British — use British spelling (colour, organise, centre), idioms, pounds and pence, and metric units. A British anecdote priced in dollars (10p fines against a $0.189/kWh tariff) is a draft that pulled its number from an American source; convert it.

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
- **Filler phrases**: "In order to" -> "To"; "Due to the fact that" -> "Because"; "It is important to note that" / "It's worth noting" -> cut entirely; "Note that" / "Observe that" -> cut, just state the observation; "Try to X" -> "X"
- **Excessive hedging**: "It could potentially possibly be argued that X might have some effect" -> "X may affect Y". Limit "may" and "can" — hedge words should almost always be dropped. Either commit to the claim or cut it. Specific AI hedge phrases to strip: "arguably", "it could be said", "in many ways", "to some extent".
- **Sycophantic tone**: "Great question!", "You're absolutely right!", "I hope this helps!" -- chatbot residue; delete on sight
- **Bare comparatives**: "improves performance", "is more efficient" — compared to what? Always specify both sides of a comparison.
- **Scare quotes**: Do not use quotation marks to smuggle imprecise words in. If a term needs scare quotes, find a precise term instead. Quoting a word someone actually said is reported speech, not a scare quote: `He called it "wasteful", I called it "cheap"` stays.
- **Unnecessary sentences**: Ask of every sentence: "Is this necessary? Can I phrase this more simply?" Cut sentences that add no information.
- **"Etc." and "and so on"**: Be exhaustive or pick representative examples. Trailing off signals lazy thinking.
- **Number threshold**: Write whole numbers below ten as words; use numerals for 10 and above. Be consistent throughout the document.
- **Vague praise**: "interesting", "fascinating", "groundbreaking" — without argument, these are empty. Explain *why* a result matters: first result, best performance, or new knowledge.

## AI Writing Patterns to Avoid

These patterns signal machine-generated text. Never use them.

### Banned Punctuation & Syntax

- **Excessive em dashes** — zero to two in the whole piece. A paired parenthetical (`-- like this --`) counts as one use, and `--` in markdown source counts the same as a typeset `—`. Replace with periods, commas, parentheses, or cut entirely. Not a rhythm tool. Prefer `;`. This is a house style rule, not a detection signal: em dashes are now a weak tell, since OpenAI suppressed them in GPT-5.1 and a July 2026 study found Claude the only current model using them more than professional writers. Since drafting happens in Claude, the rule matters *more* here, not less. The author's own dash is a spaced hyphen (` - `): the first-person blog pieces use it four to nine times each and contain no em dashes at all. It does not count toward the limit and is never upgraded to `—` or `--`.
- **Negative parallelisms** — the whole family, not just the famous one. "Not only X, but also Y"; "It's not X, it's Y"; "You're not X, you're Y"; "No X. No Y. Just Z."; "X isn't A — it's B"; and the quieter variant **"X rather than Y"** / "Rather than A, it constitutes B". The move fakes a correction to a misconception nobody held. State what the thing is.
- **"An X with Y and Z"** — dismissive constructions
- **Mid-sentence self-questioning** — "And honestly? That's amazing."
- **doesn't just** — "doesn't just" is a cliche
- **Copula avoidance** — "serves as", "stands as", "functions as", "operates as", "marks", "represents", "boasts", "features", "maintains", "offers", "refers to" instead of "is"/"are"/"has". Use the copula. The elaborated form counts too: "ventured into politics as a candidate" is "was a candidate"; "began his career as" is "was". Measured drops of >10% in "is"/"are" are the single most-replicated signature of LLM copyediting.
- **Vague expression of connection** — "in connection with", "in association with", "associated with", "connected to". Reaching for an abstract link instead of naming the relationship. Use "of", "for", "by", or say what the relationship actually is: "worked with", "used in", "caused by", "founded". "He is associated with the orchestra" → "He plays violin in the orchestra."
- **Participial commentary** — a sentence that states a fact, then tacks on an `-ing` clause telling the reader what it means: "…, highlighting the collaborative nature of the work", "…, underscoring its importance", "…, reflecting broader trends", "…, ensuring accuracy", "…, contributing to the region's growth". The clause is almost always unfalsifiable filler bolted onto a real fact. Cut it, or make it a separate sentence with a source. Watch `highlighting, underscoring, emphasizing, reflecting, symbolizing, ensuring, fostering, cultivating, encompassing, enhancing`.

### Banned Vocabulary

The list is not a rule about register. A word being overused by a model does not taint its synonyms, and formal or academic prose is not itself a tell — these are *specific words*, and context still decides ("underscore" the typographic mark is fine). Read this list literally.

**Which words date a draft.** The overused set turns over as models change, so the current tells are the useful ones:

- *2023–mid-2024 (GPT-4 era, now a dating signal for old text):* delve, tapestry, intricate, interplay, boasts, bolstered, garner, meticulous, pivotal, testament, vibrant, landscape, key, valuable, Additionally
- *Mid-2024–mid-2025:* align with, enhance, enduring, fostering, highlighting, showcasing, underscore, emphasizing, pivotal
- *Mid-2025 onward — the live ones:* **emphasizing, enhance, highlighting, showcasing**, plus the notability/attribution puffery below
- *Grok, distinctively:* causal, empirical, correlate — and it still overuses underscore in 2026

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
| `additionally`, `furthermore`, `moreover`, `ultimately`, `indeed`, `that said`, `in conclusion` | AI connective tissue |
| `crucial`, `pivotal`, `vital`, `plays a crucial role` | Inflated importance |
| `ecosystem`, `synergy`, `the space` (vague nouns) | Replace with concrete things |
| `realm`, `dive into` | AI spatial metaphors |
| `meaningfully`, `seamless`, `credible`, `beautifully unpredictable`, `quietly radical`, `disproportionate effect` | AI modifier tells |
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
| `spine` (metaphorical) | "the spine of the argument" — AI structural metaphor |
| `the gap`, `the disconnect`, `the tension`, `the delta` (as a punchline) | Abstract noun standing in for the point you failed to make. "The number worth carrying is the gap" says nothing the numbers did not already say. Fine in its literal sense ("identify the gap in prior work"); banned as the predicate of a summarising sentence |
| `emphasize`, `emphasizing` | Live 2026 tell; usually a [participial commentary](#banned-punctuation--syntax) clause |
| `bolstered` | AI synonym for "strengthened" or "backed" |
| `valuable`, `valuable insights` | Empty appraisal; say what the insight was |
| `key` (as an adjective) | "key craftsmen", "key role" — carries no information |
| `deep dive` | Corporate AI-speak, same family as `dive into` |
| `exemplifies` | Copula avoidance dressed as analysis |
| `renowned`, `esteemed`, `acclaimed` | Unsourced reputation puffery |
| `diverse array`, `wide range of`, `a multitude of` | Filler quantifier; give the actual set or count |
| `nestled in the heart of`, `natural beauty` | Travel-brochure AI |
| `commitment to` | "demonstrates its commitment to" — states an intention, not a fact |
| `resonate with`, `encompassing` | AI abstraction verbs |
| `indelible mark`, `deeply rooted`, `focal point`, `turning point` | Significance puffery nouns |
| `setting the stage for`, `reflects broader` | Narrative glue implying a causal claim you have not made |
| `lift` (as a multiplier) | "a 10x lift", "a 0.2x lift" — growth-marketing noun for a ratio; give the before and after numbers instead. A 0.2x lift is a fall. The literal lift to the third floor is fine |

### Banned Atmospheric Words

- ghosts, shadows, whispers, echoes (spectral obsession)
- "liminal" — overused atmosphere word
- forced quietness — "soft hum of distant conversation" at a loud party
- synesthesia abuse — "the texture of embarrassment," "Thursday tastes of almost-Friday"

### Banned Rhetorical Moves

- **Compulsive tricolons** — a balanced three-item list ("X, Y, and Z") is a fingerprint. Break to two, split across sentences, or disrupt with an off fourth item. The ban targets balanced abstract triads; a list of concrete specifics ("blog posts, conference slides, and LinkedIn thought pieces") earns its place, and a four-item list is already the fix, not the disease.
- **Formulaic openings** — "In today's fast-paced world", "In the age of X", "There is something almost mythic about..."
- **Empty profundity** — "carve your code into my core, etched like prophecy"
- **Mixed metaphors** — piling concepts until collapse
- **Sensory abstractions** — attaching physical senses to abstract concepts
- **Synonym cycling** — calling the same thing "the protagonist", "the main character", "the central figure", "the hero" across consecutive sentences. Pick one name and stick with it.
- **False ranges** — "from X to Y, from A to B" where X/Y aren't on a meaningful scale. "From the Big Bang to dark matter" is not a range.
- **Takeaway announcements** — "The number worth carrying is X", "The thing to remember is Y", "What matters here is Z", "The interesting part is...", "The important part is...", "The real story is...", "The key insight is...", "The key takeaway is...", and "This is the number/part/bit/thing that...". A label pasted on a fact, telling the reader which bit to be impressed by before they have seen it. If the fact is striking, it lands unannounced; if it needs the label, it is not striking. Cut the frame and state the fact. Watch for it clustering: the tic repeats across a document once it appears, and every instance reads as the same voice-over. Essay register only — an abstract's contribution sentence ("Our key insight is that X") is doing the work the section exists for, not pasting a label on it.

### Content Inflation Patterns

- **Significance puffery** — "marking a pivotal moment in the evolution of...", "underscoring its vital role in..." Strip these. State what happened; let the reader judge importance.
- **Vague attribution** — "Experts believe", "Industry observers note", "Several sources suggest". Name the source or cut the claim.
- **Formulaic challenges sections** — "Despite challenges... continues to thrive." State the specific problem and what was done about it.
- **Generic positive conclusions** — "The future looks bright", "Exciting times lie ahead." End with a concrete fact, not optimism.

### Formatting Tells

Layout gives a draft away faster than vocabulary does, because it survives editing. These apply to markdown, docs, and slides.

- **Title Case Headings** — chatbots capitalise every main word. Use sentence case.
- **Headings that contain only headings** — an `##` whose entire body is a stack of `###`s. Either write the connecting prose or flatten the level.
- **Skipped heading levels, stray level-1s** — jumping `#` → `###`, or peppering a document with `#` headings, is markdown-to-anything-else conversion damage.
- **Inline-header vertical lists** — every bullet shaped `**Bold lead-in:** one sentence of explanation.` A few are fine; a page of nothing else is a slide deck pretending to be prose. Break some into real paragraphs.
- **Mechanical boldface** — bolding every instance of a chosen term, or bolding the "key takeaway" of each bullet. Bold marks a term on first definition; it is not emphasis paint. Inherited from readmes, listicles and sales decks.
- **Emoji as formatting** — emoji prefixing headings or bullets. Never.
- **Thematic breaks between every section** — a `---` rule under each heading. Delete them; the heading is the break.
- **Curly quotes and apostrophes** — “ ” ’ mixed in with straight ones. Weak on its own (Word, macOS and Chicago style all produce them, and Claude and Gemini typically do not), but inconsistent pairs inside one document mean pasted output.
- **Tables for things that are not tabular** — two-column tables holding prose, or a table where a list would do.

### Not a tell — do not "fix" these

Over-correction has a cost: stripping these makes prose *more* machine-like, and accusing a person of AI on this evidence is simply wrong.

- **Perfect grammar**, and **fancy, academic or formal prose**. The vocabulary list is specific words, not a register.
- **Bland or robotic-sounding prose** — that is a genre, not a fingerprint. LLM output actually skews positive and verbose.
- **Mixed casual/formal register** — normal for technical writers, for the young, and for the playful.
- **Transition words in isolation** — only a handful are overused; essayists have always used them.
- **An em dash or a curly quote on its own.** Weak signals; they count only in combination.
- **Mock-formal diction on a trivial subject** — "railed against the sheer injustice", "parental strife, I salute you", "the offending bulb", "set that story straight". The joke is the gap between the register and the stakes. The stuffiness rule and the vocabulary list are about earnest prose; leave bathos alone.
- **Questions that are someone's actual thoughts** — "How much could a light bulb really cost? Could I just pay a lump sum?" is the author at ten thinking, not the essayist stacking rhetorical questions at the reader. `cliche-check.py` flags both as `stacked-questions`; keep the first kind.

### Human Signals — sprinkle these in

Small imperfections that make prose sound like a person. From the Pangram reflection convergence.

- **Real asides** — "give or take", "or whatever", "I forget the exact number", "this took me longer than I'd like to admit"
- **Concrete specifics** — brand names, dollar amounts, street names, weather, times ("8 a.m."), named objects, a bulb's part number with a link to the archived catalogue. Replaces vague abstract nouns.
- **Vary list/step openings** — in numbered or stepped content, don't make every item start with an imperative verb. Alternate structures.

Constructions measured as more common in human writing than in LLM output over 25 years of Wikipedia — LLMs avoid them while reaching for "formal, neutral" tone:

- **Plain is/has phrases** — "there is a", "it has a". The copula rule again, from the other side.
- **Short verbs over stiff synonyms** — wrote (not authored), moved (not relocated), used (not utilised), tried (not attempted), died (not passed away).
- **Definite or superlative statements** — "was the first", "is the only", "one of the best". Where the fact supports it, commit.
- **The occasional wordy construction** — "as a result of", "in order to", "the fact that". These stay on the cut list; an isolated survivor is not a defect.

This cuts against the hedging ban above, and the tension is real: **very**, **perhaps** and **tends to** read as human precisely because they are imprecise. Resolve it by target — cut hedges that dodge a claim you could make, keep the ones that mark genuine uncertainty.

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

## Figure Captions

Every caption should answer three questions in order: *what am I looking at*, *how should I read it*, and *what should I conclude*.

1. **Self-contained** — A reader should understand the figure without reading the surrounding text. You could rip any figure out and it would still make sense.
2. **Define terms inline** — Don't assume the reader remembers what a metric means. Restate definitions in the caption (e.g. "0 = uniform prediction, 100 = perfect foresight"; "replaceability = reduction in score when removing a model").
3. **State the takeaway** — Don't just describe axes and labels. Say what the reader should conclude. "gpt-oss-120b climbs 7 points and marginally exceeds Gemini 3 Pro" not "shows training curves". State it directly, not as an instruction: "The crosshatching makes dots hard to count", never "Note the crosshatching". Captions are where didactic "Note the X" openers sneak in.
4. **Include specific numbers** — Ensemble weights (40%, 20%, 20%, 20%), score improvements (38.6 → 45.8), chosen baselines (18.8%). Ground the caption so the figure is verifiable.
5. **Explain design choices** — Why the Y-axis is truncated at 22.3, what marker colour encodes, why a particular baseline is chosen. Prevent misreading.
6. **Short enough to scan** — Most captions should be 2–3 sentences. Earn extra length only by packing in necessary context.
7. **1-3 lines** — Avoid paragraph-length captions. The main text carries the argument.
8. **State direction** — Clarify whether higher or lower is better when the answer is ambiguous.

## Essay Style

- Prose should be elegant and essayistic, with a tone that feels like a particularly thoughtful friend talking you through an idea.
- Use well-chosen concrete examples. Illustrate a point about the anxiety of status by describing the experience of walking through an airport or attending a dinner party. This grounds abstract ideas in recognisable emotional moments.
    - Do not ask readers to accept an abstract principle on its own terms.
- Write the way a brilliant after-dinner speaker talks: digressive and funny, happy to make a bold claim and then back it up with a surprising example rather than a footnote.
- Write in the first person, and when the piece needs a fool, be the fool. The warmth-towards-fallibility rule points inward first: the person who never looked up the price because facts might prove him wrong is the author, and a reader forgives a lesson from someone who has already confessed to the crime.
- Open on a scene you were in, not on the topic. A bathroom light seen from the stairs; a Californian bin labelled LANDFILL. The scene carries the emotional weight of the argument, and the numbers come after it.
- Show the arithmetic. Put the inputs, the formula and the result on the page as plain lines (`10p × 0.25 × 365`; `4 W × 8760 h / 1000 = 35 kWh`), link the source of every input, then land the answer in one short sentence ("A far cry from the fines."). A reader who can check the sum trusts the claim built on it; a reader handed only the result is being asked for faith. The two-calculation shape works well: the wrong sum as it was done at the time, then the honest one.
- Reframe — take a familiar experience and make the reader see it differently. The reader should take pleasure in the shift in perspective.
- Write with genuine warmth towards human fallibility. Do not be cynical. Find contradictions and confusion endearing rather than contemptible. Make the reader feel understood rather than judged.
- Prefer unfolding cadence to drumbeat cadence. Let a paragraph develop an idea, turn it once, then land it. Avoid stacks of short verdict sentences unless you need a deliberate jolt. In blog pieces a paragraph is one to three sentences; the three-sentence minimum belongs to papers.
- Do not make every insight sound like a slogan. A line can be neat; it should not feel pre-fabricated. If a sentence reads like a maxim dropped in from above, soften it with explanation, example, or a human observation.
- Let conclusions feel discovered, not announced. The final instruction or claim should sound like the natural end of the argument, not a poster slogan pasted on top. One plain sentence of moral is fine once the piece has argued its way there, and a P.S. or footnote at the author's expense after it stops the piece ending on the maxim.
- Mix sentence lengths. A short sentence works best after a longer one has set it up. Too many short declarative sentences in a row make the prose sound abrupt and prosecutorial.
- Preserve warmth in analytical writing. When describing confusion, ambiguity, or disagreement, sound interested rather than exasperated.

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

Reference samples of the author's own voice, for calibration before editing their drafts:

- `writing/blog/sorry-dad-lights-are-expensive.md` in the kb repo. A childhood dispute settled by arithmetic and then reframed as a question of etiquette. First person, spaced-hyphen dashes, mock-formal diction for comedy, the working shown on the page, a moral in one sentence and a self-deprecating P.S. after it. About 440 words, average 17 words a sentence, range 4 to 42.

## A Note on Rules

This guide contains internal tensions. "Theme or rheme" is jargon in a guide that bans jargon.

Style guides are heuristics, not laws. Break any rule when following it would make the writing worse — Orwell's sixth rule applies to the whole document. The point is awareness: know when you're breaking a rule and why.

When editing AI-generated or AI-assisted text, do a final pass: ask "What still reads as obviously machine-generated?" Fix those tells, then check once more.

When editing, protect informality and personality — but nothing else. Do not:

- **Standardise punctuation that carries tone** — a casual hyphen-dash or exclamation mark often signals self-aware humour. "even if I know a few!" is wry; "even if I know a few." is flat.
- **Remove personality for consistency** — mechanical uniformity kills voice. A deliberate exclamation or informal dash is not an error.
- **Resolve the author's draft markers** — `(editable)`, `TODO:`, an empty `P.S.`, a `^1` with no footnote yet. They are notes for a later version. Leave them in place and ask before filling or deleting one.

The author has a penchant for semi-colons; leave them be, including the odd one that splits a clause where a comma would ("what benefit would facts have; when they could prove me wrong").

Spelling, malapropisms ("hierocracy" for "hypocrisy", "urked" for "irked") and unit slips ("4Wh" for "4W") are never voice. Fix them without comment.

This protection is never an exemption from the content rules. A slogan, an unglossed metaphor pair, or a having-it-both-ways verdict fails this guide whether it is new text or carried over verbatim from an earlier draft — "it was already there" and "that's the author's framing" are not defences. Pre-existing prose gets the same pass as new prose. (This clause exists because a carried-over maxim — "survived as structure, failed as arithmetic" — was once waved through as voice; it was spin.)

Ask: does this change make the writing better, or just more uniform?

## Scripts

Three helpers ship in this skill's directory:

- `prose-lint.sh <file ...>` — scans files for the patterns above (banned vocabulary, copula avoidance, vague connection, filler, sycophancy, significance puffery, negative parallelisms, unnecessary words and hedges, participial "-ing" commentary, vague attribution, rule-of-three, takeaway announcements, punchline abstractions), plus file-level formatting tells (curly quotes, emoji and Title Case headings, bold lead-in bullet runs, stray horizontal rules, em dash density). Word lists are kept in sync with this guide. Skips markdown tables, import lines, and YAML frontmatter keys. Requires `rg`; exits non-zero when it finds hits.
- `sentence-stats.sh <file>` — per-sentence word counts plus a summary (average, range, standard deviation). Flags sentences over 40 words, low rhythm variety (stddev < 4), and a lack of short punchy sentences. Strips YAML frontmatter, tables, imports, and JSX before counting, so MDX files report prose only.

- `cliche-check.py <file ...>` — a port of Simon Willison's [LLM cliché highlighter](https://tools.simonwillison.net/llm-cliche-highlighter), matching its whole pipeline rather than only its patterns:

  1. **38 detectors**, including the five needing run-detection rather than a regex — "no X, no Y" chains, "did not X, did not Y" chains, echoing sentence runs, stacked rhetorical questions, repeated sentence openers — each reporting a count badge.
  2. **Overlap suppression**, so `pivotal` is not reported separately inside `plays a pivotal role`. This is why the hit count is lower than the sum of the finders.
  3. **Sentence expansion** (`--context sentence`), the CLI form of the tool tinting the sentence around a highlight.
  4. **±12-word context windows** (`--windows`), the "show just the highlights" view.

  `--list` prints the inventory, `--only`/`--skip` select ids, `--stats` gives per-pattern counts. Stdlib only: `uv run cliche-check.py <file>`.

  Parity is pinned by fixtures captured from upstream, not by our own guesses — its 182-case corpus for the finders and a golden dump of its pipeline over its own example text. Run `uv run --python 3.13 --with pytest pytest tests/`, and see `tests/fixtures/README.md` to refresh. The pipeline fixture earns its keep: a finder-only corpus passed 182/182 while the port was still missing overlap suppression entirely.

Run all three before the manual editing pass; treat hits as candidates to review, not automatic rewrites.

`prose-lint.sh` and `cliche-check.py` overlap on vocabulary and deliberately stay separate: the first tracks this guide and is yours to edit freely, the second tracks an upstream tool and should only change when upstream does.

## References

- [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) — catalogue of AI text patterns, maintained by WikiProject AI Cleanup. Actively edited; last pulled into this guide 28 August 2026. Refetch before trusting the era breakdown — the live tells turn over every few months, and the page keeps a "Historical indicators" section for signals that have aged out (didactic "it's important to note" disclaimers, "In conclusion" section summaries, "as an AI language model", abrupt cut-offs). Those stay banned here on style grounds; their *absence* proves nothing.
- [LLM cliché highlighter](https://tools.simonwillison.net/llm-cliche-highlighter) (Simon Willison) — paste or load a URL, highlights matched clichés in context with per-pattern toggles and counts. Runs client-side. Complements `prose-lint.sh` for text you did not write.
- [The load-bearing vocabulary of Claude](https://louisabraham.github.io/load-bearing/) (Louis Abraham) — cluster analysis of GitHub PR text, refreshed daily, tracking which words are becoming characteristic over time. The empirical counterpart to the hand-curated list above; useful for spotting new tells before a style guide catches them.
- [Shomir Wilson: Guide for Scholarly Writing](https://shomir.net/scholarly_writing.html) — detailed academic writing guide covering language, figures, citations, and LaTeX
- [Zachary Lipton: Heuristics for Scientific Writing](https://www.approximatelycorrect.com/2018/01/29/heuristics-technical-scientific-writing-machine-learning-perspective/) — ML-focused writing heuristics covering abstracts, introductions, and positioning
