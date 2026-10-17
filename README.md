# Plasmarchy

**The look of [Omarchy](https://omarchy.org), on KDE Plasma 6 with CachyOS / Arch.**
Floating windows, one workspace per screen, Windows-style shortcuts, but with Omarchy's themes, a theme
carousel, a clean top bar, a rounded dock, a screensaver and an AI assistant.

[Deutsch](README.de.md)

## Installation

```bash
git clone https://github.com/UniteaGamedev/plasmarchy.git
cd plasmarchy
./install.sh
```

The installer asks for the sudo password (for packages and the login screen), backs up every KDE setting it touches and then
sets everything up. **Undo:** `./uninstall.sh` restores the previous state.

Options: `--no-layout` (don't touch the panels/dock), `--no-packages` (no packages, e.g. for updates),
`--no-login-screen` (leave the login screen alone).
**Update:** `git pull && ./install.sh --no-packages`

## What you get

| | |
|---|---|
| **Themes** | 8 core themes: Osaka Jade, Tokyo Night, Catppuccin Latte, Everforest, Nord, Rosé Pine, Matte Black (from Omarchy) and Cachy Matrix (animated digital rain, with a greeting from Morpheus). Plus a **theme catalog** (Theme Studio → More themes) with more themes to install, e.g. Catppuccin, Gruvbox, Kanagawa, Ristretto, Neon Drift, Ember. Any theme can be removed and comes back from the catalog |
| **Menu** | The Windows key opens an Omarchy-style menu: Apps, Learn, Toggle, Style, Capture, Setup, AI assistant, Software, About, System. Type to search all entries and apps (with KRunner as fallback), arrow keys to navigate |
| **Animated wallpapers** | Aurora, particles, Matrix-style code rain or a logo animation in the theme's colors. Your logo glows, builds itself up like in the screensaver, or stays hidden. Pauses automatically while a maximized or fullscreen window covers the desktop. Any theme can be animated |
| **Theme switcher** | Carousel with slanted previews (←/→, Enter). Switches the colors of all apps, the panel, window borders, icons (Papirus with a matching folder color), wallpaper, lock screen, login screen and terminal in ~0.3 s |
| **Theme Studio** | Create, edit and delete your own themes: all 25 colors with a color picker, light/dark, folder color, your own wallpapers, live preview. Built-in themes are read-only: apply them, or duplicate one to customize it |
| **Top bar** | Slim, clock in JetBrainsMono Nerd Font, only Wi-Fi/Bluetooth/volume/battery visible, all icons monochrome in the theme color |
| **Music player** | Top left, with audio wave, title and controls. Shows and controls whatever plays, in any app: Spotify, YouTube Music in the browser, VLC and every other player (MPRIS). Title and controls appear while something plays |
| **Dock** | Floating, rounded, glass effect, dodges windows |
| **AI assistant** | Robot icon in the system tray (or Meta+A, like Omarchy): chat with the connected AI: Claude Code (uses your subscription), Cursor, Codex, Gemini CLI or a local model (Ollama), detected automatically. **Fallback chain:** if an AI hits its limit, is signed out or can't be reached, the next one answers automatically, with a clear notice. Optionally the AI may open apps and change the theme and volume |
| **Talk to your computer** | **Meta+Shift+Space** (configurable) or an optional wake word starts a conversation: it listens until you pause (or press the hotkey again to send right away), reads the answer aloud and then listens a few more seconds for follow-ups. Saying "stop"/"thanks" ends it. The microphone is only open during a conversation; recognition (whisper.cpp, on the GPU when CUDA is available) and voice (Piper) run locally |
| **Settings page** | In the assistant (menu → Settings): preferred AI and fallback order, local model, desktop actions, limit alerts, hotkey, microphone with level test, recognition model, voice with preview, wake word |
| **Usage limits** | Claude's 5-hour and weekly limits as bars in the assistant; desktop notification when 20 % and 5 % are left (configurable) |
| **Popups** | Custom Plasma style: Wi-Fi, Bluetooth, volume, calendar and notifications with a border in the theme's accent color |
| **Settings** | System Settings → Appearance → **Plasmarchy**: theme, own wallpaper for every theme, animations and logo, menu style (Plasmarchy menu or classic KDE menu), fonts, music player, hot corner, screensaver |
| **Animations** | Zoom on open/close, "magic lamp" on minimize, blur, rounded window corners (CachyOS) |
| **Screensaver** | Like Omarchy's: your logo animated with random [terminaltexteffects](https://github.com/ChrisBuilds/terminaltexteffects) in a fullscreen terminal, in theme colors; doesn't start during videos/games |
| **Branding** | One logo for screensaver and animated wallpapers: a text, an image (SVG/PNG) or hand-edited ASCII art in `~/.config/plasmarchy/branding/` (Menu → Style, or `plasmarchy branding`) |
| **Tidy System Settings** | Pages Plasmarchy controls (Global Theme, Colors, Plasma Style, Window Decorations, Icons, KDE's Quick Settings) are hidden there |

The interface follows the system language. Translations for 20 languages are included (missing languages fall back to English).

## Usage

```
plasmarchy menu               the menu (Windows key)
plasmarchy                    theme picker
plasmarchy theme <name>       set a theme directly (plasmarchy themes = list)
plasmarchy studio             Theme Studio (catalog: plasmarchy studio catalog)
plasmarchy configure          Plasmarchy settings
plasmarchy themes available   theme catalog (install|remove <name>)
plasmarchy next-bg            next wallpaper
plasmarchy screensaver        start the screensaver
plasmarchy branding           show/change the logo (text "Name" | image <file> | edit)
plasmarchy toggle <feature>   player | animated | nightlight | idle
plasmarchy ask "question"     ask the assistant in the terminal
plasmarchy voice setup        set up voice (one time, ~650 MB)
plasmarchy llm setup          set up a local model (Ollama) as fallback/offline AI
plasmarchy talk               start a conversation (= the talk hotkey)
plasmarchy settings           assistant settings (get | set KEY VALUE)
plasmarchy ai-usage           AI usage and limits in the terminal
plasmarchy layout             set up the top bar + dock again
plasmarchy restore            the look from before Plasmarchy
```

Configuration in `~/.config/plasmarchy/`: your own themes (`themes/`), screensaver (`screensaver.conf`),
assistant, limit alerts and voice (`assistant.conf`), your own scripts run on theme switches
(`hooks.d/`, they get the theme name as argument).

### Your own theme without the Studio

A theme is a folder `~/.config/plasmarchy/themes/<name>/` with:
- `colors.toml`: Omarchy format (`mode`, `accent`, `background`, `foreground`, …)
- `kde.conf`: `NAME="Display name"` and `FOLDER_COLOR=teal` (Papirus folder color)
- `backgrounds/` with images and/or `backgrounds.list` with paths to images
- optional in `kde.conf`: `ANIMATION=aurora|particles|rain|logo` (animated wallpaper),
  `ANIMATION_COLORS="cyan blue magenta"` (palette colors the animation uses) and
  `GREETING_FROM`, `GREETING_TITLE`, `GREETING_TEXT` (a notification when switching to the theme)

To share a theme, add it to `extra-themes/` with a pull request and run `python3 tools/build_theme_index.py`.

### Translations

English is the source language. Translations live in `lib/locale/<lang>.json` as
`{"English text": "Translation"}`, shared by the scripts, the QML apps and the widget (the installer
compiles them into gettext catalogs for the widgets). Regional variants (`pt_BR.json`, `zh_TW.json`) build on the
general language. To add a language: copy `de.json` to `<lang>.json`, translate the values, then run
`python3 tools/i18n.py check <lang>` (finds missing entries) and `python3 tools/i18n.py sync` (menu entries).

## Requirements

KDE Plasma 6 (Wayland recommended) on CachyOS or Arch. The installer fetches `papirus-icon-theme`,
`ttf-jetbrains-mono-nerd`, `swayidle`, `alacritty`, `kdialog`, `imagemagick`, `qt6-declarative`, `qt6-imageformats`, `kimageformats`
and (only available on CachyOS) `kwin-effect-rounded-corners`, plus the Plasma widget
[Panel Colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer) (v8.0.0).

## Notes

- Plasmarchy reads the Claude limits from Anthropic with your local Claude login, like `/usage` in Claude
  Code does. Questions to the assistant go through the respective CLI and its account.
- Cursor usage is read from an unofficial cursor.com endpoint with your local Cursor login (only when signed
  in). Claude Code data stays local.
- Speech recognition, voice output and the wake word run entirely on your computer.
- Plasmarchy is an independent project and not affiliated with Omarchy, Basecamp or KDE.

## License

MIT, see [LICENSE](LICENSE). Themes and wallpapers come from Omarchy (MIT); details in
[THIRD-PARTY.md](THIRD-PARTY.md).
