#!/usr/bin/env python3
import sys, json, time, re

def fg(r, g, b): return f"\033[38;2;{r};{g};{b}m"
RESET = "\033[0m"
DIM   = "\033[2m"
C_OK  = fg(80, 220, 120)
C_RL  = fg(230, 80, 80)
C_BAR_OK = fg(60, 210, 110)
C_BAR_RL = fg(220, 60, 60)
C_WARN = fg(255, 200, 60)
C_BORDER = fg(60, 80, 110)

BLK_FULL = "█"

def nkey(s):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r'(\d+)', s)]

models_data = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
accounts_data = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}

accounts = [a for a in accounts_data.get("accounts", []) if a.get("enabled", True)]
now = time.time()

account_info = []
for a in accounts:
    email = a.get("email", "unknown")
    short = email.split("@")[0]
    if len(short) > 10: short = short[:9] + "…"
    account_info.append({"full": email, "short": short})

rl_map = {}
for a in accounts:
    email = a.get("email", "unknown")
    for mid, r in (a.get("modelRateLimits") or {}).items():
        if not mid: continue
        rl_map.setdefault(mid, {})
        is_rl = bool(r.get("isRateLimited"))
        reset_ms = r.get("resetTime") or 0
        reset_secs = max(0, int((reset_ms / 1000) - now)) if is_rl and reset_ms else 0
        rl_map[mid][email] = {"is_rl": is_rl, "reset_secs": reset_secs}

seen_models = set()
for m in models_data.get("data", []):
    if m.get("id"): seen_models.add(m.get("id"))

if not seen_models: sys.exit(0)

def calc_health(mid):
    total = len(account_info)
    if total == 0: return 0, 0, 0
    per_acc = rl_map.get(mid, {})
    rl_count = sum(1 for acc in account_info if per_acc.get(acc["full"], {}).get("is_rl", False))
    return total - rl_count, rl_count, total

sorted_models = sorted(seen_models, key=lambda m: (-calc_health(m)[0], nkey(m)))

def fmt_reset(secs):
    if secs <= 0: return "now"
    m, s = divmod(int(secs), 60)
    h, m = divmod(m, 60)
    if h: return f"{h}h{m:02d}m"
    if m: return f"{m}m"
    return f"{s}s"

for mid in sorted_models:
    ok, rl, total = calc_health(mid)
    
    # Health bar
    width = min(total * 2, 10)
    if total == 0:
        hbar = C_BORDER + (BLK_FULL * width) + RESET
    else:
        ok_w = round(ok / total * width)
        rl_w = width - ok_w
        hbar = C_BAR_OK + (BLK_FULL * ok_w) + C_BAR_RL + (BLK_FULL * rl_w) + RESET

    pct = int(ok / total * 100) if total else 0
    pct_col = C_OK if pct == 100 else (C_WARN if pct > 0 else C_RL)
    frac = f"{pct_col}{ok}/{total}{RESET}"
    
    pairs = []
    for acc in account_info:
        st = rl_map.get(mid, {}).get(acc["full"], {})
        if st.get("is_rl"):
            pairs.append(f"{C_RL}{acc['short']}:{fmt_reset(st.get('reset_secs', 0))}{RESET}")
        else:
            pairs.append(f"{C_OK}{acc['short']}:✓{RESET}")
            
    status_str = f"{hbar}  {frac}   {'  '.join(pairs)}"
    print(f"{mid}\t\t{status_str}")
