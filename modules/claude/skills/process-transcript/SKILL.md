---
name: process-transcript
description: Transform video/podcast transcripts into structured, dense notes following KB style guide. Extracts key concepts, quotes, actionable advice, and frameworks.
---

# Process Transcript Skill

Transform verbose video/podcast transcripts into comprehensive, structured notes that follow the knowledge base style guide principles: density over verbosity, practical over theoretical, direct communication.

## Instructions

### 1. Read the Transcript

For large transcripts (>25,000 tokens), use Task tool with general-purpose agent:

```
Use Task tool:
- subagent_type: "general-purpose"
- description: "Extract key insights from transcript"
- prompt: "Read the transcript at [PATH] and extract:
  1. Main themes and concepts discussed
  2. Specific advice, rules, or frameworks
  3. Key examples and anecdotes
  4. Practical tips for different scenarios
  5. Important quotes or memorable phrases
  6. Any mental models or frameworks mentioned

  Structure findings with clear sections and bullet points. Focus on actionable advice and concrete examples."
```

### 2. Extract Compelling Quotes

Run second agent task focused on quotable moments:

```
Use Task tool:
- subagent_type: "general-purpose"
- description: "Extract compelling quotes from transcript"
- prompt: "Read the transcript at [PATH] and extract the most compelling, memorable, and quotable statements. Look for:
  1. Funny or witty observations
  2. Strong opinions stated colorfully
  3. Memorable phrases or turns of phrase
  4. Contrarian or surprising takes
  5. Practical wisdom stated memorably
  6. Self-aware or self-deprecating moments

  Extract exact quotes (verbatim) with context. Organize by theme."
```

### 3. Structure the Notes

Replace the existing summary with structured sections following this pattern:

**Opening sections** (choose based on content):
- Core Philosophy / Main Thesis
- Key Concepts
- Overview

**Body sections** (organize by topic):
- Group related advice together
- Use descriptive H2 headers (`##`)
- Subsections with H3 (`###`) where needed

**Common section types**:
- Mental models and frameworks
- Practical advice by scenario
- Examples and case studies
- Personal context about speaker

### 4. Apply KB Style Guide Patterns

**Density**:
- Heavy use of bullet points for lists and hierarchical info
- Sentence fragments are fine
- No fluff or unnecessary elaboration

**Quotes integration**:
- Lead sections with compelling quotes using blockquotes (`>`)
- Inline quotes in bullet points for supporting wisdom
- Always use exact verbatim quotes

**Structure elements**:
```markdown
## Section Title

> "Compelling quote that captures the essence"

Brief context (1-2 sentences if needed)

- Key point with supporting detail
- Another point
- "Inline quote for memorable wisdom"

**Sub-concept with bolding**:
- Nested details
- Action items
```

**Formatting patterns**:
- Bold (`**text**`) for emphasis on key terms, sub-concepts
- Code blocks for examples, commands, specific patterns
- Lists over paragraphs
- Nested bullets for hierarchy

### 5. Content Organization Principles

**Lead with philosophy**: Core concepts and mental models upfront

**Organize by context**: Group advice by scenario (meetings, emails, conversations, etc.) not chronologically

**Integrate quotes organically**:
- Use blockquotes (`>`) for section-leading quotes
- Inline quotes within bullets for supporting points
- Don't create separate "quotes section"

**Attribution**: Include personal context about speaker at end:
- Who they are
- Why they're credible on topic
- Relevant self-aware moments or hypocrisy they acknowledge

### 6. Quality Checks

Before finalizing, verify:

- [ ] No long paragraphs (break into bullets)
- [ ] Quotes are exact/verbatim
- [ ] Headers are descriptive and meaningful
- [ ] Actionable advice is clear and specific
- [ ] Examples and anecdotes are included
- [ ] Mental models/frameworks are highlighted
- [ ] Follows "density over verbosity" principle
- [ ] Personal/self-aware moments included (adds personality)

## Examples of Good Patterns

**Section with leading quote**:
```markdown
## Core Philosophy

> "Etiquette is a skill for how to show up in a room with a low heart rate."

**The low heart rate framework**: Etiquette builds trust and projects genuine confidence.

- Not your "one shot" - project calm abundance
- Good etiquette is invisible infrastructure
- "You shouldn't notice it - it should get out of the way"
```

**Practical advice section**:
```markdown
## Email Communication

**Best practices**:
- Don't use emojis in business context (implies familiarity)
- "ChatGPT loves emojis" - avoid the tell
- Proofread everything
- Get to the point quickly
```

**Personal context**:
```markdown
## Personal Context

Sam Lessin: Partner at Slow Ventures, former VP of Product at Facebook.

Self-aware hypocrisy: "I love my children, but they have terrible manners... I'm like, 'Wow, you guys eat like animals.'"
```

## Important Notes

- **Use agents for large files**: Don't try to read 30k+ token transcripts directly
- **Run two passes**: First for content extraction, second for quotes
- **Preserve speaker voice**: Include witty/personality moments, not just dry facts
- **Action-oriented**: Focus on "what to do" not just "what was said"
- **Dense, not verbose**: If it can be a bullet, make it a bullet
- **Quote quality over quantity**: Use memorable, impactful quotes
- **No time estimates**: Don't mention how long content is unless relevant to the notes
