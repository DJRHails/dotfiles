---
name: import-papers
description: Process PDFs in research/dump/, extract metadata, generate bibtex entries, and move files to research/papers/. Use when importing research papers or managing a paper bibliography.
---

# Import Papers Skill

Process all PDFs in `research/dump/`, create bibtex entries, and move them to `research/papers/`.

## Instructions

For each PDF in `research/dump/`:

1. **Extract metadata** using `pdftotext` (first 30 lines only to avoid context overload):

   ```bash
   pdftotext "filename.pdf" - 2>&1 | head -30
   ```

2. **Identify**:

   - Title (full, not truncated)
   - Authors (first few primary authors)
   - Year (infer from content or use 2024/2025 for recent papers)
   - Venue (if clearly stated: conference/journal)

3. **Generate citation key** using format: `firstauthorYEARkeyword`

   - Use lowercase only
   - First author's last name
   - Year
   - One descriptive keyword from title
   - Examples: `ren2015faster`, `choi2024neuromamba`, `park2024processing`

4. **Create bibtex entry** matching existing format in `research/papers.bib`:

   ```bibtex
   @article{citationkey,
    author = {Author One and Author Two and Author Three},
    ejournal = {arXiv},
    title = {Full Paper Title},
    url = {https://arxiv.org/abs/XXXX.XXXXX},
    year = {YYYY}
   }
   ```

   Use `@inproceedings` if it's a conference paper (like NIPS, ICML, etc.) with:

   ```bibtex
   @inproceedings{citationkey,
    author = {Authors},
    booktitle = {Conference Name},
    title = {Title},
    year = {YYYY}
   }
   ```

5. **Append to papers.bib**:

   ```bash
   cat >> research/papers.bib << 'EOF'

   @article{citationkey,
    ...
   }
   EOF
   ```

6. **Move and rename** PDF to `research/papers/`:

   ```bash
   mv "research/dump/original.pdf" "research/papers/citationkey.pdf"
   ```

7. **Handle duplicates**: If two PDFs are identical (same title), keep only one.

8. **Verify** after processing all files:

   - List moved files: `ls -1 research/papers/ | tail -10`
   - Check dump is empty: `ls -1 research/dump/*.pdf 2>/dev/null || echo "empty"`

9. **Run bibify.py** to update the changelog and sync with Google Drive:
   ```bash
   ./bin/bibify.py
   ```

## Important Notes

- **DO NOT read entire PDFs** - only extract first 30 lines to save context
- Process all PDFs in a batch, not one at a time
- For generic filenames like `paper.pdf`, check content for actual title
- Follow existing bibtex format exactly (check `research/papers.bib` for examples)
- Use consistent naming: lowercase, no special characters in citation keys
