# Freshet

A native BitTorrent client for macOS, built with SwiftUI and AppKit on top of
[libtorrent](https://www.libtorrent.org). It's meant for people who want the full set of power-user controls —
queueing, per-torrent limits, a weekly scheduler, a transfer cap, RSS automation and torrent creation — in an app
that looks and behaves like a Mac app.

## Install

Download `Freshet-<version>-arm64.zip` from the releases page, unzip it and drag **Freshet.app** to Applications.
Freshet needs an Apple Silicon Mac with macOS 14 or later.

Builds are not notarized yet, so the first time you open Freshet, Control-click it and choose **Open**, or allow it
in **System Settings › Privacy & Security**.

## Features

- **Adding torrents:** .torrent files, drag and drop, magnet links, URLs and info-hashes, with a sheet for the save
  folder, label, file selection, starting stopped and skipping the hash check. A watch folder adds .torrent files
  automatically, and Freshet can be the default app for magnet links and .torrent files.
- **Managing them:** start, pause, force start, re-check, update tracker, queue order, labels, sidebar categories
  with counts, file priorities, Show in Finder, copy magnet link, save .torrent, set download location, and remove
  with or without moving the data to the Trash.
- **Details:** General, Files, Peers (with country flags), Trackers, Speed (live chart) and Logger tabs; sortable,
  hideable and reorderable columns.
- **Per-torrent properties:** trackers by tier, rate limits, peer and upload-slot limits, seeding goal, DHT /
  peer exchange / local discovery switches, initial seeding, sequential download and bandwidth priority.
- **Speed and scheduling:** global limits, an alternate upload rate when nothing is downloading, a 7 × 24 weekly
  scheduler (full speed, limited, seeding only, off), a transfer cap with a daily usage chart, and seeding goals by
  ratio and time.
- **Connection:** random listening port, UPnP and NAT-PMP, protocol encryption, SOCKS4/5 and HTTP proxies (password
  in the Keychain) with privacy switches, IP filter files, and interface and announce-IP settings.
- **Automation:** RSS and Atom feeds with filters (wildcards, exclusions, quality, episode ranges, a smart episode
  filter), running a program when a torrent finishes or changes state, and quitting, sleeping, shutting down or
  restarting when all downloads finish — with a cancellable countdown.
- **Creating torrents:** from a file or folder, with tiered trackers, web seeds, piece size, v1 / v2 / hybrid
  format and the private flag, hashed in the background, then seeded.
- **On the Mac:** menu bar speeds and controls, Dock menu and badge, notifications, Help with searchable topics, a
  Setup Guide, keeping the Mac awake while transferring, VoiceOver and keyboard support (including the scheduler
  grid), and banners in the main window when the transfer cap, the scheduler or a closed port stops transfers.

Freshet stores its data in `~/Library/Application Support/Freshet` (resume files in `Engine/resume`, labels in
`labels.json`).

## Build from source

You need an Apple Silicon Mac with macOS 14 or later, Xcode or the Command Line Tools (Swift 5.10 or later), and
Homebrew for Boost headers and OpenSSL:

```sh
brew install boost openssl@3
```

libtorrent itself (2.0.15) is vendored in `Vendor/libtorrent` and compiled as part of the package.

```sh
swift build                      # debug build (the first one compiles libtorrent: a few minutes)
swift run Freshet                # run without an app bundle
swift run Freshet --simulate     # run against the simulated engine (no network)
swift test                       # unit tests
bash Scripts/make-app.sh         # build/Freshet.app (release, ad-hoc signed)
bash Scripts/smoke.sh            # end-to-end: download, kill, resume (downloads part of Sintel to /tmp)
```

`touch .devloop/snapshots-on` makes `swift test` render the main window, every settings pane and the main sheets
into `.devloop/snapshots/` for review without clicking through the app.

## Layout

| Path | What lives there |
| --- | --- |
| `Vendor/libtorrent` | libtorrent-rasterbar 2.0.15 source, unmodified (see `VENDORED.md`), built as a static library |
| `Sources/LTShim` | C API over libtorrent's C++ API (`ltshim.h`, `ltshim.cpp`). No C++ crosses into Swift. |
| `Sources/FreshetEngine` | `LibtorrentEngine`, a Swift actor that polls libtorrent and saves resume data; torrent creation |
| `Sources/FreshetCore` | Models, the `EngineService` protocol, formatting, filtering, sorting, RSS and scheduling logic (pure Swift) |
| `Sources/FreshetSim` | `SimulatedEngine`, a deterministic fake engine for UI work and tests |
| `Sources/FreshetApp` | The SwiftUI + AppKit app |
| `Sources/FreshetSmoke` | `freshet-smoke`, the command-line end-to-end check |
| `Tests` | Unit and snapshot tests (Swift Testing) |
| `Scripts` | App bundling (with `Info.plist` and `AppIcon.icns`), the country database builder and the smoke test |
| `Design` | `AppIcon.svg`, the source of the app icon |

## Third-party code and data

The full licence texts are in
[`Sources/FreshetApp/Resources/THIRD_PARTY_NOTICES.txt`](Sources/FreshetApp/Resources/THIRD_PARTY_NOTICES.txt),
which ships inside the app and opens from **Help › Third-Party Notices**.

- [libtorrent](https://github.com/arvidn/libtorrent) — BSD 3-clause, see `Vendor/libtorrent/LICENSE` and `COPYING`.
- [Boost](https://www.boost.org) headers — Boost Software License 1.0.
- [OpenSSL](https://www.openssl.org) — Apache License 2.0.
- [Onest](https://github.com/googlefonts/onest) typeface — SIL Open Font License 1.1.
- IP to Country Lite database by [DB-IP](https://db-ip.com) — CC BY 4.0, see
  `Sources/FreshetApp/Resources/DBIP-LICENSE.txt`.

## License

Freshet is released under the [MIT License](LICENSE). The third-party code and data it includes keep their own
licences, listed above.
