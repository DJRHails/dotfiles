# Upstream parity fixtures

Both files are derived from Simon Willison's LLM cliché highlighter
(<https://github.com/simonw/tools>, `llm-cliche-highlighter.html`, Apache
License 2.0), captured 2026-08-30. They exist so `cliche-check.py` can be
checked against upstream behaviour rather than against our own assumptions.

- `upstream_pattern_cases.json` — the tool's own `patternCases` array, 182
  entries of `[pattern_id, sample, expected_match_count, expected_badges]`,
  covering all 38 pattern ids. Checks the **finders** in isolation.
- `upstream_pipeline_golden.json` — the output of running upstream's
  `collectMatches` → `buildRegions` → `buildWindows` over its own built-in
  EXAMPLE text, plus that text. Checks the **pipeline**: overlap suppression,
  sentence expansion, and context windows. A finder-only corpus cannot catch a
  missing suppression step, which is exactly the bug this fixture found.

## Refreshing

```bash
curl -sL https://raw.githubusercontent.com/simonw/tools/main/llm-cliche-highlighter.html -o /tmp/lch.html
```

Then re-extract the `patternCases` array, and re-run the DOM-free core (roughly
the region from `CHAIN_BODY` down to the end of `sentenceBounds`, plus
`EXAMPLE`) under node to regenerate the golden dump. If a refresh changes
either file, the diff *is* the upstream changelog — read it before updating
`UPSTREAM_IDS` in `../test_cliche_check.py`.
