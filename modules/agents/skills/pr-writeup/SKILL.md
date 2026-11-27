---
name: pr-writeup
description: >-
  Write or refresh substantial research PR descriptions and their durable repository writeups,
  including experiments, evaluations and datasets. Use for evidence, figures, terminology,
  denominator checks and stale-result audits. Small fixes and routine software PRs do not need
  this workflow.
---

# Research PR descriptions and writeups

A research PR description should let a reader assess the question, method, evidence and limits
without opening the diff. Scale the detail to the work; do not make a small fix into a paper.
Use the repository's established documentation format and any required PR template.

## Establish the current claim

Read the current diff, results tables, rendered figures and existing writeup before drafting.
Use completed results from the reviewed revision. Separate measured findings from hypotheses,
interpretations and work that remains unrun. Do not run new experiments or spend money just to
fill a section of the description.

Lead with the research question and the result that matters most. If the work builds on an
earlier result, explain that motivation and link the earlier evidence. Surface failed
replications, null results and material corrections alongside positive findings. The largest
movement visible in the figure belongs in the takeaway, even when it complicates the argument.

Give non-obvious terms and coined labels short definitions near their first use. Explain an
important mechanism with a concrete, checkable example from the work. An aggregate worked
example can be more appropriate than a transcript. Distinguish real observations from synthetic
illustrations; do not invent quotations or present a paraphrase as model output.

## Make the evidence assessable

- Give every rate its numerator or count and its denominator: attempts, answered requests,
  accepted labels, people and conversations are different units. Name selection and exclusions.
- Report uncertainty where it was measured and say what the interval conditions on. A sampling
  interval does not include classification error, dataset selection or model variation by default.
- For model-generated or model-graded rates, show the available response-quality counts beside
  the result: empty, refused, truncated, unparseable or degenerate responses, as applicable.
  Do not silently count failures as negative verdicts. If a quality property was not assessed,
  say so rather than equating parse success with valid content.
- Name what the instrument cannot observe, its preconditions and known confounds. Agreement
  between graders is not accuracy. Correlation between aggregates does not identify individuals.
- Keep paired comparisons on a common cohort where possible. When arms have different cohorts,
  show that explicitly and distinguish cohort changes from changes in the measurement.
- Link the actual prompt definitions, runner, aggregation code, result tables and full writeup.
  Prefer links at the reviewed commit for PR evidence; verify paths and figure provenance.
- Link existing run records or traces for load-bearing model-call types when available and
  appropriate. Explain unavailable or access-restricted evidence. Do not assume another
  repository's tracing system exists here, regenerate model calls to obtain traces, or publish
  confidential transcripts to satisfy an example or trace requirement. Follow the task's
  data-handling rules and use permitted aggregate evidence when raw examples cannot be shared.

Useful structure, adapted to the work: motivation and main result; terminology; method and
cohorts; results with figures; limitations and corrections; reproduction and validation. Include
next steps only when they follow from the evidence and are useful to the reviewer. Respect the
repository's existing plan rather than inventing a roadmap.

## Figures and flows

For a substantial empirical comparison, inline an informative figure when one exists. Give it
a caption explaining what the axes or cells measure and why the comparison answers the question.
If predictions were registered, report their outcomes; do not invent retrospective predictions.

Look at the rendered image before publishing. For a visual fix or restyle, show the relevant
before and after renders. For a claimed visual invariant, show both tested conditions. Numeric
layout checks alone cannot establish that a figure is readable.

Use image URLs that actually render in the PR. Private-repository blob/raw links and relative
paths often fail in PR bodies; use an authorised artifact host or attachment mechanism. Upload
only material already suitable for that audience. Keep the image's repo-relative path in its
alt text, and put the human-facing explanation in the caption. Where the repository has an
upload skill or command, use it rather than inventing a second hosting path.

For a branching pipeline or multi-stage comparison that is hard to follow in prose, add a small
Mermaid flow or state diagram. Keep it consistent with the method in the durable writeup.

## Keep the record durable

Use the existing repository writeup as the source of truth. If none exists, save a writeup in
the established documentation location and link it to the PR. The PR can be a self-contained
digest of a longer report; avoid creating a competing copy of the narrative solely for the PR.
Repository writeups should use repo-relative links or PR links rather than branch URLs that
will die when the branch is deleted.

When results, figures or scope change, update the PR and affected writeups together. Sweep
documents that quote superseded results. A substantive correction should name the old claim,
explain the corrected evidence, state which conclusions survive, and mark affected writeups as
superseded where needed. Check inbound links before renaming documented headings.

Before publishing the description, check:

- The body describes the final work; completed work is not still called queued or pending.
- Counts reconcile with the tables, each denominator is explicit, and captions match the renders.
- Source links resolve; embeds use the correct image bytes and preserve their repo paths.
- The durable writeup is tracked in the PR and agrees with the description.
- Validation is reported as performed, with unresolved failures or unmeasured properties named.
- Required attribution or automation-loop footers are preserved as the last line.

This skill does not authorise uploads, external posts, paid calls or merging. Follow the user's
request, existing permissions and repository rules for those actions. If merging is requested,
check the durable writeup and final-result consistency before proceeding.
