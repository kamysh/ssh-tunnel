# ssh-tunnel

A macOS menu-bar SSH tunnel manager — a rewrite of STM (tynsoe "SSH Tunnel
Manager"). Bring a host's tunnels up/down from the menu bar and see their health,
with **no per-app state**: your ssh config is the complete source of truth.

See [DESIGN.md](DESIGN.md) for the reasoning behind the model (especially *why the
unit of control is the host*).

## Download

[![Latest release](https://img.shields.io/github/v/release/kamysh/ssh-tunnel)](https://github.com/kamysh/ssh-tunnel/releases/latest)

Grab the latest universal (Apple Silicon + Intel) `.dmg` from the
[**Releases**](https://github.com/kamysh/ssh-tunnel/releases/latest) page, open it,
and drag **Tunnels.app** to Applications. Each `v*` tag builds and publishes a DMG
automatically (see `.github/workflows/release.yml`).

The build is ad-hoc signed for now, so on first launch right-click the app →
**Open** (or `xattr -dr com.apple.quarantine /Applications/Tunnels.app`).

## Model in one paragraph

A "tunnel" is a **host** plus the forwards declared for it in ssh config. The app
**connects/disconnects a host as a unit** — connecting brings up the host's whole
configured forward set in one ControlMaster process; disconnecting drops them
together. The app stores nothing of its own: it reads config via `ssh -G`,
authenticates once, and monitors health. `ssh <host>` works on its own, exactly
as the config says — the app never disagrees with it.

## Layout

- `TunnelKit` — the engine (the future MenuBarExtra app depends only on this):
  - `SSHConfig.swift` — read a host's forwards via `ssh -G` (display + health).
  - `Connection.swift` — `HostConnection`: `connect` / `disconnect` / `isConnected`.
  - `PortProbe.swift` — is the local port listening? (checks IPv4 **and** IPv6).
  - `ProcessRunner.swift` — `Process` wrapper (temp-file capture, no pipe deadlock).
- `tunnels-askpass` — GUI askpass helper (passphrase / password / MFA / host-key).
- `tunnelctl` — CLI driver to exercise the engine before any UI exists.

## Build

```sh
swift build
```

Binaries land in `.build/debug/`. `tunnelctl` finds `tunnels-askpass` as a sibling.

## Config (the source of truth)

Real ssh directives in `~/.ssh/config` (or an `Include`d file). Forwards are
genuine `LocalForward`/`RemoteForward`/`DynamicForward` directives, so a plain
`ssh <host>` tunnels exactly as the app does.

Group a host's forwards into **independently-togglable units**: one alias per
group, with the shared connection settings written **once** in a `Host <host>*`
wildcard block. Use `%n` (the alias) — not `%C` — in `ControlPath`, so each group
gets its own connection (`%C` hashes host/user/port, which are identical across
the aliases, and would collapse them onto one socket):

```
Host myhost-vnc
    LocalForward 5901 localhost:5900

Host myhost-dev
    LocalForward 3000 localhost:3000
    LocalForward 3001 localhost:3001

Host myhost*                         # shared settings — written once
    HostName myhost.example.com
    User alice
    IdentityFile ~/.ssh/id_ed25519
    ControlMaster auto
    ControlPath ~/.ssh/cm-%n         # %n = alias → a separate connection per group
    ControlPersist 10m
```

The app lists each concrete alias (`myhost-vnc`, `myhost-dev`) as its own
on/off row; the `myhost*` wildcard is settings-only and isn't shown. A plain
`ssh myhost` matches the wildcard too — clean shell, no forwards.

## Usage

```sh
tunnelctl up     myhost     # connect: brings up ALL of myhost's forwards (askpass if the key is locked)
tunnelctl status myhost     # connected? which local ports are listening?
tunnelctl down   myhost     # disconnect: drops all of myhost's forwards
tunnelctl -F <file> …       # read connection/config from a specific file
```

There is intentionally **no per-forward on/off** — see DESIGN.md §"The decision".

## How it works

- **Connect:** `ssh -M -N -f -o ControlMaster=yes -o ControlPath=… <host>` opens a
  master that applies the host's configured forwards. `ExitOnForwardFailure=yes`
  makes a busy local port fail the whole connect (all-or-nothing) instead of
  coming up half-forwarded. Auth happens here, once.
- **Disconnect:** `ssh -O exit <host>` — the master dies, all forwards with it.
- **Health:** `ssh -O check` (is the host connected?) plus a local-port probe per
  forward. The probe checks both `127.0.0.1` and `[::1]` (a `localhost` forward
  binds both).
- **Auth without a TTY:** `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` (OpenSSH
  8.4+) route passphrase/password/MFA/host-key prompts to a native dialog — so a
  menu-bar app with no terminal can still drive interactive logins.

## Verified on this machine (OpenSSH 10.2p1, macOS)

- `ssh -G` emits resolved `localforward`/`remoteforward`/`dynamicforward` lines
  (connect host bracketed, e.g. `[localhost]:5432`; the reader normalizes that).
- ControlMaster gives one authenticated connection carrying all the host's forwards.
- `ssh` expands `~/.ssh/config` from the passwd DB, not `$HOME` — use `-F` to point
  elsewhere (also how `tunnelctl -F` targets a specific file).
- A `localhost` forward binds both IPv4 and IPv6 — health must probe both.

## Still to do

- The MenuBarExtra app on top of `TunnelKit` (host list + health dot + on/off;
  expand a host to show its forwards read-only, like STM).
- Reconnect-on-drop / wake-from-sleep policy.
- Import the other STM hosts (host-a, host-b, …) into the config.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
