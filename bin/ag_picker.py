#!/usr/bin/env python3
"""
Antigravity Model Health & Quota Picker
Renders an interactive terminal UI displaying live per-account rate limits,
health bars, and reset countdowns for each model.
"""

import sys
import json
import time
import os
import re
import termios
import tty

# ── ANSI Helpers ──────────────────────────────────────────────────────────────
RESET = "\033[0m"
BOLD  = "\033[1m"
DIM   = "\033[2m"

def fg(r, g, b): return f"\033[38;2;{r};{g};{b}m"
def bg(r, g, b): return f"\033[48;2;{r};{g};{b}m"

C_HEADER        = fg(100, 180, 255)
C_BORDER        = fg(60, 80, 110)
C_OK            = fg(80, 220, 120)
C_RL            = fg(230, 80, 80)
C_WARN          = fg(255, 200, 60)
C_DIM           = fg(90, 110, 140)
C_SEL_BG        = bg(30, 50, 80)
C_SEL_FG        = fg(220, 240, 255) + BOLD
C_NUM           = fg(130, 130, 190)
C_BAR_OK        = fg(60, 210, 110)
C_BAR_RL        = fg(220, 60, 60)
C_VENDOR_CLAUDE = fg(190, 150, 255)
C_VENDOR_GEMINI = fg(80, 210, 170)
C_MODEL         = fg(210, 225, 255)

BLK_FULL = "█"

def strip_ansi(s):
    return re.sub(r'\033\[[^m]*m', '', s)

def vis_len(s):
    return len(strip_ansi(s))

def nkey(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r'(\d+)', s)]

# ── Parse Inputs ──────────────────────────────────────────────────────────────
models_json_raw   = sys.argv[1] if len(sys.argv) > 1 else "{}"
accounts_json_raw = sys.argv[2] if len(sys.argv) > 2 else "{}"

try:
    models_data = json.loads(models_json_raw)
except Exception:
    models_data = {}

try:
    accounts_data = json.loads(accounts_json_raw)
except Exception:
    accounts_data = {}

accounts = [a for a in accounts_data.get("accounts", []) if a.get("enabled", True)]
now      = time.time()

# Map accounts to display labels
account_info = []
for a in accounts:
    email = a.get("email", "unknown")
    short_name = email.split("@")[0]
    if len(short_name) > 10:
        short_name = short_name[:9] + "…"
    account_info.append({
        "full": email,
        "short": short_name,
        "raw": a
    })

# Map per-model, per-account status
# rl_map[model_id][email] = {"is_rl": bool, "reset_secs": int}
rl_map = {}
for a in accounts:
    email = a.get("email", "unknown")
    limits = a.get("modelRateLimits") or {}
    for model_id, r in limits.items():
        if not model_id:
            continue
        rl_map.setdefault(model_id, {})
        is_rl = bool(r.get("isRateLimited"))
        reset_ms = r.get("resetTime") or 0
        reset_secs = max(0, int((reset_ms / 1000) - now)) if is_rl and reset_ms else 0
        rl_map[model_id][email] = {
            "is_rl": is_rl,
            "reset_secs": reset_secs
        }

# Gather all unique model IDs
seen_models = set()
model_descriptions = {}

for m in models_data.get("data", []):
    mid = m.get("id", "")
    if mid:
        seen_models.add(mid)
        if m.get("description"):
            model_descriptions[mid] = m.get("description")

# The catalog passed in is authoritative. Rate-limit entries are deliberately NOT
# merged into the model list: modelRateLimits only ever names models that have
# already been rate limited, so merging them can only re-introduce something the
# caller chose to filter out (e.g. a model that is dead server-side and would fail
# every request). Per-account limits are still read below for the health display.

if not seen_models:
    sys.stderr.write("No models found in proxy payload.\n")
    sys.exit(1)

def calc_health(mid):
    total = len(account_info)
    if total == 0:
        return 0, 0, 0
    per_acc = rl_map.get(mid, {})
    rl_count = sum(1 for acc in account_info if per_acc.get(acc["full"], {}).get("is_rl", False))
    ok_count = total - rl_count
    return ok_count, rl_count, total

def sort_models_key(mid):
    ok, rl, total = calc_health(mid)
    # Sort by: 1) ok count desc, 2) mid asc
    return (-ok, nkey(mid))

sorted_models = sorted(seen_models, key=sort_models_key)

# ── Helper Formatting ─────────────────────────────────────────────────────────
def vendor_color(mid):
    m = mid.lower()
    if "claude" in m: return C_VENDOR_CLAUDE
    if "gemini" in m: return C_VENDOR_GEMINI
    return C_MODEL

def fmt_reset(secs):
    if secs <= 0: return "now"
    m, s = divmod(int(secs), 60)
    h, m = divmod(m, 60)
    if h:  return f"{h}h{m:02d}m"
    if m:  return f"{m}m"
    return f"{s}s"

def draw_health_bar(ok, total, width=8):
    if total == 0:
        return C_BORDER + (BLK_FULL * width) + RESET
    ok_w = round(ok / total * width)
    rl_w = width - ok_w
    return C_BAR_OK + (BLK_FULL * ok_w) + C_BAR_RL + (BLK_FULL * rl_w) + RESET

def draw_account_pairs(mid):
    per_acc = rl_map.get(mid, {})
    pairs = []
    for acc in account_info:
        st = per_acc.get(acc["full"], {})
        is_rl = st.get("is_rl", False)
        reset = st.get("reset_secs", 0)
        short = acc["short"]
        if is_rl:
            t_str = fmt_reset(reset)
            pairs.append(f"{C_RL}{short}:{t_str}{RESET}")
        else:
            pairs.append(f"{C_OK}{short}:✓{RESET}")
    return "  ".join(pairs)

# ── Terminal I/O & Rendering ──────────────────────────────────────────────────
# Open tty explicitly so stdout can remain clean for script capturing
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

def render_ui(selected_idx, scroll_offset, filter_text, is_filtering):
    tw, th = get_termsize()
    
    # Filter visible list
    if filter_text:
        visible = [m for m in sorted_models if filter_text.lower() in m.lower()]
        if not visible:
            visible = sorted_models
    else:
        visible = sorted_models

    total_vis = len(visible)
    selected_idx = max(0, min(selected_idx, total_vis - 1))

    max_rows = max(4, th - 10)
    if selected_idx < scroll_offset:
        scroll_offset = selected_idx
    if selected_idx >= scroll_offset + max_rows:
        scroll_offset = selected_idx - max_rows + 1

    lines = []

    # 1. Header Box
    title = " Antigravity · Model Health & Account Quotas "
    hdr = C_HEADER + BOLD + "╔══" + title + "═" * max(0, tw - len(title) - 4) + "╗" + RESET
    lines.append(hdr)

    # 2. Account Legend
    acc_tags = [f"{C_DIM}{a['short']}{RESET}" for a in account_info]
    leg_str = C_BORDER + "║" + RESET + "  " + DIM + "Accounts (" + str(len(account_info)) + "): " + RESET + "  ".join(acc_tags)
    pad = tw - 1 - vis_len(strip_ansi(leg_str))
    lines.append(leg_str + " " * max(0, pad) + C_BORDER + "║" + RESET)

    lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)

    # 3. Filter Bar (if active)
    if filter_text or is_filtering:
        cur = "▌" if is_filtering else ""
        fbar = (C_BORDER + "║" + RESET + "  " + C_WARN + " Search: " + RESET +
                BOLD + filter_text + cur + RESET +
                (DIM + "  (ESC to clear · Enter to lock)" + RESET if is_filtering else ""))
        pad = tw - 1 - vis_len(strip_ansi(fbar))
        lines.append(fbar + " " * max(0, pad) + C_BORDER + "║" + RESET)
        lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)

    # 4. Model Rows
    for i in range(scroll_offset, min(scroll_offset + max_rows, total_vis)):
        mid = visible[i]
        ok, rl, total = calc_health(mid)
        is_selected = (i == selected_idx)

        # Health percentage & fraction
        pct = int(ok / total * 100) if total else 0
        pct_col = C_OK if pct == 100 else (C_WARN if pct > 0 else C_RL)
        
        hbar = draw_health_bar(ok, total, width=min(total * 2, 10))
        frac = f"{pct_col}{ok}/{total}{RESET}"
        num_str = f"{C_NUM}{i+1:>2}){RESET}"
        name_str = f"{vendor_color(mid)}{mid}{RESET}"
        pairs_str = draw_account_pairs(mid)

        name_pad = " " * max(1, 32 - len(mid))
        row_content = f"  {num_str} {name_str}{name_pad} {hbar}  {frac}   {pairs_str}"

        if is_selected:
            raw_len = vis_len(strip_ansi(row_content))
            pad_len = max(0, tw - 2 - raw_len)
            row_content = C_SEL_BG + C_SEL_FG + row_content + " " * pad_len + RESET

        lines.append(C_BORDER + "║" + RESET + row_content + C_BORDER + "║" + RESET)

    # 5. Scroll info
    if total_vis > max_rows:
        end_idx = min(scroll_offset + max_rows, total_vis)
        hint = DIM + f"  ↑↓ scroll  [{scroll_offset+1}–{end_idx} of {total_vis} models]" + RESET
        pad = tw - 1 - vis_len(strip_ansi(hint))
        lines.append(C_BORDER + "║" + RESET + hint + " " * max(0, pad) + C_BORDER + "║" + RESET)

    lines.append(C_BORDER + "╠" + "═" * (tw - 2) + "╣" + RESET)
    keys_help = DIM + "  ↑/↓: navigate   Enter: select model   /: search   q: cancel" + RESET
    pad = tw - 1 - vis_len(strip_ansi(keys_help))
    lines.append(C_BORDER + "║" + RESET + keys_help + " " * max(0, pad) + C_BORDER + "║" + RESET)
    lines.append(C_BORDER + "╚" + "═" * (tw - 2) + "╝" + RESET)

    # Draw to TTY
    write_tty("\033[H\033[J" + "\n".join(lines) + "\n")
    return visible, selected_idx, scroll_offset

def read_key():
    fd = tty_in.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = tty_in.read(1)
        if ch == "\033":
            # Escape sequence
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
    write_tty("\033[?25l") # Hide cursor
    selected_idx = 0
    scroll_offset = 0
    filter_text = ""
    is_filtering = False

    try:
        while True:
            visible, selected_idx, scroll_offset = render_ui(
                selected_idx, scroll_offset, filter_text, is_filtering
            )

            key = read_key()

            if is_filtering:
                if key in ("\r", "\n"):
                    is_filtering = False
                elif key in ("\x7f", "\x08"):
                    filter_text = filter_text[:-1]
                elif key in ("\x1b", "q"):
                    filter_text = ""
                    is_filtering = False
                elif len(key) == 1 and key.isprintable():
                    filter_text += key
                    selected_idx = 0
                    scroll_offset = 0
                continue

            if key in ("UP", "k"):
                selected_idx = max(0, selected_idx - 1)
            elif key in ("DOWN", "j"):
                selected_idx = min(len(visible) - 1, selected_idx + 1)
            elif key == "PGUP":
                selected_idx = max(0, selected_idx - 10)
            elif key == "PGDN":
                selected_idx = min(len(visible) - 1, selected_idx + 10)
            elif key in ("\r", "\n", " "):
                write_tty("\033[?25h\033[H\033[J") # Restore cursor & clear
                # Print ONLY selected model ID to standard stdout
                sys.stdout.write(visible[selected_idx])
                sys.stdout.flush()
                sys.exit(0)
            elif key == "/":
                is_filtering = True
                filter_text = ""
                selected_idx = 0
                scroll_offset = 0
            elif key in ("q", "Q", "\x03", "\x1b"):
                write_tty("\033[?25h\033[H\033[J") # Restore cursor & clear
                sys.exit(1)
    finally:
        write_tty("\033[?25h")

if __name__ == "__main__":
    main()
