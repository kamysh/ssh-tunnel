# ssh-tunnel — design

## 1. Goal

Rewrite STM (tynsoe "SSH Tunnel Manager"): a macOS menu-bar app that brings SSH
port-forwards up and down with one click and shows their health, without a
permanently-open window.

## 2. The principle

**ssh config is the *complete* source of truth.** Tunnels are defined as real ssh
directives; the app keeps no parallel store and `ssh <host>` must behave exactly
as the app does. This is non-negotiable and it decides everything below.

## 3. The decision: the unit of control is the host

The hard question was: can you turn off *one forward* of a host while keeping its
others up? We first chased this as a technical problem and it thrashed. The real
answer is conceptual:

- ssh config is **declarative and complete** — it defines *what a host's tunnel
  is*: these forwards, this connection.
- The one legitimate piece of runtime state outside config is **"is this host
  connected right now"** — ephemeral, like whether an ssh session is open. Config
  defines the connection; it never claimed to say whether it is currently *up*.
- **Per-forward enable/disable is a different kind of state.** "3002 is off while
  3000 stays on" is not "connected vs not" — it is a *configuration* fact. ssh
  config cannot express "this declared forward is administratively disabled."

So the moment the app offers per-forward on/off, that state must live **in the
app** — and ssh config is no longer the complete source of truth. `ssh myhost`
(which brings up all five) would then disagree with the app. The feature is
self-defeating *given §2*, independent of whether ssh can technically do it.

**Therefore the host is the unit.** A host's forward set is all-or-nothing,
exactly as declared. The app toggles host *connections* (runtime) and holds zero
tunnel state. "Turn off a particular tunnel" = turn off a host; its forwards drop
together. (This is also, not coincidentally, what STM does — forwards are grouped
under a host and the host is what you enable/disable.)

## 4. What we ruled out, and why

- **Per-forward live toggle over one master** (`-O forward` / `-O cancel`).
  Excluded **on principle** (§3), *not* capability. For the record: selective
  cancel is a real, documented-by-practice feature — the
  [OpenSSH Cookbook](https://en.wikibooks.org/wiki/OpenSSH/Cookbook/Multiplexing)
  and a [demo gist](https://gist.github.com/aculich/4265549) show `ssh -O cancel
  -L <spec> host` removing one forward while others keep working, *provided the
  cancel spec matches the original exactly (including bind address)*. Our spike's
  "it cancels all" result was a confound (duplicate-stacked forwards from repeated
  blind re-adds, plus forwards created two different ways). We did not finish
  isolating whether 10.2p1 also regresses — moot, since the feature is excluded
  regardless.
- **Forwards as app-managed catalog / `# tunnel` comments.** This makes
  per-forward processes possible but breaks §2: `ssh <host>` would no longer
  tunnel. Rejected.
- **`ClearAllForwardings` + command-line `-L` on a child.** `ssh_config(5)` says
  it clears forwards "in the configuration files **or on the command line**", so
  it can't suppress siblings while keeping one `-L`. Dead end.

## 5. Verified facts (grounded, OpenSSH 10.2p1 / macOS unless noted)

| # | Fact |
|---|------|
| F1 | `ssh -G <host>` emits resolved `localforward`/`remoteforward`/`dynamicforward` lines; connect host is bracketed (`[localhost]:5432`). |
| F2 | `ssh -G` resolves Include / Match / ProxyJump as ssh does (docs + tested). |
| F3 | ControlMaster + ControlPath + ControlPersist → one authenticated connection carrying all the host's forwards; reused without re-auth. |
| F4 | `ssh -O check` / `-O exit` cleanly report/teardown the connection. |
| F5 | `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` (OpenSSH 8.4+) route prompts to a GUI helper with no TTY. |
| F6 | A `localhost` forward binds both 127.0.0.1 and [::1] (lsof) — health must probe both. |
| F7 | `ssh` expands `~/.ssh/config` from the passwd DB, not `$HOME`; use `-F`. |
| F8 | `ssh -f` backgrounds a long-lived child that inherits stdio — capture output via temp files, not pipes, or `readToEnd` deadlocks. |

## 6. Engine (host-as-unit)

- **Catalog:** `ssh -G <host>` → hostname + forwards, for display and health only.
- **Connect:** `ssh -M -N -f -o ControlMaster=yes -o ControlPath=… <host>` — one
  master applying all configured forwards. No `ClearAllForwardings` (we want them).
  `ExitOnForwardFailure=yes` → all-or-nothing.
- **Disconnect:** `ssh -O exit <host>`.
- **Health:** `-O check` AND per-forward local-port probe (both address families).
- **Auth:** askpass helper for passphrase/password/MFA; agent keys need no prompt.
- **App state:** only "which hosts are connected." Nothing else.

## 7. Open questions

1. ControlMaster vs. a plain `ssh -Nf` per host. ControlMaster wins: it gives
   `-O check`/`-O exit` and lets a terminal `ssh host` reuse the connection.
2. Reconnect policy on drop / sleep / network change (STM auto-restores).
3. Remote (`-R`) forwards: no local listener to probe — show "connected" only.
4. Menu-bar UX: host list + health dot + on/off; expand to show forwards read-only.
5. Import the rest of the STM hosts (host-a, host-c, host-d, host-b).

## 8. Process note

This design was reached the hard way — guessing, then RTFM, then community
sources. The durable lesson: when behavior is unclear, read the manual and find
how practitioners actually do it *before* concluding from local trial-and-error;
and check whether a hard feature conflicts with a stated principle before fighting
the tools to build it.
