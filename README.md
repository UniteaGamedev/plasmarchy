# Plasmarchy

**The look of [Omarchy](https://omarchy.org) – on KDE Plasma 6 with CachyOS / Arch.**
Floating windows, one workspace per screen, Windows-style shortcuts – but with Omarchy's themes, a theme
carousel, a clean top bar, a rounded dock, a screensaver and an AI assistant.

[Deutsch](README.de.md)

## Installation

```bash
git clone https://github.com/UniteaGamedev/plasmarchy.git
cd plasmarchy
./install.sh
```

The installer asks once for the sudo password (for packages), backs up every KDE setting it touches and then
sets everything up. **Undo:** `./uninstall.sh` restores the previous state.

Options: `--no-layout` (don't touch the panels/dock), `--no-packages` (no packages, e.g. for updates).
**Update:** `git pull && ./install.sh --no-packages`

## What you get

| | |
|---|---|
| **11 themes** | Osaka Jade, Tokyo Night, Catppuccin (+ Latte), Gruvbox, Kanagawa, Everforest, Nord, Rosé Pine, Matte Black, Ristretto – taken from Omarchy |
| **Theme switcher** | Carousel with slanted previews (←/→, Enter). Switches the colors of all apps, the panel, window borders, icons (Papirus with a matching folder color), wallpaper, lock screen and terminal – in ~0.3 s |
| **Theme Studio** | Create, edit and delete your own themes: all 25 colors with a color picker, light/dark, folder color, your own wallpapers, live preview. Built-in themes stay untouched – changes are saved as your own copy |
| **Top bar** | Slim, clock in JetBrainsMono Nerd Font, only Wi-Fi/Bluetooth/volume/battery visible, all icons monochrome in the theme color |
| **Dock** | Floating, rounded, glass effect, dodges windows |
| **AI assistant** | Robot icon in the panel (or Meta+Shift+A): chat with the connected AI – Claude Code (uses your subscription), Cursor, Codex, Gemini CLI or a local model (Ollama), detected automatically. **Fallback chain:** if an AI hits its limit, is signed out or can't be reached, the next one answers automatically – with a clear notice. Optionally the AI may open apps and change the theme and volume |
| **Talk to your computer** | **Meta+Shift+Space** (configurable) or an optional wake word starts a conversation: it listens until you pause, reads the answer aloud and then listens a few more seconds for follow-ups. Saying "stop"/"thanks" or pressing the hotkey again ends it. The microphone is only open during a conversation; recognition (whisper.cpp) and voice (Piper) run locally |
| **Settings page** | In the assistant (menu → Settings): preferred AI and fallback order, local model, desktop actions, limit alerts, hotkey, microphone with level test, recognition model, voice with preview, wake word |
| **Usage limits** | Claude's 5-hour and weekly limits as bars in the assistant; desktop notification when 20 % and 5 % are left (configurable) |
| **Popups** | Custom Plasma style: Wi-Fi, Bluetooth, volume, calendar and notifications with a border in the theme's accent color |
| **Centered search** | The Windows key opens KRunner in the middle of the screen |
| **Animations** | Zoom on open/close, "magic lamp" on minimize, blur, rounded window corners (CachyOS) |
| **Screensaver** | Block-letter text with effects (decrypt, matrix rain, color wave) in theme colors; doesn't start during videos/games |
| **Tidy System Settings** | Pages Plasmarchy controls (Global Theme, Colors, Plasma Style, Window Decorations, Icons) are hidden there |

The interface follows the system language; English and German are included.

## Usage

```
plasmarchy                    theme picker
plasmarchy theme <name>       set a theme directly (plasmarchy themes = list)
plasmarchy studio             Theme Studio
plasmarchy next-bg            next wallpaper
plasmarchy screensaver        start the screensaver
plasmarchy ask "question"     ask the assistant in the terminal
plasmarchy voice setup        set up voice (one time, ~650 MB)
plasmarchy llm setup          set up a local model (Ollama) as fallback/offline AI
plasmarchy talk               start a conversation (= the talk hotkey)
plasmarchy settings           assistant settings (get | set KEY VALUE)
plasmarchy ai-usage           AI usage and limits in the terminal
plasmarchy layout             set up the top bar + dock again
plasmarchy restore            the look from before Plasmarchy
```

Configuration: `~/.config/plasmarchy/` – your own themes (`themes/`), screensaver (`screensaver.conf`),
assistant, limit alerts and voice (`assistant.conf`), your own scripts run on theme switches
(`hooks.d/`, they get the theme name as argument).

### Your own theme without the Studio

A theme is a folder `~/.config/plasmarchy/themes/<name>/` with:
- `colors.toml` – Omarchy format (`mode`, `accent`, `background`, `foreground`, …)
- `kde.conf` – `NAME="Display name"` and `FOLDER_COLOR=teal` (Papirus folder color)
- `backgrounds/` with images and/or `backgrounds.list` with paths to images

### Translations

English is the source language. Translations live in `lib/locale/<lang>.json` as
`{"English text": "Translation"}` – shared by the scripts, the QML apps and the widget (the installer
compiles them into a gettext catalog for the widget). To add a language, copy `de.json` and translate the
values.

## Requirements

KDE Plasma 6 (Wayland recommended) on CachyOS or Arch. The installer fetches `papirus-icon-theme`,
`ttf-jetbrains-mono-nerd`, `swayidle`, `imagemagick`, `qt6-declarative`, `qt6-imageformats`, `kimageformats`
and – only available on CachyOS – `kwin-effect-rounded-corners`, plus the Plasma widget
[Panel Colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer) (v8.0.0).

## Notes

- Plasmarchy reads the Claude limits from Anthropic with your local Claude login, like `/usage` in Claude
  Code does. Questions to the assistant go through the respective CLI and its account.
- Cursor usage is read from an unofficial cursor.com endpoint with your local Cursor login (only when signed
  in). Claude Code data stays local.
- Speech recognition, voice output and the wake word run entirely on your computer.
- Plasmarchy is an independent project and not affiliated with Omarchy, Basecamp or KDE.

## License

MIT – see [LICENSE](LICENSE). Themes and wallpapers come from Omarchy (MIT); details in
[THIRD-PARTY.md](THIRD-PARTY.md).
