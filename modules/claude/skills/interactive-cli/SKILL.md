---
name: interactive-cli
description: Control interactive CLI processes (pdb, repl, etc.) across multiple turns using tmux. Use when debugging with pdb, running a REPL, or any interactive terminal program.
argument-hint: <command>
allowed-tools:
  - Bash(tmux *)
---

# Interactive CLI Process Control

Control interactive CLI processes across multiple bash tool calls using tmux sessions.

## Session Management

Use a named tmux session `proc` for the interactive process:

```bash
# Start a detached session named "proc" with 120x40 terminal
tmux new-session -d -s proc -x 120 -y 40 "<command>"

# Send input (use $'...\n' for newlines)
tmux send-keys -t proc $'<input>\n'

# Send multiple commands
tmux send-keys -t proc $'cmd1\ncmd2\n'

# Read current terminal output (print to stdout)
tmux capture-pane -t proc -p

# Read with scrollback history (start from line -100)
tmux capture-pane -t proc -p -S -100

# Stop the session
tmux kill-session -t proc
```

## Workflow

1. **Start**: Launch the interactive process in a detached tmux session
2. **Interact**: Send commands with `send-keys`, read output with `capture-pane`
3. **Iterate**: Continue sending commands and reading output as needed
4. **Cleanup**: Kill the session when done

## Examples

### Python Debugger (pdb)

```bash
# Start pdb
tmux new-session -d -s proc -x 120 -y 40 "python3 -m pdb script.py"
sleep 2 && tmux capture-pane -t proc -p

# Step through code and print a variable
tmux send-keys -t proc $'n\n'
sleep 0.5 && tmux capture-pane -t proc -p
tmux send-keys -t proc $'print(my_var)\n'
sleep 0.5 && tmux capture-pane -t proc -p

# Set breakpoint and continue
tmux send-keys -t proc $'b 42\nc\n'
sleep 1 && tmux capture-pane -t proc -p

# Quit
tmux send-keys -t proc $'q\n' && tmux kill-session -t proc
```

### Python REPL

```bash
tmux new-session -d -s proc -x 120 -y 40 "python3"
sleep 1 && tmux send-keys -t proc $'import math\nmath.pi\n'
sleep 0.5 && tmux capture-pane -t proc -p
```

### Node.js REPL

```bash
tmux new-session -d -s proc -x 120 -y 40 "node"
sleep 1 && tmux send-keys -t proc $'const x = [1,2,3]\nx.map(n => n * 2)\n'
sleep 0.5 && tmux capture-pane -t proc -p
```

## Async Code & Playwright Debugging

To debug async code (e.g., Playwright scripts) interactively, use `nest_asyncio` to enable nested event loops.

Install if needed: `pip install nest_asyncio`

### Interactive Async Debugging

At any pdb breakpoint where async objects (like Playwright's `page`) are in scope:

```bash
# Start pdb on an async Playwright script
tmux new-session -d -s proc -x 120 -y 40 "python3 -m pdb my_playwright_script.py"
sleep 2

# Set breakpoint where page exists and continue
tmux send-keys -t proc $'b 50\nc\n'
sleep 10  # Wait for browser to launch

# At the breakpoint, enable nest_asyncio for interactive async:
tmux send-keys -t proc $'import nest_asyncio; nest_asyncio.apply(); import asyncio\n'

# Run async code interactively:
tmux send-keys -t proc $'asyncio.run(page.evaluate("() => document.title"))\n'
sleep 1 && tmux capture-pane -t proc -p
# Output: 'My Page Title'

# Query DOM, call functions, interact with page:
tmux send-keys -t proc $'asyncio.run(page.evaluate("() => document.querySelectorAll(\'button\').length"))\n'
tmux send-keys -t proc $'asyncio.run(page.click("button"))\n'
tmux send-keys -t proc $'asyncio.run(page.screenshot(path="debug.png"))\n'
```

### Key Points

- `nest_asyncio.apply()` patches the event loop to allow `asyncio.run()` inside an already-running loop
- Use `asyncio.run(coroutine)` to execute any async code at pdb prompts
- Works with Playwright's `page.evaluate()`, `page.click()`, `page.screenshot()`, etc.
- Can call your own async functions to inspect state
- Useful for debugging animation waits, DOM state, network timing issues

### Example: Debugging Animation State

```python
# At breakpoint, inspect SVG animation state:
(Pdb) asyncio.run(page.evaluate('() => document.querySelectorAll("circle").length'))
11
(Pdb) asyncio.run(page.click('circle'))
(Pdb) import time; time.sleep(2)  # Wait for animation
(Pdb) asyncio.run(page.evaluate('() => document.querySelectorAll("circle").length'))
21  # State changed after click
```

## Sending Longer Scripts

Always pass multiline commands with HEREDOC:

```bash
tmux send-keys -t proc "$(cat <<'EOF'
def greet(name):
    return f"Hello, {name}!"

greet("world")
EOF
)"
```

HEREDOC preserves formatting and avoids escaping issues. Use `<<'EOF'` (quoted) to prevent variable expansion.

## Tips

- Always add `sleep` after starting or sending commands to allow output to render
- Use `capture-pane -p -S -100` to get scrollback history if output scrolled off
- Chain commands with `&&` when they don't need intermediate reads
- For long-running processes, check status with `tmux has-session -t proc`
- Multiple sessions: use different names (e.g., `-s pdb`, `-s repl`)

## Handling User Arguments

If the user provides a command as `$ARGUMENTS`:

```bash
tmux new-session -d -s proc -x 120 -y 40 "$ARGUMENTS"
```
