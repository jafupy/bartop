# bartop

A native macOS resource monitor with a btop-style dashboard. No dependencies beyond the Apple SDK.

The whole menu bar item has two lines: **CPU above, GPU below**, with a shared divider, live percentages, and five braille characters each. Each character holds two graph columns, giving ten one-second samples per row. New samples enter at the right and move left (←). CPU grows up from the divider; GPU grows down.

Every graph uses braille. CPU/GPU and upload/download history each use three rows per half, with labels occupying the outermost rows and a small gap in the middle. Core rows fill downward, then across columns: `C0 15% 30°C ⣀⣀⣀⣀⣀`. Click anywhere on the CPU cores row to expand it.

Processes is collapsible and groups helper processes under their owning app, summing CPU, GPU, and memory. Expand an app to see its individual processes. Filter by app, process name, or PID, or click CPU/GPU/Memory to sort. Pause freezes monitoring. Right-click the item for pause and quit.

The entire app is monochrome, with large braille dots and automatic macOS tinting. The dashboard follows serverBar's flat layout: plain sections, dividers, a compact footer, and automatic content sizing. Native text and controls follow the Mac's light or dark appearance. Sizes and rates use decimal units: 1 KB = 1,000 B, 1 MB = 1,000 KB, and 1 GB = 1,000 MB.

The dashboard lives in a native macOS menu, using the same system glass material as CodexBar. There is no extra background layer. Expanding or collapsing sections resizes the menu to its content.

## Build and run

Requires macOS 13+ and Xcode or its command line tools.

```sh
./scripts/build.sh
open dist/bartop.app
```

For development, use `swift run bartop --show`. To print a live sample, use `swift run bartop --sample`.

To render the dashboard and menu item with ten seconds of real history, use `swift run bartop --render dist/preview`.

GPU usage comes from the driver's IOKit performance counter. Unsupported drivers show “unavailable”. With multiple GPUs, the displayed usage is the busiest device. Process CPU uses 100% per core, so a process can exceed 100%. RAM counts active, wired, and compressed pages; it may differ from Activity Monitor. Network totals physical Ethernet/Wi-Fi interfaces to avoid counting VPN traffic twice. Process details are sampled only while the dashboard is open; its first sample establishes the CPU baseline.

Process GPU usage uses the Apple GPU driver's cumulative execution-time counters, measured against wall time. Overlapping work can exceed 100%; this differs from the global device utilization. Missing counters show “—”. These driver properties are not a documented stable API.

M5 core temperatures use read-only SMC sensor keys mapped by CPU cluster, following Stats' sensor mapping. Apple does not document the sensor locations. Unsupported models or missing sensors show “—°C”.

The built app is locally ad-hoc signed. To start at login, add it in System Settings → General → Login Items.

## License

Copyright (C) 2026 Jacob. Licensed under the [GNU General Public License v3.0](LICENSE) (GPL-3.0-only).
