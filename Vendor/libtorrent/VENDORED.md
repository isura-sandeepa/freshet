# Vendored: libtorrent-rasterbar 2.0.15

| | |
| --- | --- |
| Upstream | https://github.com/arvidn/libtorrent, tag `v2.0.15` (commit `1eb18faeae156d8dbbab42935c082f8b81f50989`) |
| Archive | https://github.com/arvidn/libtorrent/releases/download/v2.0.15/libtorrent-rasterbar-2.0.15.tar.gz |
| SHA-256 | `5e2e79129823b7ea48721164c32b5aaf83d3fd733b5502100f6705b29f27bb02` |
| Licence | BSD 3-clause, with third-party notices — see `LICENSE` and `COPYING`. `src/ed25519` is public domain, `deps/try_signal` is BSD 3-clause. |

## What is here

Copied unmodified from the release archive:

- `include/` — public headers
- `src/` — the library, including `src/kademlia/` (DHT) and `src/ed25519/`
- `deps/try_signal/*.cpp`, `*.hpp` — the try_signal submodule (commit `105cce59972f925a33aa6b1c3109e4cd3caf583d`)
- `LICENSE`, `COPYING`

Nothing else from the archive (bindings, tests, examples, tools, docs, build files) is included. `include/` and
`src/` were checked identical to the git tag.

## How it is built

`Package.swift` builds this folder as the static `libtorrent` target with the definitions upstream's CMake
build uses by default: OpenSSL (HTTPS trackers and web seeds, SSL torrents), encryption, DHT, logging,
deprecated APIs available. Boost is used header-only. Any target that includes libtorrent headers must use the
same definitions (`libtorrentConfiguration` in `Package.swift`).

## Updating

Download the new release, replace `include/`, `src/` and `deps/try_signal/` the same way, update this file,
then build and run `bash Scripts/smoke.sh`.
