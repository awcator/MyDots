#!/usr/bin/env python3
"""
Generic Interactive Terminal Picker
Reads TSV from stdin (or file): ID [TAB] Title [TAB] Status
Returns the selected ID on stdout.
"""

import os
import re
import select
import sys
import termios
import tty
import unicodedata

RESET = "\033[0m"
BOLD  = "\033[1m"
DIM   = "\033[2m"

def fg(r, g, b): return f"\033[38;2;{r};{g};{b}m"
def bg(r, g, b): return f"\033[48;2;{r};{g};{b}m"

C_HEADER = fg(100, 180, 255)
C_BORDER = fg(60, 80, 110)
C_WARN   = fg(255, 200, 60)
C_SEL_BG = bg(30, 50, 80)
C_SEL_FG = fg(220, 240, 255) + BOLD
C_ID     = fg(210, 225, 255)

MIN_CELL_WIDTH = 42
MAX_COLUMNS = 6

def strip_ansi(s):
    return re.sub(r'\033\[[^m]*m', '', s)

def vis_len(s):
    return sum(0 if unicodedata.combining(ch) else
               2 if unicodedata.east_asian_width(ch) in "WF" else 1
               for ch in strip_ansi(s))

def fit_text(text, width):
    text_width = vis_len(text)
    if text_width <= width:
        return text + " " * (width - text_width)
    result = ""
    for ch in text:
        if vis_len(result + ch) > width - 1:
            break
        result += ch
    return result + "…" + " " * (width - vis_len(result) - 1)

def read_tsv():
    items = []
    text = sys.stdin.read()
    for line in text.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        mid = parts[0]
        title = parts[1] if len(parts) > 1 else ""
        status = parts[2] if len(parts) > 2 else ""
        items.append((mid, title, status))
    return items

try:
    tty_out = open("/dev/tty", "w")
    tty_in  = open("/dev/tty", "r")
except Exception:
    tty_out = sys.stderr
    tty_in  = sys.stdin

def write_tty(msg):
    tty_out.write(msg)
    tty_out.flush()

def get_termsize():
    try:
        sz = os.get_terminal_size(tty_out.fileno())
        return max(sz.columns - 1, 40), max(sz.lines, 10)
    except Exception:
        return 100, 30

def format_cell(item, index, width, selected):
    mid, title, status = item
    label = f" {index + 1:>3}) {mid}"
    if title and title != mid:
        label += f" · {title}"
    if status:
        label += f"  {status}"
    color = C_SEL_BG + C_SEL_FG if selected else C_ID
    return color + fit_text(label, width) + RESET

def render_ui(items, selected_idx, filter_text, heading_title):
    tw, th = get_termsize()

    if filter_text:
        visible = [m for m in items if filter_text.lower() in m[0].lower() or filter_text.lower() in m[1].lower()]
    else:
        visible = items

    total_vis = len(visible)
    selected_idx = max(0, min(selected_idx, total_vis - 1))
    columns = min(MAX_COLUMNS, max(1, (tw - 2) // MIN_CELL_WIDTH))
    max_rows = max(1, th - 8)
    page_size = max_rows * columns
    page_start = (selected_idx // page_size) * page_size
    page_end = min(page_start + page_size, total_vis)
    cell_space = tw - 2 - (columns - 1)
    widths = [cell_space // columns + (col < cell_space % columns)
              for col in range(columns)]

    lines = []
    hdr = C_HEADER + BOLD + f"╔══ {heading_title} "
    hdr += "═" * max(0, tw - vis_len(strip_ansi(hdr)) - 1) + "╗" + RESET
    lines.append(hdr)

    search = f"  Search: {filter_text}▌  (type to filter)"
    lines.append(C_BORDER + "║" + RESET + C_WARN + fit_text(search, tw - 2) + RESET + C_BORDER + "║" + RESET)
    lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)

    for row in range((page_end - page_start + columns - 1) // columns):
        cells = []
        for col, width in enumerate(widths):
            index = page_start + row * columns + col
            cells.append(format_cell(visible[index], index, width, index == selected_idx)
                         if index < page_end else " " * width)
        separator = C_BORDER + "│" + RESET
        lines.append(C_BORDER + "║" + RESET + separator.join(cells) + C_BORDER + "║" + RESET)

    if total_vis == 0:
        msg = f"  No matches found for '{filter_text}'"
        lines.append(C_BORDER + "║" + RESET + C_WARN + fit_text(msg, tw - 2) + RESET + C_BORDER + "║" + RESET)

    if total_vis > page_size:
        hint = f"  {page_start + 1}–{page_end} of {total_vis}  ·  PgUp/PgDn: page"
        lines.append(C_BORDER + "║" + RESET + DIM + fit_text(hint, tw - 2) + RESET + C_BORDER + "║" + RESET)

    lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)
    keys_help = "  ↑/↓/←/→: move   PgUp/PgDn: page   Enter: pick   ESC: clear/quit"
    lines.append(C_BORDER + "║" + RESET + DIM + fit_text(keys_help, tw - 2) + RESET + C_BORDER + "║" + RESET)
    lines.append(C_BORDER + "╚" + "═" * (tw - 2) + "╝" + RESET)

    write_tty("\033[H\033[2J" + "\n".join(lines) + "\n")
    return visible, selected_idx, columns, page_size

def read_char(fd):
    data = os.read(fd, 1)
    if not data:
        return ""
    first = data[0]
    if first & 0xE0 == 0xC0:
        extra = 1
    elif first & 0xF0 == 0xE0:
        extra = 2
    elif first & 0xF8 == 0xF0:
        extra = 3
    else:
        extra = 0
    for _ in range(extra):
        data += os.read(fd, 1)
    return data.decode("utf-8", errors="ignore")

def read_key():
    fd = tty_in.fileno()
    if not os.isatty(fd):
        return tty_in.read(1)
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = read_char(fd)
        if ch == "\033":
            if not select.select([fd], [], [], 0.05)[0]:
                return ch
            ch2 = read_char(fd)
            if ch2 in ("[", "O"):
                ch3 = read_char(fd)
                if ch3 == "A": return "UP"
                if ch3 == "B": return "DOWN"
                if ch3 == "C": return "RIGHT"
                if ch3 == "D": return "LEFT"
                if ch3 == "5": os.read(fd, 1); return "PGUP"
                if ch3 == "6": os.read(fd, 1); return "PGDN"
                return ch3
            return ch
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def main():
    items = read_tsv()
    if not items:
        sys.exit(1)
        
    heading_title = sys.argv[1] if len(sys.argv) > 1 else "Picker"

    write_tty("\033[?1049h\033[?25l")
    selected_idx = 0
    filter_text = ""

    try:
        while True:
            visible, selected_idx, columns, page_size = render_ui(items, selected_idx, filter_text, heading_title)

            key = read_key()

            if key == "UP":
                selected_idx = max(0, selected_idx - columns)
            elif key == "DOWN":
                selected_idx = min(len(visible) - 1, selected_idx + columns)
            elif key == "LEFT" and selected_idx % columns:
                selected_idx -= 1
            elif key == "RIGHT" and selected_idx % columns < columns - 1:
                selected_idx = min(len(visible) - 1, selected_idx + 1)
            elif key == "PGUP":
                selected_idx = max(0, selected_idx - page_size)
            elif key == "PGDN":
                selected_idx = min(len(visible) - 1, selected_idx + page_size)
            elif key in ("\r", "\n"):
                if visible:
                    sys.stdout.write(visible[selected_idx][0])
                    sys.stdout.flush()
                    sys.exit(0)
            elif key in ("\x7f", "\x08"):
                filter_text = filter_text[:-1]
                selected_idx = 0
            elif key in ("\x03", "\x1b", ""):
                if filter_text and key == "\x1b":
                    filter_text = ""
                    selected_idx = 0
                else:
                    sys.exit(1)
            elif len(key) == 1 and key.isprintable():
                filter_text += key
                selected_idx = 0
    finally:
        write_tty("\033[?25h\033[?1049l")

if __name__ == "__main__":
    main()
