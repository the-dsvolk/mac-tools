# mac-tools

Small macOS utilities. Each tool lives in its own folder with its own README and install script.

| Tool | What it does |
|---|---|
| [`awdl/`](awdl/) | Stops Wi-Fi latency spikes (and a ~40% download-speed loss) on a Mac by keeping AWDL (AirDrop / Continuity peer-to-peer Wi-Fi) off, with `awdl on [minutes]` when you need AirDrop. A root LaunchDaemon plus a no-sudo command. |

Tested on macOS 26. Shell scripts only target the stock `/bin/bash` 3.2.

License: [GPL-3.0](LICENSE).
