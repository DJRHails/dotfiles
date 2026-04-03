---
name: interactive-cli
description: Control interactive CLI processes across multiple turns using tmux. Use when a command requires interactive input (y/n prompts, confirmations, menu selection, pdb, REPL, etc.) — any program that reads from stdin and cannot be run non-interactively. If a command fails with EOFError or hangs waiting for input, use this skill.
argument-hint: <command>
allowed-tools:
  - Bash(tmux *)
---

# Interactive CLI Process Control

Control interactive CLI processes across multiple bash tool calls using tmux sessions.

## Session Management

Use a named tmux session with a descriptive `cli_` prefix that captures the full context of what the session is doing:

```bash
# Start a detached session with a descriptive name
# Convention: cli_<what>_<where>_<why>
# Examples:
#   cli_ssh_saintmini01_for_running_saint_up
#   cli_pdb_debug_config_loading
#   cli_pyrepl_testing_math_functions
#   cli_ssh_thechurch_checking_docker_logs
tmux new-session -d -s cli_ssh_prod_deploying_v2 -x 120 -y 40 "<command>"

# Send input (use $'...\n' for newlines)
tmux send-keys -t cli_ssh_prod_deploying_v2 $'<input>\n'

# Send multiple commands
tmux send-keys -t cli_ssh_prod_deploying_v2 $'cmd1\ncmd2\n'

# Read current terminal output (print to stdout)
tmux capture-pane -t cli_ssh_prod_deploying_v2 -p

# Read with scrollback history (start from line -100)
tmux capture-pane -t cli_ssh_prod_deploying_v2 -p -S -100

# Stop the session
tmux kill-session -t cli_ssh_prod_deploying_v2
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
tmux new-session -d -s cli_pdb_debug_config_loading -x 120 -y 40 "python3 -m pdb script.py"
sleep 2 && tmux capture-pane -t cli_pdb_debug_config_loading -p

# Step through code and print a variable
tmux send-keys -t cli_pdb_debug_config_loading $'n\n'
sleep 0.5 && tmux capture-pane -t cli_pdb_debug_config_loading -p
tmux send-keys -t cli_pdb_debug_config_loading $'print(my_var)\n'
sleep 0.5 && tmux capture-pane -t cli_pdb_debug_config_loading -p

# Set breakpoint and continue
tmux send-keys -t cli_pdb_debug_config_loading $'b 42\nc\n'
sleep 1 && tmux capture-pane -t cli_pdb_debug_config_loading -p

# Quit
tmux send-keys -t cli_pdb_debug_config_loading $'q\n' && tmux kill-session -t cli_pdb_debug_config_loading
```

### Python REPL

```bash
tmux new-session -d -s cli_pyrepl_testing_math_functions -x 120 -y 40 "python3"
sleep 1 && tmux send-keys -t cli_pyrepl_testing_math_functions $'import math\nmath.pi\n'
sleep 0.5 && tmux capture-pane -t cli_pyrepl_testing_math_functions -p
```

### Node.js REPL

```bash
tmux new-session -d -s cli_node_repl_array_transforms -x 120 -y 40 "node"
sleep 1 && tmux send-keys -t cli_node_repl_array_transforms $'const x = [1,2,3]\nx.map(n => n * 2)\n'
sleep 0.5 && tmux capture-pane -t cli_node_repl_array_transforms -p
```

## Async Code & Playwright Debugging

To debug async code (e.g., Playwright scripts) interactively, use `nest_asyncio` to enable nested event loops.

Install if needed: `pip install nest_asyncio`

### Interactive Async Debugging

At any pdb breakpoint where async objects (like Playwright's `page`) are in scope:

```bash
# Start pdb on an async Playwright script
tmux new-session -d -s cli_pdb_playwright_animation_bug -x 120 -y 40 "python3 -m pdb my_playwright_script.py"
sleep 2

# Set breakpoint where page exists and continue
tmux send-keys -t cli_pdb_playwright_animation_bug $'b 50\nc\n'
sleep 10  # Wait for browser to launch

# At the breakpoint, enable nest_asyncio for interactive async:
tmux send-keys -t cli_pdb_playwright_animation_bug $'import nest_asyncio; nest_asyncio.apply(); import asyncio\n'

# Run async code interactively:
tmux send-keys -t cli_pdb_playwright_animation_bug $'asyncio.run(page.evaluate("() => document.title"))\n'
sleep 1 && tmux capture-pane -t cli_pdb_playwright_animation_bug -p
# Output: 'My Page Title'

# Query DOM, call functions, interact with page:
tmux send-keys -t cli_pdb_playwright_animation_bug $'asyncio.run(page.evaluate("() => document.querySelectorAll(\'button\').length"))\n'
tmux send-keys -t cli_pdb_playwright_animation_bug $'asyncio.run(page.click("button"))\n'
tmux send-keys -t cli_pdb_playwright_animation_bug $'asyncio.run(page.screenshot(path="debug.png"))\n'
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
tmux send-keys -t cli_pyrepl_testing_math_functions "$(cat <<'EOF'
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
- For long-running processes, check status with `tmux has-session -t cli_ssh_prod_deploying_v2`
- Multiple sessions: use different descriptive names for each context

## Handling User Arguments

If the user provides a command as `$ARGUMENTS`, derive a descriptive session name from the command context:

```bash
tmux new-session -d -s cli_<descriptive_name_from_context> -x 120 -y 40 "$ARGUMENTS"
```
