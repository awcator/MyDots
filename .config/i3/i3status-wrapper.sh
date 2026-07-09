#!/usr/bin/env python3
"""
Wrapper around i3status that prepends laptop (eDP-1) workspace indicators
to the i3bar JSON output on the external monitor bar.
Shows which workspaces on the laptop have windows open.
"""

import sys
import json
import subprocess

# Catppuccin Mocha colors (matching i3bar workspace colors)
COLORS = {
    "focused":  {"background": "#b4befe", "color": "#11111b", "border": "#b4befe"},  # lavender
    "visible":  {"background": "#313244", "color": "#cdd6f4", "border": "#6c7086"},  # surface0
    "urgent":   {"background": "#fab387", "color": "#11111b", "border": "#fab387"},  # peach
    "inactive": {"background": "#1e1e2e", "color": "#7f849c", "border": "#1e1e2e"},  # base
}

def get_laptop_workspace_blocks():
    """Get workspace blocks for eDP-1 output with colored backgrounds."""
    try:
        result = subprocess.run(
            ['i3-msg', '-t', 'get_workspaces'],
            capture_output=True, text=True, timeout=2
        )
        workspaces = json.loads(result.stdout)
        laptop_ws = [w for w in workspaces if w.get('output') == 'eDP-1']
        if not laptop_ws:
            return []

        blocks = []
        for w in laptop_ws:
            name = w['name']
            if w.get('urgent'):
                style = COLORS["urgent"]
            elif w.get('focused'):
                style = COLORS["focused"]
            elif w.get('visible'):
                style = COLORS["visible"]
            else:
                style = COLORS["inactive"]

            blocks.append({
                "full_text": f" {name} ",
                "color": style["color"],
                "background": style["background"],
                "border": style["border"],
                "separator": False,
                "separator_block_width": 3,
                "min_width": 30,
            })

        return blocks
    except Exception:
        return []


def main():
    proc = subprocess.Popen(
        ['i3status'],
        stdout=subprocess.PIPE,
        text=True
    )

    # i3bar protocol: first line is {"version":1}
    header = proc.stdout.readline().strip()
    print(header, flush=True)

    # Second line is opening [
    opening = proc.stdout.readline().strip()
    print(opening, flush=True)

    first = True
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue

        # Lines are either "[...]" (first data) or ",[...]" (subsequent)
        prefix = ""
        if line.startswith(','):
            prefix = ","
            line = line[1:]

        try:
            blocks = json.loads(line)
        except json.JSONDecodeError:
            print(prefix + line, flush=True)
            continue

        # Prepend laptop workspace blocks
        laptop_blocks = get_laptop_workspace_blocks()
        if laptop_blocks:
            # Add a label block first
            label = {
                "full_text": "💻",
                "color": "#89dceb",
                "separator": False,
                "separator_block_width": 3,
            }
            blocks = [label] + laptop_blocks + blocks

        print(prefix + json.dumps(blocks), flush=True)


if __name__ == '__main__':
    main()
