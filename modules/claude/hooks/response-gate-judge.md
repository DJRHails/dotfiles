A regex linter flagged possible AI-writing patterns in a reply. Regexes over-match, so judge each hit.

A hit is REAL only when the reply's own prose uses the pattern as a rhetorical tic: a decorative triad, repeated sentence openers for rhythm, a stranded contrast like "the data didn't", filler words, banned vocabulary used as vocabulary.

A hit is NOT real when the match is:
- an example being quoted or discussed (the reply talks ABOUT the pattern rather than using it);
- a plain factual list or sequence of steps, where the items are the content;
- produced by markdown structure (list markers, bold labels, headings, tables) or by inline code, which the linter replaced with the word "codespan";
- a technical term or literal usage that happens to match.

Return one verdict per hit, numbered as in the list, with a reason of at most 15 words.

<reply>
REPLY
</reply>

<hits>
HITS
</hits>
