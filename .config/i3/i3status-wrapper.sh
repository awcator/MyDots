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


def get_laptop_position():
    """Determine if laptop is to the left or right of the external monitor."""
    try:
        result = subprocess.run(['xrandr', '--query'], capture_output=True, text=True, timeout=2)
        laptop_x = None
        external_x = None
        for line in result.stdout.splitlines():
            if line.startswith('eDP-1 connected'):
                # parse +X+Y from something like "1920x1200+0+0"
                parts = line.split()
                for p in parts:
                    if '+' in p and 'x' in p:
                        laptop_x = int(p.split('+')[1])
                        break
            elif ' connected' in line and not line.startswith('eDP-1'):
                parts = line.split()
                for p in parts:
                    if '+' in p and 'x' in p:
                        external_x = int(p.split('+')[1])
                        break
        if laptop_x is not None and external_x is not None:
            return "left" if laptop_x < external_x else "right"
    except Exception:
        pass
    return "left"


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
                "name": "laptop_ws",
                "instance": name,
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


def build_output(laptop_blocks, status_blocks):
    """Build output with laptop blocks positioned based on monitor layout."""
    if not laptop_blocks:
        return status_blocks
    label = {
        "full_text": " 💻 ",
        "color": "#89dceb",
        "separator": False,
        "separator_block_width": 3,
    }
    spacer = {"full_text": " ", "separator": False, "separator_block_width": 9}
    position = get_laptop_position()
    if position == "left":
        return [label] + laptop_blocks + [spacer] + status_blocks
    else:
        return status_blocks + [spacer, label] + laptop_blocks


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
    # Enable click events
    print('{"version":1,"click_events":true}', flush=True)

    # Second line is opening [
    opening = proc.stdout.readline().strip()
    print(opening, flush=True)

    import threading
    import os

    # Pipe to signal workspace changes
    ws_r, ws_w = os.pipe()

    def handle_clicks():
        # First line from i3bar is opening '['
        try:
            sys.stdin.readline()
        except:
            return
        for line in sys.stdin:
            line = line.strip().lstrip(',').strip()
            if not line or line == '[' or line == ']':
                continue
            try:
                event = json.loads(line)
                if event.get("name") == "laptop_ws":
                    ws_name = event.get("instance", "")
                    if ws_name:
                        subprocess.Popen(['i3-msg', f'workspace {ws_name}'],
                                         stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL)
                        # Signal a refresh
                        os.write(ws_w, b'1')
            except (json.JSONDecodeError, KeyError, ValueError):
                pass

    def watch_workspaces():
        """Subscribe to i3 workspace events and signal refresh."""
        ws_proc = subprocess.Popen(
            ['i3-msg', '-t', 'subscribe', '-m', '["workspace"]'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True
        )
        for line in ws_proc.stdout:
            os.write(ws_w, b'1')

    click_thread = threading.Thread(target=handle_clicks, daemon=True)
    click_thread.start()

    ws_thread = threading.Thread(target=watch_workspaces, daemon=True)
    ws_thread.start()

    import select

    last_status_blocks = []
    first_output = True

    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue

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
        last_status_blocks = blocks[:]

        # Prepend/append laptop workspace blocks based on monitor position
        laptop_blocks = get_laptop_workspace_blocks()
        output = build_output(laptop_blocks, blocks)

        if first_output:
            print(json.dumps(output), flush=True)
            first_output = False
        else:
            print("," + json.dumps(output), flush=True)

        # Drain any pending workspace events and re-render immediately
        while True:
            r, _, _ = select.select([ws_r], [], [], 0)
            if not r:
                break
            os.read(ws_r, 1024)

        # Wait for either next i3status line OR a workspace event
        while True:
            r, _, _ = select.select([proc.stdout, ws_r], [], [])
            if proc.stdout in r:
                break  # i3status has new data, outer loop handles it
            if ws_r in r:
                os.read(ws_r, 1024)
                # Re-render with fresh workspace state
                laptop_blocks = get_laptop_workspace_blocks()
                output = build_output(laptop_blocks, last_status_blocks)
                print("," + json.dumps(output), flush=True)


if __name__ == '__main__':
    main()
