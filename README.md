# Stretch Buddy 🍝🕎

A cute desktop buddy for Windows that nudges you to stretch, drink water, stand up and rest your
eyes while you sit at the computer. Animated characters act out each exercise, so you just copy them.

*Inspired by Claude's "Tony the Rigatoni" demo. Built with Claude Code.*

![Reminder](docs/reminder.png)

## What it does

- About **every 2 hours, at a slightly random time** (adjustable: ~1h / 1.5h / 2h / 3h). Not a nag.
- A short toast ("It's time to **stretch!**"), then a card with one exercise. The character demos it live.
- **Start** runs a countdown with a progress bar. **Snooze** brings it back in 5 minutes. Ignore it and it leaves quietly.
- 15 exercises: thoracic extension, chin tucks, neck stretch, shoulder rolls, seated twist, wrist & finger stretch,
  20-20-20 eye break, deep breaths, calf raises, stand up, walkaround, and water breaks.
- A small posture/water tip on every card.
- **Drag** the popup to any screen; it remembers the spot.
- **English and Hebrew** (right-to-left). More languages: add a block to `i18n.json`.
- **Tray icon**: remind me now, choose character, language, frequency, pause for an hour, reset position.

![Poses](docs/poses.png)

## The cast

Kits of characters. Pick one, a random one from a kit, or a surprise from everyone.

- **Hanukkah** (default): Sufganiya, Dreidel, Menorah
- **Israeli street food**: Falafel, Shawarma
- **Pasta**: Rigatoni, Penne, Farfalle, Ravioli, Spaghetti, Lasagna
- **Bakery** (example pack): Bagel, Pita

![Gallery](docs/gallery.png)

### Add your own characters

Like a WhatsApp sticker pack: drop a folder into `packs\` with a `pack.json` and either sticker
PNGs or simple vector shapes. Every character automatically gets arms, legs, blinking and all the
exercise animations. See [packs/README.md](packs/README.md).

## Install

Windows 10/11, nothing else needed (uses built-in PowerShell + WPF).

1. Download or clone this repo to a folder you'll keep.
2. Right-click `install.ps1` > **Run with PowerShell**
   (or: `powershell -ExecutionPolicy Bypass -File install.ps1`).
3. Find the rigatoni in your system tray (click the `^` arrow if it's hidden).

It starts with Windows from then on. To remove it, run `uninstall.ps1`.

## Files

| File | What |
|---|---|
| `rigatoni.ps1` | the reminder popup, the characters and their animations, the character gallery |
| `tray.ps1` | tray icon, timer and settings menu |
| `i18n.json` | all text (English, Hebrew) |
| `packs\` | extra character kits |
| `state.json` | your settings (created on first run, not in git) |

Preview any exercise/character: `powershell -File rigatoni.ps1 -Demo drink -Who 8 -Lang he`

## License

MIT
