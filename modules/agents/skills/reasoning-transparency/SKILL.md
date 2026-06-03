---
name: reasoning-transparency
description: How to write analyses, research reports, recommendations, and decision memos so a reader can answer "How should I update my view in response to this?" — open with linked key takeaways, flag which considerations matter most, and state confidence + kind of support for every major claim. Load when drafting or reviewing a research write-up, evaluation, literature review, cost-effectiveness or recommendation doc, or any argument meant to move someone's beliefs; when deciding how to hedge / express uncertainty in prose; or when the user asks to make a document "more rigorous", "more transparent", "better calibrated", or "easier to trust". Distilled from Coefficient Giving (formerly Open Philanthropy) "Reasoning Transparency" by Luke Muehlhauser.
---

# Reasoning Transparency

How to write an analysis so the reader can answer the only question that matters when they read it: **"How should I update my view in response to this?"** Distilled from [Reasoning Transparency](https://coefficientgiving.org/research/reasoning-transparency/) (Luke Muehlhauser, Open Philanthropy / now Coefficient Giving, Dec 2017).

A reasoning-transparent document lets the reader cheaply judge: Is the evidence presented fairly or selectively? How much does the author know? What was the research process — what shortcuts were taken? How confident is the author in each claim, and on what basis? What's the key takeaway, and what would change the author's mind? Most scientific norms (methods sections, open data, COI statements) target this; the two things they routinely miss are **per-claim confidence** and **per-claim support** — which is where most of the cheap wins are.

## The three recommendations (do these first)

1. **Open with a linked summary of key takeaways.** Lead with the conclusions, each linking to the section that argues for it. If the summary can't link inline, follow it immediately with a linked table of contents. The reader should grasp the takeaways and drill into any one of them without reading linearly.
2. **Flag which considerations matter most.** Say *early* — in the intro, or at the top of each section — which arguments or pieces of evidence are load-bearing for the conclusion. Don't make the reader reverse-engineer what's doing the work. (Bad: a report whose conclusion rests almost entirely on RCT evidence but never says so.)
3. **State confidence + support for every major claim.** For each claim that's critical to your conclusion, indicate (a) how confident you are and (b) what kind of support you have. This is the highest-leverage habit and the rest of this skill operationalises it.

## Calibrate effort to stakes — don't gold-plate

GiveWell's [AMF review](https://www.givewell.org/charities/against-malaria-foundation) is the extreme model: 125 endnotes, support for nearly every claim, a sourced table with archived copies, an open-questions list, linked sub-reports. **That level is more costly than it's worth for almost everything.** The goal is to buy most of the transparency at a fraction of the cost — mostly via cheap inline phrasings (below) rather than exhaustive citation. Spend the effort on the *load-bearing* claims; signpost the rest quickly.

## Expressing confidence

Match precision to how central the claim is and how much you've actually investigated.

- **Words** ("plausible", "likely", "seems likely", "unlikely", "very likely") are fine for non-central claims — but remember they're [interpreted inconsistently across readers](https://en.wikipedia.org/wiki/Words_of_estimative_probability) (words of estimative probability). Use them to signal a rough direction, not a shared number.
- **Probabilities / confidence intervals** when the estimate *is* the goal of the investigation or feeds a decision: "nontrivial likelihood (at least 10% with moderate robustness, at least 1% with high robustness)"; "my 70% confidence interval is 10–120 years, though that estimate is unstable and uncertain".
- **Colloquial in text, precise in a footnote** — say "I think this is a fairly complete list" in the body, then pin it down in a footnote: "70% confident there are fewer than 5 such reviews I missed, published before Oct 2015, that include ≥5 RCTs…".
- **State instability explicitly.** A number isn't a claim to calibration. Pair it with caveats where warranted: "unstable and uncertain", "I don't have much reason to believe my judgments here are well-calibrated", "I have limited introspective access to why my brain produced these probabilities".

| Centrality of claim | Investigation done | How to express |
| --- | --- | --- |
| Core to conclusion / feeds a decision | Deep | Probability or confidence interval, + robustness/stability caveat |
| Core but hard to justify | Some | Number *plus* explicit "may be unstable / not well-calibrated" |
| Supporting, not the focus | Light | "seems likely" (>50%), "plausible" (rough impression after some reading) |
| Aside | None | "widely believed", "my guess", state you haven't checked |

## Indicating the kind of support

You can't carefully assess every claim. But you can cheaply tell the reader *what kind* of support each claim rests on, and spend more words on the key ones. Possible kinds of support, roughly strongest to weakest:

- another detailed analysis you wrote
- careful examination of studies you feel qualified / only weakly qualified to assess
- shallow skim of studies you feel qualified / only weakly qualified to assess
- verifiable facts you can / can't easily source
- expert opinion you can / can't comfortably assess
- a vague impression from various sources or conversations
- a general intuition about how the world works
- a simple argument that seems robust / questionable to you
- a complex argument that seems strong / questionable to you
- follows logically from other supported claims + background knowledge
- a source you can't remember but recall trusting, and think is easily verifiable
- any combination of the above

A good shortcut for conveying support is to **summarise the research process** behind a conclusion, including the shortcuts: "I spent less than one hour on this; I looked only at Cochrane reviews and did a few Scholar searches for rebuttals, finding none." "I did not run any literature searches — I've followed this small field since 2011 and felt I knew where the best work was." "I used my intuitions to generate the probabilities, then reflected on what factors drove them, then filled out the table." Naming the shortcut is itself transparency.

## Cheap phrasing toolkit

These one-liners buy most of the transparency for almost no cost. They'd rarely appear in a journal article — that's the point.

| Situation | Phrasing |
| --- | --- |
| Believe it but haven't verified | "Supposedly (I haven't checked), …" |
| True but not your focus, so unreviewed | "It is widely believed, and seems likely, that …" |
| Easily checkable, not worth sourcing | (state plainly; optionally footnote "easy to verify by Googling X") |
| Can't share the full reasoning | "My view rests on many undocumented conversations; I'll lay out the structure and flag which parts are well-supported vs. rely on info I can't share." |
| Reasoning too costly to summarise | "Our reasoning can't be easily summarised; it's based on extensive reading and informal conversations. See [book] for more on this point." |
| Number with no real basis | "I have very little sense of cost; my guess is $X–$Y, but this is pulled from vague memory and could be off by an order of magnitude." |
| It's just an intuition | "I find it intuitively hard to imagine that …" |
| Assumption you won't defend here | "I merely report my assumptions and link to the relevant debates; my purpose isn't to settle them, only to explain where I'm coming from." |
| Forgot the source | "We don't recall our source for this but believe it would be straightforward to verify." |
| Preliminary / unfinished work | "I'm still researching X; I only have time to point to some sources without further comment. This is a preliminary list — I haven't evaluated them and may end up with a different impression." |
| Guard against confirmation bias | "Keep in mind I began this investigation already holding [prior]; I came away more convinced, which may reflect the arguments or may reflect bias." |
| Bounding a claim's reach | "This is uncertainty about *magnitude*, not *direction*." / "This likely doesn't transfer to X, because…" |
| Reporting a curated subset | "All N ranked; the cited k span the full range (Mann-Whitney p = 0.31); the higher mean is driven by one outlier." |
| You ran an empirical study | Pre-register predictions, then score them in a Prediction / Result / Correct? table — surface the wrong rows. |

Disclose your **starting point** when it shapes the conclusion — make clear when the investigation *confirmed* a prior rather than *produced* the view.

## Sourcing (do when cheap, skip when not)

- **Quotes + page numbers** beat bare citations — quote the most relevant passage so the reader needn't track down the source. Online docs have no space limit; long quotes in footnotes are free.
- **Data and code** when possible — from an 11-sheet cost-effectiveness model down to a 14-row spreadsheet of the cases you considered. Even the *list of things you looked at* is useful.
- **Archived copies** of web sources, since links rot.
- **Transcripts or summaries of expert conversations** when interviews were a key input — but skip when too costly or when the expert will only speak anonymously / off the record.

## For empirical & technical write-ups

The source is philanthropy/literature-review flavoured; these port it to research, eval, and engineering write-ups, where the strongest signals are about what you *measured*, what *failed*, and what someone else can *re-run*.

- **Make confidence mechanical: inline-tag every load-bearing claim.** Append a uniform `[confidence: ~85%]` so the reader never infers it from prose. **Split the tag when confidence differs by regime** — separating what you measured from what you're extrapolating: `[~95% in MLP; ~75% for the LLM prediction]`, `[~90% for 1B; ~55% for 8B+]`.
- **Pre-register predictions, then score them.** A `Prediction | Result | Correct?` table that includes the **Wrong** rows is the strongest anti-cherry-picking signal in empirical work — and the misses are usually the most informative.
- **Give negative and refuting results equal billing.** A refuted hypothesis is often the most decisional content — lead with it ("**The geometry hypothesis is wrong**"). When several independent failures point the same way, enumerate them: "four independent lines of evidence converge" reads as robustness, not one fragile test.
- **Ship the runnable recipe, not "code available".** Seeds, sample sizes, exact command (`uv run scripts/<exp>.py`). Stamp each figure/table with a provenance comment pointing at what produced it (`<!-- generated-by: scripts/exp1.py -->`, `<!-- data-source: .data/output/foo.csv -->`).
- **Make evidence tables self-justifying.** Push support into the data display: intervals (`53.0% [50.9%, 55.1%]`), effect sizes (`d = 3.74`), explicit `ns` for non-significant cells — so the prose needn't restate strength.
- **Bound the scope; separate direction from magnitude.** State what the conclusion does *not* cover, and distinguish "unsure how big" from "unsure which way": "reasons for uncertainty about *magnitude*, not *direction*." Name the single most important missing piece explicitly.
- **State a selection test when reporting a subset.** If you (or a paper you're replicating) curated examples, test the subset against the full set and say so ("all 53 ranked; the cited 10 span the full range; Mann-Whitney p = 0.31"). Naming the outlier driving a headline number is itself transparency.

## Checklist

- [ ] Opens with key takeaways, each linked to its supporting section (or a linked TOC follows immediately)
- [ ] The load-bearing considerations are named up front, not left implicit
- [ ] Every *major* claim carries a confidence signal (word, probability, or interval) matched to its stakes
- [ ] Every major claim signals what *kind* of support it rests on
- [ ] Central numeric estimates note their stability / calibration
- [ ] The research process — and the shortcuts taken — is summarised
- [ ] Key citations give page numbers and quote the relevant passage
- [ ] Data/code/sources provided where cheap; effort concentrated on load-bearing claims, not gold-plated everywhere
- [ ] Confidence inline-tagged on load-bearing claims, split by regime where it differs
- [ ] Predictions pre-registered and scored, with the wrong ones surfaced
- [ ] Negative/refuted results get equal billing; converging independent evidence enumerated
- [ ] Scope + threats-to-validity stated, separating uncertainty of *direction* from *magnitude*
- [ ] Reproducibility recipe given (seeds, N, exact command); figures stamped with provenance
- [ ] Confidence numbers' origin/calibration stated once (tags alone aren't enough)

## Related

- [[research-meeting-playbook]] — Tsai's "give as much signal as reasonable on *how* you're reasoning" points directly at this; reasoning transparency is the written form of increasing the surface area for mistakes to be noticed.
- `prose-conventions` skill — general writing voice and AI-pattern avoidance; this skill is the *epistemic* layer on top.
