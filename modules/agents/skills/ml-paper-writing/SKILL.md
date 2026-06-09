---
name: ml-paper-writing
description: Write publication-ready ML/AI papers for NeurIPS, ICML, ICLR, ACL, AAAI, COLM. Use when drafting papers from research repos, structuring arguments, verifying citations, or preparing camera-ready submissions. Includes LaTeX templates, reviewer guidelines, and citation verification workflows.
version: 1.0.0
author: Orchestra Research
license: MIT
dependencies: [semanticscholar, arxiv, habanero, requests]
metadata:
  hermes:
    tags: [Academic Writing, NeurIPS, ICML, ICLR, ACL, AAAI, COLM, LaTeX, Paper Writing, Citations, Research]

---

# ML Paper Writing for Top AI Conferences

Expert-level guidance for writing publication-ready papers targeting **NeurIPS, ICML, ICLR, ACL, AAAI, and COLM**. Combines writing philosophy from top researchers (Nanda, Farquhar, Karpathy, Lipton, Steinhardt, Perez) with practical tools: LaTeX templates, citation verification APIs, and conference checklists. This file is the summary; the deep dives live in [references/](references/).

## When to Use This Skill

- **Starting from a research repo** to write a paper
- **Drafting or revising** specific sections
- **Finding and verifying citations** for related work
- **Formatting** for conference submission
- **Resubmitting** to a different venue (format conversion)
- **Iterating** on drafts with scientist feedback

**Always remember**: First drafts are starting points for discussion, not final outputs.

---

## Core Philosophy: Collaborative but Proactive

Paper writing is collaborative, but be proactive in delivering drafts. Understand the project (repo, results, docs), deliver a complete first draft when confident, search literature via APIs, then refine through feedback cycles. Don't block waiting for feedback on every section—produce something concrete the scientist can react to.

| Confidence Level | Action |
|-----------------|--------|
| **High** (clear repo, obvious contribution) | Write full draft, deliver, iterate on feedback |
| **Medium** (some ambiguity) | Write draft with flagged uncertainties, continue |
| **Low** (major unknowns) | Ask 1-2 targeted questions, then draft |

**Only block for input when**: target venue is unclear, contradictory framings seem equally valid, results look incomplete/inconsistent, or review is explicitly requested. Per-section flagging tables and repo-exploration steps: [references/paper-workflow.md](references/paper-workflow.md).

---

## ⚠️ CRITICAL: Never Hallucinate Citations

AI-generated citations have a **~40% error rate**. Hallucinated references are academic misconduct that can cause desk rejection or retraction.

**The Rule: NEVER generate BibTeX from memory. ALWAYS fetch programmatically.**

```
Citation Verification (MANDATORY for every citation) — Workflow 2:
- [ ] Step 1: Search using Exa MCP or Semantic Scholar API
- [ ] Step 2: Verify paper exists in 2+ sources (Semantic Scholar + arXiv/CrossRef)
- [ ] Step 3: Retrieve BibTeX via DOI (programmatically, not from memory)
- [ ] Step 4: Verify the claim you're citing actually appears in the paper
- [ ] Step 5: Add verified BibTeX to bibliography
- [ ] Step 6: If ANY step fails → mark as placeholder, inform scientist
```

If you cannot verify a citation, mark it explicitly and tell the scientist:

```latex
\cite{PLACEHOLDER_author2024_verify_this}  % TODO: Verify this citation exists
```

### Summary: Citation Rules

| Situation | Action |
|-----------|--------|
| Found paper, got DOI, fetched BibTeX | ✅ Use the citation |
| Found paper, no DOI | ✅ Use arXiv BibTeX or manual entry from paper |
| Paper exists but can't fetch BibTeX | ⚠️ Mark placeholder, inform scientist |
| Uncertain if paper exists | ❌ Mark `[CITATION NEEDED]`, inform scientist |
| "I think there's a paper about X" | ❌ **NEVER cite** - search first or mark placeholder |

APIs, Python code, Exa MCP setup, BibTeX management: [references/citation-workflow.md](references/citation-workflow.md).

---

## The Narrative Principle

**Your paper is not a collection of experiments—it's a story with one clear contribution supported by evidence.** Neel Nanda: "A paper is a short, rigorous, evidence-based technical story with a takeaway readers care about."

Three pillars must be crystal clear by the end of the introduction:

| Pillar | Description | Example |
|--------|-------------|---------|
| **The What** | 1-3 specific novel claims within cohesive theme | "We prove that X achieves Y under condition Z" |
| **The Why** | Rigorous empirical evidence supporting claims | Strong baselines, experiments distinguishing hypotheses |
| **The So What** | Why readers should care | Connection to recognized community problems |

**If you cannot state your contribution in one sentence, you don't yet have a paper.** Full framework: [references/writing-guide.md](references/writing-guide.md#the-narrative-principle).

---

## Workflow 0: Starting from a Research Repository

```
Project Understanding:
- [ ] Step 1: Explore the repository structure
- [ ] Step 2: Read README, existing docs, and key results
- [ ] Step 3: Identify the main contribution with the scientist
- [ ] Step 4: Find papers already cited in the codebase
- [ ] Step 5: Search for additional relevant literature
- [ ] Step 6: Outline the paper structure together
- [ ] Step 7: Draft sections iteratively with feedback
```

Existing citations in the repo are high-signal Related Work starting points. **Never assume the narrative—confirm the contribution framing with the scientist.** Step-by-step commands and draft-delivery guidance: [references/paper-workflow.md](references/paper-workflow.md#workflow-0-starting-from-a-research-repository).

---

## Workflow 1: Writing a Complete Paper (Iterative)

Each step is draft → feedback → revise:

```
Paper Writing Progress:
- [ ] Step 1: Define the one-sentence contribution (with scientist)
- [ ] Step 2: Draft Figure 1 → get feedback → revise
- [ ] Step 3: Draft abstract → get feedback → revise
- [ ] Step 4: Draft introduction → get feedback → revise
- [ ] Step 5: Draft methods → get feedback → revise
- [ ] Step 6: Draft experiments → get feedback → revise
- [ ] Step 7: Draft related work → get feedback → revise
- [ ] Step 8: Draft limitations → get feedback → revise
- [ ] Step 9: Complete paper checklist (required)
- [ ] Step 10: Final review cycle and submission
```

Key constraints per step:

- **Contribution**: requires explicit scientist confirmation
- **Figure 1**: many readers skip straight to it—vector graphics, standalone caption, B&W-readable
- **Abstract**: Farquhar's 5-sentence formula (achievement → why hard → how → evidence → best number); delete generic openings
- **Introduction**: ≤1.5 pages, 2-4 contribution bullets, methods start by page 2-3
- **Methods**: enable reimplementation—pseudocode, all hyperparameters, architecture details
- **Experiments**: each states the claim it supports; error bars with methodology, search ranges, compute, seeds
- **Related work**: organize methodologically, not paper-by-paper; cite generously
- **Limitations**: REQUIRED everywhere; honesty helps—reviewers must not penalize it
- **Checklist**: see [references/checklists.md](references/checklists.md)

Full per-step instructions and troubleshooting common issues: [references/paper-workflow.md](references/paper-workflow.md#workflow-1-writing-a-complete-paper-iterative).

---

## Writing Philosophy for Top ML Conferences

Distilled from Nanda, Farquhar, Karpathy, Gopen & Swan, Lipton, Steinhardt, and Perez—these separate accepted papers from rejected ones:

- **Time allocation (Nanda)**: spend equal time on the abstract, the introduction, the figures, and everything else combined—readers go title → abstract → intro → figures → maybe the rest.
- **Sentence-level clarity (Gopen & Swan, 7 principles)**: subject-verb proximity, stress position (emphasis at sentence end), topic position (context first), old-before-new, one unit one function, action in the verb, context before new information.
- **Micro-level (Perez)**: minimize pronouns, verbs early, unfold awkward apostrophes ("X's Y" → "the Y of X"), delete filler words.
- **Word choice (Lipton)**: be specific ("accuracy" not "performance"), eliminate hedging and intensifiers, avoid incremental vocabulary ("combine"/"modify" → "develop"/"propose").
- **Precision (Steinhardt)**: one term per concept, state assumptions formally, intuition alongside rigor.
- **What reviewers read**: abstract 100%, intro skimmed by 90%+, figures before methods, appendix rarely—front-load value.

Full principles with examples: [references/writing-guide.md](references/writing-guide.md). Source bibliography with links: [references/sources.md](references/sources.md).

---

## Conference Requirements Quick Reference

| Conference | Page Limit | Extra for Camera-Ready | Key Requirement |
|------------|------------|------------------------|-----------------|
| **NeurIPS 2025** | 9 pages | +0 | Mandatory checklist, lay summary for accepted |
| **ICML 2026** | 8 pages | +1 | Broader Impact Statement required |
| **ICLR 2026** | 9 pages | +1 | LLM disclosure required, reciprocal reviewing |
| **ACL 2025** | 8 pages (long) | varies | Limitations section mandatory |
| **AAAI 2026** | 7 pages | +1 | Strict style file adherence |
| **COLM 2025** | 9 pages | +1 | Focus on language models |

**Universal Requirements:**
- Double-blind review (anonymize submissions)
- References don't count toward page limit
- Appendices unlimited but reviewers not required to read
- LaTeX required for all venues

Per-venue checklists (NeurIPS 16-item, ICML, ICLR, ACL): [references/checklists.md](references/checklists.md).

---

## Workflow 4: Using LaTeX Templates Properly

```
Template Setup Checklist:
- [ ] Step 1: Copy entire template directory to new project
- [ ] Step 2: Verify template compiles as-is (before any changes)
- [ ] Step 3: Read the template's example content to understand structure
- [ ] Step 4: Replace example content section by section
- [ ] Step 5: Keep template comments/examples as reference until done
- [ ] Step 6: Clean up template artifacts only at the end
```

Copy the ENTIRE directory (`.sty`/`.bst` files are required), never edit style files, compile frequently. Templates for all six venues live in [templates/](templates/). Step detail, pitfalls table, and per-venue main/style file names: [references/latex-templates.md](references/latex-templates.md).

---

## Workflow 3: Conference Resubmission & Format Conversion

```
Format Conversion Checklist:
- [ ] Step 1: Identify source and target template differences
- [ ] Step 2: Create new project with target template
- [ ] Step 3: Copy content sections (not preamble)
- [ ] Step 4: Adjust page limits and content
- [ ] Step 5: Update conference-specific requirements
- [ ] Step 6: Verify compilation and formatting
```

**Never copy LaTeX preambles between templates**—start fresh from the target template and migrate content only. Address reviewer concerns in the new version, but never reference the previous submission (blind review). Page-limit deltas, venue-specific additions, and conversion pitfalls: [references/latex-templates.md](references/latex-templates.md#workflow-3-converting-between-conference-formats).

---

## Reviewer Evaluation Criteria

Reviewers assess four dimensions: **Quality** (technical soundness), **Clarity** (reproducible by experts), **Significance** (community impact), **Originality** (new insights—doesn't require a new method). NeurIPS scores on a 6-point scale from Strong Reject (1) to Strong Accept (6). Detailed criteria, scoring rubrics, common concerns, and rebuttal guidance: [references/reviewer-guidelines.md](references/reviewer-guidelines.md).

---

## Tables and Figures

- **Tables**: `booktabs` package; bold the best value, direction arrows (↑/↓), right-align numbers, consistent precision.
- **Figures**: vector graphics (PDF/EPS) for plots; colorblind-safe palettes (Okabe-Ito/Paul Tol); verify grayscale readability; no title inside the figure; self-contained captions.

LaTeX examples and full design rules: [references/writing-guide.md](references/writing-guide.md#table-design).

---

## References & Resources

| Document | Contents |
|----------|----------|
| [paper-workflow.md](references/paper-workflow.md) | Repo-to-paper workflow, proactivity tables, per-step writing guide, troubleshooting |
| [writing-guide.md](references/writing-guide.md) | Gopen & Swan 7 principles, Perez micro-tips, word choice, math/figure/table design |
| [citation-workflow.md](references/citation-workflow.md) | Citation APIs, Python code, Exa MCP, BibTeX management |
| [checklists.md](references/checklists.md) | NeurIPS 16-item, ICML, ICLR, ACL requirements |
| [reviewer-guidelines.md](references/reviewer-guidelines.md) | Evaluation criteria, scoring, rebuttals |
| [latex-templates.md](references/latex-templates.md) | Template setup, pitfalls, format conversion |
| [sources.md](references/sources.md) | Complete bibliography of all sources |

LaTeX templates in [templates/](templates/): ICML 2026, ICLR 2026, NeurIPS 2025, ACL/EMNLP, AAAI 2026, COLM 2025 (see [templates/README.md](templates/README.md) for compilation setup).
