# Paper Writing Workflows

Full workflow detail for drafting papers from research repositories: repo exploration,
proactivity guidance, the complete-paper checklist with per-step instructions, and
troubleshooting. Summarized in [SKILL.md](../SKILL.md).

---

## Contents

- [Core Philosophy: Collaborative Writing](#core-philosophy-collaborative-writing)
- [Workflow 0: Starting from a Research Repository](#workflow-0-starting-from-a-research-repository)
- [Balancing Proactivity and Collaboration](#balancing-proactivity-and-collaboration)
- [Workflow 1: Writing a Complete Paper (Iterative)](#workflow-1-writing-a-complete-paper-iterative)
- [Common Issues and Solutions](#common-issues-and-solutions)

---

## Core Philosophy: Collaborative Writing

**Paper writing is collaborative, but Claude should be proactive in delivering drafts.**

The typical workflow starts with a research repository containing code, results, and experimental artifacts. Claude's role is to:

1. **Understand the project** by exploring the repo, results, and existing documentation
2. **Deliver a complete first draft** when confident about the contribution
3. **Search literature** using web search and APIs to find relevant citations
4. **Refine through feedback cycles** when the scientist provides input
5. **Ask for clarification** only when genuinely uncertain about key decisions

**Key Principle**: Be proactive. If the repo and results are clear, deliver a full draft. Don't block waiting for feedback on every section—scientists are busy. Produce something concrete they can react to, then iterate based on their response.

**Always remember**: First drafts are starting points for discussion, not final outputs.

---

## Workflow 0: Starting from a Research Repository

When beginning paper writing, start by understanding the project:

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

**Step 1: Explore the Repository**

```bash
# Understand project structure
ls -la
find . -name "*.py" | head -20
find . -name "*.md" -o -name "*.txt" | xargs grep -l -i "result\|conclusion\|finding"
```

Look for:
- `README.md` - Project overview and claims
- `results/`, `outputs/`, `experiments/` - Key findings
- `configs/` - Experimental settings
- Existing `.bib` files or citation references
- Any draft documents or notes

**Step 2: Identify Existing Citations**

Check for papers already referenced in the codebase:

```bash
# Find existing citations
grep -r "arxiv\|doi\|cite" --include="*.md" --include="*.bib" --include="*.py"
find . -name "*.bib"
```

These are high-signal starting points for Related Work—the scientist has already deemed them relevant.

**Step 3: Clarify the Contribution**

Before writing, explicitly confirm with the scientist:

> "Based on my understanding of the repo, the main contribution appears to be [X].
> The key results show [Y]. Is this the framing you want for the paper,
> or should we emphasize different aspects?"

**Never assume the narrative—always verify with the human.**

**Step 4: Search for Additional Literature**

Use web search to find relevant papers:

```
Search queries to try:
- "[main technique] + [application domain]"
- "[baseline method] comparison"
- "[problem name] state-of-the-art"
- Author names from existing citations
```

Then verify and retrieve BibTeX using [citation-workflow.md](citation-workflow.md).

**Step 5: Deliver a First Draft**

**Be proactive—deliver a complete draft rather than asking permission for each section.**

If the repo provides clear results and the contribution is apparent:
1. Write the full first draft end-to-end
2. Present the complete draft for feedback
3. Iterate based on scientist's response

If genuinely uncertain about framing or major claims:
1. Draft what you can confidently
2. Flag specific uncertainties: "I framed X as the main contribution—let me know if you'd prefer to emphasize Y instead"
3. Continue with the draft rather than blocking

**Questions to include with the draft** (not before):
- "I emphasized X as the main contribution—adjust if needed"
- "I highlighted results A, B, C—let me know if others are more important"
- "Related work section includes [papers]—add any I missed"

---

## Balancing Proactivity and Collaboration

**Default: Be proactive. Deliver drafts, then iterate.**

| Confidence Level | Action |
|-----------------|--------|
| **High** (clear repo, obvious contribution) | Write full draft, deliver, iterate on feedback |
| **Medium** (some ambiguity) | Write draft with flagged uncertainties, continue |
| **Low** (major unknowns) | Ask 1-2 targeted questions, then draft |

**Draft first, ask with the draft** (not before):

| Section | Draft Autonomously | Flag With Draft |
|---------|-------------------|-----------------|
| Abstract | Yes | "Framed contribution as X—adjust if needed" |
| Introduction | Yes | "Emphasized problem Y—correct if wrong" |
| Methods | Yes | "Included details A, B, C—add missing pieces" |
| Experiments | Yes | "Highlighted results 1, 2, 3—reorder if needed" |
| Related Work | Yes | "Cited papers X, Y, Z—add any I missed" |

**Only block for input when:**
- Target venue is unclear (affects page limits, framing)
- Multiple contradictory framings seem equally valid
- Results seem incomplete or inconsistent
- Explicit request to review before continuing

**Don't block for:**
- Word choice decisions
- Section ordering
- Which specific results to show (make a choice, flag it)
- Citation completeness (draft with what you find, note gaps)

---

## Workflow 1: Writing a Complete Paper (Iterative)

Copy this checklist and track progress. **Each step involves drafting → feedback → revision:**

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

**Step 1: Define the One-Sentence Contribution**

**This step requires explicit confirmation from the scientist.**

Before writing anything, articulate and verify:
- What is the single thing your paper contributes?
- What was not obvious or present before your work?

> "I propose framing the contribution as: '[one sentence]'. Does this capture
> what you see as the main takeaway? Should we adjust the emphasis?"

**Step 2: Draft Figure 1**

Figure 1 deserves special attention—many readers skip directly to it.
- Convey core idea, approach, or most compelling result
- Use vector graphics (PDF/EPS for plots)
- Write captions that stand alone without main text
- Ensure readability in black-and-white (8% of men have color vision deficiency)

**Step 3: Write Abstract (5-Sentence Formula)**

From Sebastian Farquhar (DeepMind):

```
1. What you achieved: "We introduce...", "We prove...", "We demonstrate..."
2. Why this is hard and important
3. How you do it (with specialist keywords for discoverability)
4. What evidence you have
5. Your most remarkable number/result
```

**Delete** generic openings like "Large language models have achieved remarkable success..."

**Step 4: Write Introduction (1-1.5 pages max)**

Must include:
- 2-4 bullet contribution list (max 1-2 lines each in two-column format)
- Clear problem statement
- Brief approach overview
- Methods should start by page 2-3 maximum

**Step 5: Methods Section**

Enable reimplementation:
- Conceptual outline or pseudocode
- All hyperparameters listed
- Architectural details sufficient for reproduction
- Present final design decisions; ablations go in experiments

**Step 6: Experiments Section**

For each experiment, explicitly state:
- What claim it supports
- How it connects to main contribution
- Experimental setting (details in appendix)
- What to observe: "the blue line shows X, which demonstrates Y"

Requirements:
- Error bars with methodology (standard deviation vs standard error)
- Hyperparameter search ranges
- Compute infrastructure (GPU type, total hours)
- Seed-setting methods

**Step 7: Related Work**

Organize methodologically, not paper-by-paper:

**Good:** "One line of work uses Floogledoodle's assumption [refs] whereas we use Doobersnoddle's assumption because..."

**Bad:** "Snap et al. introduced X while Crackle et al. introduced Y."

Cite generously—reviewers likely authored relevant papers.

**Step 8: Limitations Section (REQUIRED)**

All major conferences require this. Counter-intuitively, honesty helps:
- Reviewers are instructed not to penalize honest limitation acknowledgment
- Pre-empt criticisms by identifying weaknesses first
- Explain why limitations don't undermine core claims

**Step 9: Paper Checklist**

NeurIPS, ICML, and ICLR all require paper checklists. See [checklists.md](checklists.md).

---

## Common Issues and Solutions

**Issue: Abstract too generic**

Delete first sentence if it could be prepended to any ML paper. Start with your specific contribution.

**Issue: Introduction exceeds 1.5 pages**

Split background into Related Work. Front-load contribution bullets. Methods should start by page 2-3.

**Issue: Experiments lack explicit claims**

Add sentence before each experiment: "This experiment tests whether [specific claim]..."

**Issue: Reviewers find paper hard to follow**

- Add explicit signposting: "In this section, we show X"
- Use consistent terminology throughout
- Include figure captions that stand alone

**Issue: Missing statistical significance**

Always include:
- Error bars (specify: std dev or std error)
- Number of runs
- Statistical tests if comparing methods
