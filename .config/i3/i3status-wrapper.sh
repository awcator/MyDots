#!/usr/bin/env python3
"""
Wrapper around i3status that prepends laptop (eDP-1) workspace indicators
to the i3bar JSON output on the external monitor bar.
Shows which workspaces on the laptop have windows open.
"""

import sys
import json
import subprocess

def get_laptop_workspaces():
    """Get workspace info for eDP-1 output."""
    try:
        result = subprocess.run(
            ['i3-msg', '-t', 'get_workspaces'],
            capture_output=True, text=True, timeout=2
        )
        workspaces = json.loads(result.stdout)
        laptop_ws = [w for w in workspaces if w.get('output') == 'eDP-1']
        if not laptop_ws:
            return None

        parts = []
        for w in laptop_ws:
            num = w.get('num', '?')
            name = w['name'].split(': ', 1)[-1] if ': ' in w['name'] else w['name']
            if w.get('urgent'):
                parts.append(f"!{num}:{name}")
            elif w.get('focused'):
                parts.append(f"*{num}:{name}")
            else:
                parts.append(f"{num}:{name}")

        return "eDP[" + " ".join(parts) + "]"
    except Exception:
        return None


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

        # Prepend laptop workspace info
        laptop_info = get_laptop_workspaces()
        if laptop_info:
            laptop_block = {
                "full_text": laptop_info,
                "color": "#89dceb",
                "separator": True,
                "separator_block_width": 15
            }
            blocks.insert(0, laptop_block)

        print(prefix + json.dumps(blocks), flush=True)


if __name__ == '__main__':
    main()
