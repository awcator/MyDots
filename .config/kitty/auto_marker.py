"""
Kitty watcher: auto-enables word highlighting on every window.

Hooks used:
- on_load: sets marker on all existing windows when kitty starts
- on_resize: catches the initial window (first resize = window creation)
- on_focus_change: catches new windows when they gain focus
- on_close: cleanup

Colors: mark1=red(errors), mark2=green(success), mark3=yellow(status/info)

Priority: kitty combines patterns into one regex with |, so mark1 (red)
is checked first — if a word could match both red and green, red wins.

Requires Python 3.14+ compatible regex (no inline (?i) flags — kitty's
'iregex' marker type handles case-insensitivity via re.IGNORECASE).
No leading \\b so keywords match even mid-word (ConnectionError, fewerror).
No trailing \\w* so only the matched keyword is highlighted, not the suffix.
"""

# ── mark1: RED — errors, failures, problems ──────────────────────────────
E = (
    # general failure verbs/nouns
    r'(error|err|fail|fault|fatal|critical|severe|panic|oops|not|'
    r'crash|segfault|segv|sigsegv|sigabrt|sigkill|sigterm|'
    r'coredump|core\s+dump|abort|exception|throwable|'
    r'traceback|stacktrace|stack\s+trace|backtrace|'
    r'assertion|violation|doesnt|doesn|cant|'
    # denied / refused / auth failures
    r'denied|refused|forbidden|unauthorized|unauthenticated|'
    r'rejected|revoked|banned|blacklisted|blocklisted|restricted|'
    r'locked\s+out|access\s+denied|permission\s+denied|lock|'
    # unavailable / unreachable
    r'unavailable|unreachable|unresponsive|disconnected|offline|'
    r'down|dead|gone|lost|missing|absent|not\s+found|no\s+such|end|'
    # broken state
    r'broken|corrupt|malformed|invalid|illegal|bad|wrong|incorrect|'
    r'inconsistent|mismatch|incompatible|unsupported|unrecognized|'
    r'unexpected|unknown|undefined|uninitialized|null|nil|nan|void|'
    r'nullptr|nullpointer|nullref|npe|empty|blank|'
    # explicit negative outcomes
    r'failed|failure|unsuccessful|unresolved|unhandled|uncaught|'
    r'unprocessed|undelivered|unfinished|incomplete|'
    r'unfulfilled|unmatched|unparseable|unreadable|'
    # health / stability
    r'unhealthy|unstable|degraded|impaired|flaky|flapping|'
    # resource problems
    r'overflow|underflow|overrun|underrun|exhausted|full|'
    r'leak|leaked|leaking|oom|out\s+of\s+memory|'
    r'out\s+of\s+space|out\s+of\s+disk|no\s+space|disk\s+full|'
    r'exceeded|overlimit|throttled|rate\s+limit|'
    # timeout / hang
    r'timeout|timedout|timed\s+out|deadline|expired|stale|'
    r'hung|frozen|stuck|blocked|stalled|deadlock|livelock|'
    r'starved|starvation|bottleneck|'
    # stopped / killed
    r'killed|terminated|aborted|cancelled|canceled|stopped|halted|'
    r'shutdown|crashed|dumped|trapped|interrupted|'
    r'exited\s+with|exit\s+code|non-zero|nonzero|zero|'
    # network / dns
    r'NXDOMAIN|SERVFAIL|REFUSED|FORMERR|connreset|connrefused|'
    r'connection\s+reset|connection\s+refused|connection\s+closed|close'
    r'broken\s+pipe|reset\s+by\s+peer|host\s+unreachable|'
    r'network\s+unreachable|no\s+route|dns\s+fail|'
    r'ssl\s+error|tls\s+error|handshake\s+fail|cert\s+expired|'
    # data integrity
    r'truncated|garbled|scrambled|overwritten|clobbered|'
    r'collision|conflict|duplicate|'
    r'checksum|crc\s+error|hash\s+mismatch|digest\s+mismatch|'
    # rollback / revert
    r'rollback|reverted|regression|downgraded|'
    # deprecation / removal
    r'deprecated|obsolete|removed|dropped|abandoned|orphaned|'
    r'eol|end\s+of\s+life|sunset|'
    # negative words
    r'negative|unable|cannot|impossible|'
    r'nothing|nowhere|nobody|'
    # warning level
    r'warning|warn|alert|alarm|danger|dangerous|hazard|'
    r'caution|urgent|'
    # http error codes
    r'400|401|403|404|405|406|408|409|410|411|412|413|414|'
    r'415|416|422|423|424|429|431|451|'
    r'500|501|502|503|504|505|507|508|511|'
    # exit codes
    r'errno|errcode|errnum|exitcode)'
)

# ── mark2: GREEN — success, positive outcomes ────────────────────────────
S = (
    # explicit success
    r'(ok|okay|yes|success|succeed|'
    r'pass|passed|passing|'
    r'done|complete|accomplish|achieve|'
    r'finish|finalize|'
    # positive state
    r'ready|available|active|alive|healthy|stable|steady|resilient|'
    r'online|reachable|accessible|responsive|up|'
    r'running|operational|functional|working|'
    r'valid|verified|validated|confirmed|certified|authentic|'
    r'consistent|coherent|intact|pristine|'
    # connection / auth
    r'connected|established|bound|listening|accepted|'
    r'authenticated|authorized|granted|permitted|allowed|'
    r'enabled|activated|unlocked|opened|'
    # creation / deployment
    r'created|built|compiled|assembled|generated|produced|'
    r'installed|deployed|released|published|shipped|launched|delivered|'
    r'provisioned|configured|applied|'
    # fix / recovery
    r'fixed|repaired|resolved|recovered|restored|healed|'
    r'patched|remediated|mitigated|rescued|'
    # data operations
    r'saved|stored|persisted|committed|written|flushed|'
    r'cached|indexed|replicated|backed\s+up|'
    r'merged|synced|synchronized|aligned|reconciled|'
    r'received|acknowledged|acked|'
    # positive adjectives
    r'correct|accurate|proper|good|great|fine|'
    r'clean|safe|secure|trusted|reliable|robust|solid|'
    r'approved|endorsed|recommended|preferred|optimal|'
    r'improved|enhanced|optimized|upgraded|'
    # found / matched
    r'found|located|detected|discovered|matched|identified|'
    r'recognized|resolved|'
    # registered / initialized
    r'registered|enrolled|subscribed|joined|'
    r'initialized|bootstrapped|loaded|mounted|attached|'
    # test results
    r'NOERROR|noterror|'
    r'green|✓|✔|passed|approved|'
    # http success codes
    r'200|201|202|203|204|206|'
    r'301|302|304)'
)

# ── mark3: YELLOW — status, info, in-progress ────────────────────────────
T = (
    # in-progress states
    r'(loading|pending|waiting|processing|busy|open'
    r'queued|enqueued|scheduled|dispatched|dequeued|'
    r'executing|computing|calculating|rendering|'
    r'compiling|building|assembling|linking|packaging|bundling|'
    r'testing|benchmarking|profiling|linting|formatting|'
    # io operations
    r'reading|writing|copying|moving|renaming|'
    r'downloading|uploading|streaming|piping|'
    r'sending|receiving|transmitting|broadcasting|multicasting|'
    r'fetching|pulling|pushing|cloning|mirroring|syncing|'
    # lifecycle
    r'starting|stopping|restarting|rebooting|'
    r'spawning|forking|launching|booting|'
    r'initializing|configuring|preparing|provisioning|'
    r'connecting|reconnecting|handshaking|negotiating|'
    r'authenticating|authorizing|'
    r'migrating|upgrading|updating|patching|'
    r'installing|uninstalling|reinstalling|'
    r'shutting\s+down|winding\s+down|draining|'
    r'reloading|refreshing|recycling|rotating|'
    r'scaling|autoscaling|rebalancing|resharding|'
    # monitoring / observability
    r'monitoring|watching|observing|polling|probing|pinging|'
    r'scanning|sweeping|crawling|indexing|'
    r'tracing|logging|auditing|recording|capturing|sampling|'
    r'snapshotting|checkpointing|'
    r'inspecting|examining|analyzing|evaluating|diagnosing|'
    # sync / schedule
    r'synchronizing|replicating|propagating|'
    r'flushing|purging|evicting|expiring|'
    r'retrying|backoff|retry|attempt|'
    r'resuming|recovering|replaying|'
    r'pausing|suspending|sleeping|idling|'
    # informational keywords
    r'info|notice|note|hint|tip|remark|'
    r'debug|verbose|trace|log|'
    r'status|progress|update|report|summary|overview|'
    r'check|verify|validate|inspect|lint|'
    # requirement / importance
    r'required|mandatory|needed|necessary|essential|'
    r'important|must|should|shall|'
    r'todo|fixme|hack|xxx|nb|'
    # component labels
    r'worker|thread|process|daemon|service|job|task|cron|'
    r'handler|listener|observer|notifier|dispatcher|emitter|'
    r'scheduler|executor|runner|controller|manager|orchestrator|'
    r'heartbeat|keepalive|healthcheck|watchdog|sentinel|'
    r'middleware|interceptor|filter|pipeline|'
    # misc process
    r'allocating|deallocating|freeing|collecting|garbage|gc|'
    r'parsing|serializing|deserializing|marshalling|unmarshalling|'
    r'encoding|decoding|encrypting|decrypting|'
    r'compressing|decompressing|zipping|unzipping|'
    r'hashing|signing|verifying|'
    r'resolving|looking\s+up|querying|requesting|'
    r'binding|unbinding|subscribing|unsubscribing|'
    r'caching|invalidating|warming|prefetching|key)'
)

SPEC = ['iregex', '1', E, '2', S, '3', T]

_marked = set()

def _apply(window):
    if window is not None and window.id not in _marked:
        _marked.add(window.id)
        try:
            window.set_marker(SPEC)
        except Exception:
            _marked.discard(window.id)

def on_load(boss, data):
    try:
        for os_win in boss.os_windows.values():
            for tab in os_win.tabs:
                for window in tab.windows:
                    _apply(window)
    except Exception:
        pass  # windows may not be ready yet; on_resize will catch them

def on_resize(boss, window, data):
    _apply(window)

def on_focus_change(boss, window, data):
    _apply(window)

def on_close(boss, window, data):
    _marked.discard(window.id)
