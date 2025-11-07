#!/usr/bin/env python3
"""
Execute code blocks from markdown files.
"""

import sys
import re
from pathlib import Path


def extract_code_blocks(markdown_content):
    """Extract all code blocks from markdown content."""
    # Match fenced code blocks with optional language specifier
    pattern = r'```(\w+)?\n(.*?)```'
    matches = re.findall(pattern, markdown_content, re.DOTALL)
    return [(lang or 'text', code) for lang, code in matches]


def execute_python_blocks(markdown_file):
    """Execute all Python code blocks in a markdown file."""
    content = Path(markdown_file).read_text()
    blocks = extract_code_blocks(content)

    python_blocks = [code for lang, code in blocks if lang in ('py', 'python')]

    if not python_blocks:
        print(f"No Python code blocks found in {markdown_file}", file=sys.stderr)
        return 1

    # Shared namespace across all blocks
    namespace = {'__name__': '__main__'}

    # Execute all Python blocks in sequence
    for i, code in enumerate(python_blocks):
        print(f"--- Executing block {i+1}/{len(python_blocks)} ---")
        try:
            # Try to evaluate as expression first, to auto-print like REPL
            lines = code.strip().split('\n')
            if lines:
                # Separate the last line to try as expression
                last_line = lines[-1]
                preceding = '\n'.join(lines[:-1])

                # Execute all but last line
                if preceding:
                    exec(preceding, namespace)

                # Try last line as expression
                try:
                    result = eval(last_line, namespace)
                    if result is not None:
                        print(result)
                except SyntaxError:
                    # Not an expression, execute as statement
                    exec(last_line, namespace)
        except Exception as e:
            print(f"Error in block {i+1}: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            return 1

    return 0


def main():
    if len(sys.argv) != 2:
        print("Usage: execblock <markdown-file>", file=sys.stderr)
        return 1

    markdown_file = sys.argv[1]

    if not Path(markdown_file).exists():
        print(f"File not found: {markdown_file}", file=sys.stderr)
        return 1

    return execute_python_blocks(markdown_file)


if __name__ == '__main__':
    sys.exit(main())
