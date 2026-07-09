#!/usr/bin/env python3
"""
Wrapper around i3status that:
1. Prepends laptop (eDP-1) workspace indicators on external monitor bar
2. Colorizes each i3status block with Catppuccin Mocha accents
"""

import sys
import json
import subprocess

# Catppuccin Mocha workspace colors
WS_COLORS = {
    "focused":  {"background": "#b4befe", "color": "#11111b", "border": "#b4befe"},
    "visible":  {"background": "#313244", "color": "#cdd6f4", "border": "#6c7086"},
    "urgent":   {"background": "#fab387", "color": "#11111b", "border": "#fab387"},
    "inactive": {"background": "#1e1e2e", "color": "#7f849c", "border": "#1e1e2e"},
}

# Per-module colors (Catppuccin Mocha palette)
BLOCK_COLORS = {
    "wireless":        "#89dceb",  # sky
    "ethernet":        "#89b4fa",  # blue
    "battery":         "#a6e3a1",  # green
    "cpu_usage":       "#cba6f7",  # mauve
    "cpu_temperature": "#fab387",  # peach
    "disk_info":       "#74c7ec",  # sapphire
    "memory":          "#f5c2e7",  # pink
    "tztime":          "#f5e0dc",  # rosewater
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
                style = WS_COLORS["urgent"]
            elif w.get('focused'):
                style = WS_COLORS["focused"]
            elif w.get('visible'):
                style = WS_COLORS["visible"]
            else:
                style = WS_COLORS["inactive"]

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


def colorize_blocks(blocks):
    """Apply Catppuccin accent colors to each i3status block by module name."""
    for block in blocks:
        name = block.get("name", "")
        if name in BLOCK_COLORS:
            block["color"] = BLOCK_COLORS[name]
        # Hide empty blocks (e.g. ethernet when down)
        if not block.get("full_text", "").strip():
            block["full_text"] = ""
    # Filter out empty blocks
    return [b for b in blocks if b.get("full_text", "").strip()]


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

        # Colorize i3status blocks
        blocks = colorize_blocks(blocks)

        # Prepend laptop workspace blocks
        laptop_blocks = get_laptop_workspace_blocks()
        if laptop_blocks:
            label = {
                "full_text": " 💻 ",
                "color": "#89dceb",
                "separator": False,
                "separator_block_width": 3,
            }
            blocks = [label] + laptop_blocks + [{"full_text": " ", "separator": False, "separator_block_width": 9}] + blocks

        print(prefix + json.dumps(blocks), flush=True)


if __name__ == '__main__':
    main()
