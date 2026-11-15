# Accessibility

Freshet should work for everyone who uses a Mac, however they use it. Accessibility is part of how each
screen is designed and reviewed, not an extra.

## What Freshet supports

- **VoiceOver:** controls, rows and progress bars have labels and values, and icon-only buttons are
  named. Status is spoken as a word ("Downloading", "Seeding", "Error"), never only shown as a colour.
- **Keyboard:** the main commands are in the menu bar with keyboard shortcuts, and lists move with the
  arrow keys. The weekly scheduler works from the keyboard too: the arrow keys move between hours, Space
  sets one, Shift with an arrow key paints across, and 1 to 4 pick the mode.
- **Colour:** status and chart colours are chosen to stay distinct with the common kinds of colour
  blindness, and each status also has a word or a symbol. In speed charts, the upload line is dashed as
  well as coloured.
- **Increase Contrast and Reduce Motion:** outlines, tinted fills and progress bars get stronger with
  Increase Contrast, and animations are skipped with Reduce Motion.
- **Light and dark appearance**, following the system setting.

Freshet runs on macOS 14 or later on Macs with Apple silicon.

## Known limitations

- Freshet hasn't yet been tested end to end by people who use VoiceOver, Voice Control or Switch Control
  every day. Reports from anyone who does are especially welcome.
- Text sizes follow Freshet's own type scale and don't change with the system's text size settings.

## Reporting a barrier

If something in Freshet is hard or impossible to use with your setup, please
[open an accessibility report](https://github.com/isura-sandeepa/freshet/issues/new?template=accessibility.yml).
Say what you were trying to do, which assistive technology or settings you use, and what got in the way.
Barriers are treated as bugs.
