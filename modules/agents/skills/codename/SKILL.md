---
name: codename
description: "Suggest a codename for a project. Fetches naming philosophy from hails.info/writing/codenames, studies the project context, then proposes names that are suggestive (not descriptive), memorable, and free of pop culture references."
---

# Codename Generator

Suggest a codename for a project by applying a principled naming philosophy.

## Process

1. **Fetch the naming guide** — use WebFetch to read `https://hails.info/writing/codenames` and extract the full naming philosophy. This is the source of truth for what makes a good codename.

2. **Understand the project** — read key files (README, package.json, CLAUDE.md, main source files) to understand:
   - What the project does
   - Core abstractions and metaphors
   - Target audience
   - Key technical properties (e.g. durability, speed, isolation, orchestration)

3. **Apply the naming rules** from hails.info:
   - **Be suggestive, not descriptive** — prefer `gatekeeper` over `identity-service`
   - **Cute names aid recall** — and subtly imply fungibility
   - **No pop culture references** — if it needs explanation, the suggestive benefit vanishes
   - **Separate marketing names from codenames** — codenames serve internal technical purposes
   - **Use the trademark "suggestive" test** — like Coppertone, Greyhound, Tesla: infer meaning without being directly descriptive

4. **If the user provided a theme or constraint**, weight suggestions toward it (e.g. "something referencing durability" or "nautical theme").

5. **Generate 5-7 candidates** — for each, provide:
   - The name
   - A one-line connection to the project (why it's suggestive)
   - CLI ergonomics check: is it short, easy to type, unambiguous to spell?
   - Conflicts check: is it already a well-known dev tool or product?

6. **Apply the tattoo test** to each candidate: if the project's scope evolves (gains features, handles new domains, changes direction), does the name still fit? A good codename suggests a *quality* or *metaphor*, not a specific implementation — so it survives scope changes. If the project later does something completely different and the name still works, it passes.

7. **Recommend your top pick** with a brief justification covering:
   - How it passes the suggestive test
   - How it passes the tattoo test (resilient to scope changes)
   - Why it fits this specific project
   - How it works in practice (`<name> deploy`, `<name> init`, etc.)

## Key Principles

- One-syllable or two-syllable names are strongly preferred
- The name should be greppable and unique enough to not collide with common terms
- Avoid names already taken by popular dev tools (check your knowledge)
- A good codename makes people curious, not confused
- When in doubt, simpler is better
