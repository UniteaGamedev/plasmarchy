# Plasmarchy

**Der Look von [Omarchy](https://omarchy.org), auf KDE Plasma 6 mit CachyOS / Arch.**
Freie Fenster, eine Arbeitsfläche pro Bildschirm, Windows-typische Tastenkürzel, aber mit Omarchys
Themes, Theme-Karussell, schlanker Leiste, rundem Dock, Screensaver und KI-Assistent.

[English](README.md)

## Installation

```bash
git clone https://github.com/UniteaGamedev/plasmarchy.git
cd plasmarchy
./install.sh
```

Der Installer fragt einmal nach dem sudo-Passwort (für Pakete), sichert alle betroffenen KDE-Einstellungen
und richtet dann alles ein. **Rückgängig:** `./uninstall.sh` stellt den vorherigen Zustand wieder her.

Optionen: `--no-layout` (Leisten/Dock nicht anfassen), `--no-packages` (keine Pakete, z. B. für Updates).
**Update:** `git pull && ./install.sh --no-packages`

## Was du bekommst

| | |
|---|---|
| **Themes** | 8 Kern-Themes: Osaka Jade, Tokyo Night, Catppuccin Latte, Everforest, Nord, Rosé Pine, Matte Black (aus Omarchy) und Cachy Matrix (animierter Code-Regen, mit Gruß von Morpheus). Dazu ein **Theme-Katalog** (Theme Studio → Weitere Themes) mit weiteren Themes zum Installieren, z. B. Catppuccin, Gruvbox, Kanagawa, Ristretto, Neon Drift, Ember. Jedes Theme lässt sich entfernen und kommt über den Katalog zurück |
| **Menü** | Die Windows-Taste öffnet ein Menü im Omarchy-Stil: Apps, Lernen, Umschalten, Stil, Aufnehmen, Einrichten, KI-Assistent, Software, Über, System. Lostippen durchsucht alle Einträge und Apps (KRunner als Rückfall), Pfeiltasten navigieren |
| **Animierte Hintergründe** | Aurora, Partikel, Code-Regen wie in Matrix oder eine Logo-Animation in den Theme-Farben. Dein Logo leuchtet, baut sich auf wie im Screensaver oder bleibt ausgeblendet. Pausieren automatisch, solange ein maximiertes oder Vollbild-Fenster den Desktop verdeckt. Jedes Theme lässt sich animieren |
| **Theme-Wechsel** | Karussell mit schrägen Vorschauen (←/→, Enter). Wechselt Farben aller Programme, Leiste, Fensterrahmen, Symbole (Papirus mit passender Ordnerfarbe), Hintergrund, Sperrbildschirm und Terminal in ~0,3 s |
| **Theme Studio** | Eigene Themes anlegen, bearbeiten, löschen: alle 25 Farben mit Farbwähler, hell/dunkel, Ordnerfarbe, eigene Hintergrundbilder, Live-Vorschau. Mitgelieferte Themes sind schreibgeschützt: anwenden oder duplizieren und die Kopie anpassen |
| **Obere Leiste** | Schlank, Uhr in JetBrainsMono Nerd Font, nur WLAN/Bluetooth/Lautstärke/Akku sichtbar, alle Symbole einfarbig in Theme-Farbe |
| **Musik-Player** | Oben links, mit Audiowelle, Titel und Steuerung. Eingebaut: **YouTube Music** (Suche, endloses Radio, Cover; über mpv, ohne Browser oder App). Steuert auch jeden anderen Player (MPRIS), zum Beispiel Musik im Browser. Einrichtung direkt im Popup |
| **Dock** | Schwebend, abgerundet, Glas-Effekt, weicht Fenstern aus |
| **KI-Assistent** | Roboter-Symbol im System-Tray (oder Meta+A, wie bei Omarchy): Chat mit der verbundenen KI: Claude Code (nutzt dein Abo), Cursor, Codex, Gemini CLI oder ein lokales Modell (Ollama), automatisch erkannt. **Ausweich-Kette:** Ist eine KI am Limit, nicht angemeldet oder nicht erreichbar, antwortet automatisch die nächste, mit verständlichem Hinweis. Optional darf die KI Apps öffnen, das Theme und die Lautstärke ändern |
| **Mit dem PC sprechen** | **Meta+Shift+Leertaste** (einstellbar) oder ein optionales Weckwort startet ein Gespräch: zuhören bis zur Sprechpause (oder Kürzel nochmal drücken, um sofort abzusenden), Antwort wird vorgelesen, danach ein paar Sekunden für Rückfragen. „Stopp“/„Danke“ beendet. Mikrofon nur während des Gesprächs offen; Erkennung (whisper.cpp, mit CUDA auf der GPU) und Stimme (Piper) laufen lokal |
| **Einstellungsseite** | Im Assistenten (Menü → Einstellungen): bevorzugte KI und Ausweich-Reihenfolge, lokales Modell, Aktionen am PC, Limit-Hinweise, Tastenkürzel, Mikrofon mit Pegeltest, Erkennungsmodell, Stimme mit Hörprobe, Weckwort |
| **Nutzungslimits** | Claude 5-Stunden- und Wochenlimit als Balken im Assistenten; Desktop-Benachrichtigung bei 20 % und 5 % Rest (einstellbar) |
| **Aufklappmenüs** | Eigener Plasma-Stil: WLAN, Bluetooth, Lautstärke, Kalender, Benachrichtigungen mit Rahmen in der Akzentfarbe des Themes |
| **Einstellungen** | Systemeinstellungen → Erscheinungsbild → **Plasmarchy**: Theme, eigenes Hintergrundbild für alle Themes, Animationen und Logo, Menü-Stil (Plasmarchy-Menü oder klassisches KDE-Menü), Schriften, Musik-Player, aktive Ecke, Bildschirmschoner |
| **Animationen** | Zoom beim Öffnen/Schließen, „Wunderlampe“ beim Minimieren, Blur, abgerundete Fensterecken (CachyOS) |
| **Screensaver** | Wie bei Omarchy: dein Logo, animiert mit zufälligen [terminaltexteffects](https://github.com/ChrisBuilds/terminaltexteffects) in einem Vollbild-Terminal, in Theme-Farben; startet nicht bei Videos/Spielen |
| **Branding** | Ein Logo für Screensaver und animierte Hintergründe: Text, Bild (SVG/PNG) oder selbst bearbeitete ASCII-Grafik in `~/.config/plasmarchy/branding/` (Menü → Stil, oder `plasmarchy branding`) |
| **Aufgeräumte Systemeinstellungen** | Was Plasmarchy steuert (Globales Design, Farben, Plasma-Stil, Fensterdekoration, Symbole, KDEs Schnelleinstellungen), wird dort ausgeblendet |

Die Oberfläche folgt der Systemsprache. Übersetzungen für 20 Sprachen sind enthalten (fehlende Sprachen fallen auf Englisch zurück).

## Bedienung

```
plasmarchy menu               Menü (Windows-Taste)
plasmarchy                    Theme-Auswahl
plasmarchy theme <name>       Theme direkt setzen (plasmarchy themes = Liste)
plasmarchy studio             Theme Studio (Katalog: plasmarchy studio catalog)
plasmarchy configure          Plasmarchy-Einstellungen
plasmarchy themes available   Theme-Katalog (install|remove <name>)
plasmarchy music setup        eingebautes YouTube Music: nötige Pakete installieren
plasmarchy next-bg            Nächstes Hintergrundbild
plasmarchy screensaver        Screensaver starten
plasmarchy branding           Logo zeigen/ändern (text "Name" | image <datei> | edit)
plasmarchy toggle <funktion>  player | animated | nightlight | idle
plasmarchy ask "Frage"        Den Assistenten im Terminal fragen
plasmarchy voice setup        Sprache einrichten (einmalig, ~650 MB)
plasmarchy llm setup          Lokales Modell (Ollama) als Ausweich-KI/offline einrichten
plasmarchy talk               Gespräch starten (= Tastenkürzel)
plasmarchy settings           Einstellungen des Assistenten (get | set KEY WERT)
plasmarchy ai-usage           KI-Nutzung und Limits im Terminal
plasmarchy layout             Leiste + Dock neu einrichten
plasmarchy restore            Look von vor Plasmarchy
```

Einstellungen in `~/.config/plasmarchy/`: eigene Themes (`themes/`), Screensaver (`screensaver.conf`),
Assistent, Limit-Hinweise und Sprache (`assistant.conf`), eigene Skripte bei Theme-Wechsel
(`hooks.d/`, bekommen den Theme-Namen als Argument).

### Eigenes Theme ohne Studio

Ein Theme ist ein Ordner in `~/.config/plasmarchy/themes/<name>/` mit:
- `colors.toml`: Omarchy-Format (`mode`, `accent`, `background`, `foreground`, …)
- `kde.conf`: `NAME="Anzeigename"` und `FOLDER_COLOR=teal` (Papirus-Ordnerfarbe)
- `backgrounds/` mit Bildern und/oder `backgrounds.list` mit Pfaden zu Bildern
- optional in `kde.conf`: `ANIMATION=aurora|particles|rain|logo` (animierter Hintergrund),
  `ANIMATION_COLORS="cyan blue magenta"` (welche Palettenfarben die Animation nutzt) und
  `GREETING_FROM`, `GREETING_TITLE`, `GREETING_TEXT` (Benachrichtigung beim Wechsel zum Theme)

Ein Theme teilen: per Pull Request in `extra-themes/` ablegen und `python3 tools/build_theme_index.py` ausführen.

### Übersetzungen

Ausgangssprache ist Englisch. Übersetzungen liegen in `lib/locale/<sprache>.json` als
`{"English text": "Übersetzung"}`, gemeinsam für Skripte, QML-Apps und Widget (der Installer erzeugt daraus
die gettext-Kataloge für die Widgets). Regionale Varianten (`pt_BR.json`, `zh_TW.json`) bauen auf der allgemeinen
Sprache auf. Neue Sprache: `de.json` nach `<sprache>.json` kopieren, Werte übersetzen, dann
`python3 tools/i18n.py check <sprache>` (findet Lücken) und `python3 tools/i18n.py sync` (Menüeinträge).

## Voraussetzungen

KDE Plasma 6 (Wayland empfohlen) auf CachyOS oder Arch. Der Installer holt: `papirus-icon-theme`,
`ttf-jetbrains-mono-nerd`, `swayidle`, `alacritty`, `kdialog`, `imagemagick`, `qt6-declarative`, `qt6-imageformats`, `kimageformats`
und (nur auf CachyOS verfügbar) `kwin-effect-rounded-corners`. Dazu das Plasma-Widget
[Panel Colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer) (v8.0.0).

## Hinweise

- Die Claude-Limits fragt Plasmarchy wie `/usage` in Claude Code mit deinem lokalen Claude-Login bei
  Anthropic ab. Fragen an den Assistenten laufen über die jeweilige CLI und deren Konto.
- Die Cursor-Nutzung wird über eine inoffizielle Schnittstelle von cursor.com mit deinem lokalen
  Cursor-Login abgefragt (nur wenn angemeldet). Claude-Code-Daten bleiben lokal.
- Spracherkennung, Sprachausgabe und Weckwort laufen komplett auf deinem Rechner.
- Plasmarchy ist ein unabhängiges Projekt und nicht mit Omarchy, Basecamp oder KDE verbunden.

## Lizenz

MIT, siehe [LICENSE](LICENSE). Themes und Hintergründe stammen aus Omarchy (MIT), Details in
[THIRD-PARTY.md](THIRD-PARTY.md).
