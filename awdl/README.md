# awdl — keep AWDL off, allow it on demand

A Mac with excellent Wi-Fi can still stutter, and lose a lot of speed: pings to the router jump from
~4 ms to 50–130 ms in regular bursts, and download throughput can drop by ~40%. The cause is usually **AWDL** (Apple Wireless Direct Link, interface `awdl0`), the
peer-to-peer Wi-Fi behind AirDrop, Handoff, Universal Control and Sidecar. While `awdl0` is up, the
Wi-Fi chip keeps leaving your network's channel to rendezvous with nearby Apple devices on AWDL's own
channels (149 in the US), and your traffic waits until it comes back.

This tool keeps `awdl0` down, and lets you allow it for a few minutes when you want AirDrop:

```
awdl on        # AirDrop works for 10 minutes, then AWDL is blocked again
awdl on 30     # … for 30 minutes
awdl off       # block it now
awdl status    # guard running?, awdl0 up/down, minutes left
```

## What it fixed

Measured on one Mac (MacBook Air, Wi-Fi 6, 2×2) on 5 GHz, 80 MHz, signal around −41 dBm, on gigabit
fiber, so the Mac's Wi-Fi link is the bottleneck.

### Throughput — macOS `networkQuality -s`

Runs alternated off / on / off / on a few minutes apart (`awdl off` / `awdl on 5`), average of two
runs each:

| | AWDL off | AWDL on | AWDL on vs off |
|---|---|---|---|
| **Download** | **647 Mbps** (656, 639) | **361 Mbps** (358, 363) | **−44%** |
| **Upload** | **591 Mbps** (601, 581) | **426 Mbps** (428, 423) | **−28%** |
| Download responsiveness | 642 RPM (650, 633) | 380 RPM (489, 270) | −41% |
| Upload responsiveness | 824 RPM (688, 960) | 679 RPM (648, 709) | −18% |
| Idle latency | 62.6 ms (62.5, 62.7) | 94.5 ms (88.0, 100.9) | +51% |

Every off-hop is airtime the Mac can't send or receive in, so throughput suffers as well as latency.
Download loses more because the router has to hold and resend frames that arrive while the Mac is
away. (RPM = round-trips per minute under load, higher is better; `networkQuality`'s idle latency
includes connection setup to Apple's servers, so it reads higher than a plain ping.)

### Latency — 120 pings at 10/s to the router

| | Spikes > 20 ms | Average |
|---|---|---|
| AWDL up (default macOS) | 18–37 of 120, up to 129 ms | 13–21 ms |
| AirDrop off, AirPlay + Receiver off, Universal Control off | still 20–37 of 120 | 14–21 ms |
| Router "network optimization" (5 GHz ch 48 → 36) | still 18 of 120 | 13 ms |
| **`awdl0` down** | **0 of 120** | **4.3 ms** |

Turning features off in System Settings stops the Mac *advertising* over AWDL, but while `awdl0` is
up it still stays in sync with nearby Apple devices and keeps hopping. Picking channel 149 on the
router (so Wi-Fi and AWDL share a channel) also fixes it, but many mesh routers (e.g. TP-Link Deco)
don't let you choose the channel. Hence: keep `awdl0` down.

## What you lose while AWDL is blocked

- **Stops working:** AirDrop, Universal Control, wireless Sidecar, Handoff / Universal Clipboard;
  likely also iPhone Mirroring, wireless Continuity Camera and Apple Watch Auto Unlock.
- **Keeps working:** AirPlay to Apple TVs / speakers **on the same Wi-Fi** (found over your network,
  not AWDL), AirPlay Receiver from devices on the same Wi-Fi, everything else on the network.

`awdl on` brings it all back for a while.

## How it works

- **`awdl-guard`** (root, LaunchDaemon `io.github.the-dsvolk.awdl-guard`) checks every 2 s. If the
  allow file holds a time in the future, it brings `awdl0` up; otherwise it takes it down. macOS turns
  `awdl0` back on by itself (opening AirDrop, Control Center…), so a one-off `ifconfig awdl0 down`
  doesn't last; the guard puts it back within ~2 s. Each change goes to the system log (macOS files
  `logger` lines under the process name `logger`):
  `log show --last 1h --predicate 'process == "logger" AND eventMessage BEGINSWITH "awdl-guard"'`
- **`awdl`** (you, no sudo) only writes or removes the allow file,
  `~/.local/state/awdl-guard/allow-until` (a Unix time). The allow window expires on its own, so
  forgetting `awdl off` costs at most the minutes you asked for.
- **Safety:** the installer copies the guard to `/usr/local/libexec/awdl-guard`, owned by root, so root
  never runs a file you can edit. The guard reads only digits from the allow file; anything else
  (missing, empty, garbage) means "blocked".

## Install

```bash
git clone https://github.com/the-dsvolk/mac-tools && cd mac-tools/awdl
./test.sh                 # optional: tests with a fake ifconfig, no root, doesn't touch awdl0
sudo ./install.sh         # guard + LaunchDaemon; links `awdl` into ~/.local/bin
awdl status
```

No terminal handy (e.g. from a script or an agent)? The macOS admin dialog works too:

```bash
osascript -e 'do shell script "'"$PWD"'/install.sh" with administrator privileges'
```

`~/.local/bin` must be on your `PATH` for the `awdl` command (or run `./awdl` from here). Re-run
`install.sh` after pulling changes to the guard.

## Uninstall

```bash
sudo ./install.sh --uninstall   # stops and removes the guard, brings awdl0 back up
```

## Files

| File | Installed as |
|---|---|
| `awdl-guard` | `/usr/local/libexec/awdl-guard` (root:wheel 755) |
| `io.github.the-dsvolk.awdl-guard.plist.in` | `/Library/LaunchDaemons/io.github.the-dsvolk.awdl-guard.plist` |
| `awdl` | symlink `~/.local/bin/awdl` → this folder |
| `install.sh`, `test.sh` | — |
