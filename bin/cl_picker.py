#!/usr/bin/env python3
"""
Generic Interactive Terminal Picker
Reads TSV from stdin (or file): ID [TAB] Title [TAB] Status
Returns the selected ID on stdout.
"""

import sys, os, re, termios, tty

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
C_NUM    = fg(130, 130, 190)
C_ID     = fg(210, 225, 255)

def strip_ansi(s):
    return re.sub(r'\033\[[^m]*m', '', s)

def vis_len(s):
    return len(strip_ansi(s))

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
        return max(sz.columns, 80), max(sz.lines, 20)
    except Exception:
        return 100, 30

def render_ui(items, selected_idx, scroll_offset, filter_text, heading_title):
    tw, th = get_termsize()
    
    if filter_text:
        visible = [m for m in items if filter_text.lower() in m[0].lower() or filter_text.lower() in m[1].lower()]
    else:
        visible = items

    total_vis = len(visible)
    selected_idx = max(0, min(selected_idx, total_vis - 1))

    max_rows = max(4, th - 8)
    if selected_idx < scroll_offset:
        scroll_offset = selected_idx
    if selected_idx >= scroll_offset + max_rows:
        scroll_offset = selected_idx - max_rows + 1

    lines = []
    hdr = C_HEADER + BOLD + f"╔══ {heading_title} "
    hdr += "═" * max(0, tw - vis_len(strip_ansi(hdr)) - 1) + "╗" + RESET
    lines.append(hdr)

    if True:
        cur = "▌"
        fbar = (C_BORDER + "║" + RESET + "  " + C_WARN + " Search: " + RESET +
                BOLD + filter_text + cur + RESET +
                DIM + "  (type to fuzzy search)" + RESET)
        pad = tw - 1 - vis_len(strip_ansi(fbar))
        lines.append(fbar + " " * max(0, pad) + C_BORDER + "║" + RESET)
        lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)

    for i in range(scroll_offset, min(scroll_offset + max_rows, total_vis)):
        mid, title, status = visible[i]
        is_selected = (i == selected_idx)

        num_str = f"{C_NUM}{i+1:>2}){RESET}"
        name_str = f"{C_ID}{mid}{RESET}"
        
        row_content = f"  {num_str} {name_str}"
        if title and title != mid:
            row_content += f" {DIM}· {title}{RESET}"
        if status:
            row_content += f"  {status}"

        if is_selected:
            raw_len = vis_len(strip_ansi(row_content))
            pad_len = max(0, tw - 2 - raw_len)
            row_content = C_SEL_BG + C_SEL_FG + row_content + " " * pad_len + RESET
        else:
            raw_len = vis_len(strip_ansi(row_content))
            pad_len = max(0, tw - 2 - raw_len)
            row_content += " " * pad_len

        lines.append(C_BORDER + "║" + RESET + row_content + C_BORDER + "║" + RESET)

    if total_vis == 0:
        msg = f"  {C_WARN}No matches found for '{filter_text}'{RESET}"
        pad_len = max(0, tw - 2 - vis_len(strip_ansi(msg)))
        lines.append(C_BORDER + "║" + RESET + msg + " " * pad_len + C_BORDER + "║" + RESET)

    if total_vis > max_rows:
        end_idx = min(scroll_offset + max_rows, total_vis)
        hint = DIM + f"  ↑↓ scroll  [{scroll_offset+1}–{end_idx} of {total_vis}]" + RESET
        pad = tw - 1 - vis_len(strip_ansi(hint))
        lines.append(C_BORDER + "║" + RESET + hint + " " * max(0, pad) + C_BORDER + "║" + RESET)

    lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)
    keys_help = DIM + "  ↑/↓: nav   Enter: pick   ESC: clear/quit" + RESET
    pad = tw - 1 - vis_len(strip_ansi(keys_help))
    lines.append(C_BORDER + "║" + RESET + keys_help + " " * max(0, pad) + C_BORDER + "║" + RESET)
    lines.append(C_BORDER + "╚" + "═" * (tw - 2) + "╝" + RESET)

    write_tty("\033[H\033[J" + "\n".join(lines) + "\n")
    return visible, selected_idx, scroll_offset

def read_key():
    fd = tty_in.fileno()
    if not os.isatty(fd):
        return tty_in.read(1)
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = tty_in.read(1)
        if ch == "\033":
            ch2 = tty_in.read(1)
            if ch2 == "[":
                ch3 = tty_in.read(1)
                if ch3 == "A": return "UP"
                if ch3 == "B": return "DOWN"
                if ch3 == "5": tty_in.read(1); return "PGUP"
                if ch3 == "6": tty_in.read(1); return "PGDN"
                return ch3
            return ch2
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def main():
    items = read_tsv()
    if not items:
        sys.exit(1)
        
    heading_title = sys.argv[1] if len(sys.argv) > 1 else "Picker"

    write_tty("\033[?25l")
    selected_idx = 0
    scroll_offset = 0
    filter_text = ""
    
    try:
        while True:
            visible, selected_idx, scroll_offset = render_ui(
                items, selected_idx, scroll_offset, filter_text, heading_title
            )

            key = read_key()

            if key in ("UP",):
                selected_idx = max(0, selected_idx - 1)
            elif key in ("DOWN",):
                selected_idx = min(len(visible) - 1, selected_idx + 1)
            elif key == "PGUP":
                selected_idx = max(0, selected_idx - 10)
            elif key == "PGDN":
                selected_idx = min(len(visible) - 1, selected_idx + 10)
            elif key in ("\r", "\n"):
                if visible:
                    write_tty("\033[?25h\033[H\033[J")
                    sys.stdout.write(visible[selected_idx][0])
                    sys.stdout.flush()
                    sys.exit(0)
            elif key in ("\x7f", "\x08"):
                filter_text = filter_text[:-1]
                selected_idx = 0
                scroll_offset = 0
            elif key in ("\x03", "\x1b", ""):
                if filter_text and key == "\x1b":
                    filter_text = ""
                    selected_idx = 0
                    scroll_offset = 0
                else:
                    write_tty("\033[?25h\033[H\033[J")
                    sys.exit(1)
            elif len(key) == 1 and key.isprintable():
                filter_text += key
                selected_idx = 0
                scroll_offset = 0
    finally:
        write_tty("\033[?25h")

if __name__ == "__main__":
    main()
