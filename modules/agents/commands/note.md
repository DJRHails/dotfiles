---
description: Pin a note to the status line; no text clears it. Handled in the shell, no model turn.
---

`/note` is handled by `modules/claude/hooks/note.sh`, a UserPromptSubmit hook that
reads the raw prompt and blocks it, so this body is never meant to reach the model.
The file exists so `/note` shows up in the slash-command menu.

If you are reading this, the hook did not run. Tell the user that `/note` is not
wired into this profile's settings.json under hooks.UserPromptSubmit, and do
nothing else.
