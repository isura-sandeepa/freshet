# Security policy

## Supported versions

Security fixes go into the newest release, so please check that you're up to date before reporting.

| Version | Supported |
| --- | --- |
| 0.1.x (newest) | Yes |

## Reporting a problem

Please report security problems privately, not in a public issue:

1. Open the repository's **Security** tab and click **Report a vulnerability**
   ([direct link](https://github.com/isura-sandeepa/freshet/security/advisories/new)).
2. Describe the problem, what an attacker could do with it, and how to reproduce it. Include your Freshet
   and macOS versions, and a proof of concept if you have one.

Only you and the maintainer can see the report. Freshet is maintained by one person in their own time,
so a reply can take a few days. You'll hear back once the report has been looked at, and again when a
fix is released. If you'd like to be credited in the release notes, say so in the report.

## Scope

In scope is Freshet's own code: for example how it handles .torrent files, magnet links, torrent URLs,
RSS feeds, the watch folder, the "run a program" option and the files it saves.

Problems in libtorrent itself should also go to the [libtorrent project](https://github.com/arvidn/libtorrent).
Please tell us as well, so the copy built into Freshet can be updated.

Out of scope are the contents of torrents people choose to download, and attacks that need someone to
already control the Mac or the user's account.

## Checking a download

The notes for each release list the SHA-256 of its zip. To check yours, run this in Terminal and compare
the result:

```sh
shasum -a 256 ~/Downloads/Freshet-0.1.0-arm64.zip
```

Freshet's builds aren't notarized by Apple yet, so macOS asks you to confirm the first launch. The
release notes explain how.
