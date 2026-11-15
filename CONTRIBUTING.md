# Contributing to Freshet

Thanks for helping. Bug reports, fixes, accessibility improvements and clearer documentation are the most
useful contributions. For anything bigger than a small fix, please open an issue first, so we can agree
on the approach before you spend time on it.

## Before you start

- Search the [issues](https://github.com/isura-sandeepa/freshet/issues) to see whether someone has
  already reported or suggested it.
- Security problems don't go in issues: see [SECURITY.md](SECURITY.md).
- Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## What Freshet won't include

Freshet is a client for sharing files that people have the right to share. To keep it that way, it won't
add:

- built-in search of torrent sites, content recommendations, or bundled links to content;
- ads, bundled offers, accounts, analytics or any other tracking;
- support for Intel Macs (Freshet runs on Apple silicon only).

## Build and run

You need an Apple silicon Mac with macOS 14 or later, Xcode or the Command Line Tools (Swift 5.10 or
later), and Homebrew:

```sh
brew install boost openssl@3
git clone https://github.com/isura-sandeepa/freshet.git
cd freshet
swift build                      # the first build compiles libtorrent: a few minutes
swift run Freshet --simulate     # the app against a simulated engine, no network
swift test                       # unit tests
bash Scripts/make-app.sh         # build/Freshet.app
```

The simulated engine is the easiest way to work on the interface: it fills the app with sample torrents
in every state, without touching the network.

For interface changes, run `touch .devloop/snapshots-on` before `swift test`. The tests then render the
main window, every settings pane and the main sheets, in light and dark, into `.devloop/snapshots/`, so
you can check them without clicking through the app.

The [README](README.md#layout) explains how the code is laid out.

## Making a change

- Keep each pull request to one change, and say what it fixes and why.
- Add or update tests in `Tests/` when you change behaviour in `FreshetCore` or the engine.
- **Interface:** use the tokens in `Sources/FreshetApp/Theme.swift` and the components in
  `Sources/FreshetApp/Style.swift`. Views don't use raw colours, fonts, corner radii or spacing.
- **Accessibility:** check light and dark appearance, Increase Contrast, Reduce Motion, keyboard-only use
  and VoiceOver. Every icon-only button needs a label and a tooltip, and no status is shown by colour
  alone. See [ACCESSIBILITY.md](ACCESSIBILITY.md).
- **Writing:** Mac title-style capitalisation for buttons and menu items, sentence case everywhere else,
  and labels that say what happens ("Add Feed", not "OK").
- **Third-party code** needs a licence compatible with MIT, and an entry in
  `Sources/FreshetApp/Resources/THIRD_PARTY_NOTICES.txt`.

## Licence

By contributing, you agree that your contribution is released under the project's
[MIT License](LICENSE).
