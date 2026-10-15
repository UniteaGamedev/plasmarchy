# Plasmarchy

**Der Look von [Omarchy](https://omarchy.org) – auf KDE Plasma 6 mit CachyOS / Arch.**
Freie Fenster, eine Arbeitsfläche pro Bildschirm, Windows-typische Tastenkürzel – aber mit Omarchys
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
| **11 Themes** | Osaka Jade, Tokyo Night, Catppuccin (+ Latte), Gruvbox, Kanagawa, Everforest, Nord, Rosé Pine, Matte Black, Ristretto – übernommen aus Omarchy |
| **Theme-Wechsel** | Karussell mit schrägen Vorschauen (←/→, Enter). Wechselt Farben aller Programme, Leiste, Fensterrahmen, Symbole (Papirus mit passender Ordnerfarbe), Hintergrund, Sperrbildschirm, Terminal – in ~0,3 s |
| **Theme Studio** | Eigene Themes anlegen, bearbeiten, löschen: alle 25 Farben mit Farbwähler, hell/dunkel, Ordnerfarbe, eigene Hintergrundbilder, Live-Vorschau. Mitgelieferte Themes bleiben unangetastet – Änderungen landen als eigene Kopie |
| **Obere Leiste** | Schlank, Uhr in JetBrainsMono Nerd Font, nur WLAN/Bluetooth/Lautstärke/Akku sichtbar, alle Symbole einfarbig in Theme-Farbe |
| **Dock** | Schwebend, abgerundet, Glas-Effekt, weicht Fenstern aus |
| **KI-Assistent** | Roboter-Symbol in der Leiste (oder Meta+Shift+A): Chat mit der verbundenen KI – Claude Code (nutzt dein Abo), Cursor, Codex, Gemini CLI oder ein lokales Modell (Ollama), automatisch erkannt. **Ausweich-Kette:** Ist eine KI am Limit, nicht angemeldet oder nicht erreichbar, antwortet automatisch die nächste – mit verständlichem Hinweis. Optional darf die KI Apps öffnen, das Theme und die Lautstärke ändern |
| **Mit dem PC sprechen** | **Meta+Shift+Leertaste** (einstellbar) oder ein optionales Weckwort startet ein Gespräch: zuhören bis zur Sprechpause, Antwort wird vorgelesen, danach ein paar Sekunden für Rückfragen. „Stopp“/„Danke“ oder erneutes Kürzel beendet. Mikrofon nur während des Gesprächs offen; Erkennung (whisper.cpp) und Stimme (Piper) laufen lokal |
| **Einstellungsseite** | Im Assistenten (Menü → Einstellungen): bevorzugte KI und Ausweich-Reihenfolge, lokales Modell, Aktionen am PC, Limit-Hinweise, Tastenkürzel, Mikrofon mit Pegeltest, Erkennungsmodell, Stimme mit Hörprobe, Weckwort |
| **Nutzungslimits** | Claude 5-Stunden- und Wochenlimit als Balken im Assistenten; Desktop-Benachrichtigung bei 20 % und 5 % Rest (einstellbar) |
| **Aufklappmenüs** | Eigener Plasma-Stil: WLAN, Bluetooth, Lautstärke, Kalender, Benachrichtigungen mit Rahmen in der Akzentfarbe des Themes |
| **Zentrale Suche** | Windows-Taste öffnet KRunner in der Bildschirmmitte |
| **Animationen** | Zoom beim Öffnen/Schließen, „Wunderlampe“ beim Minimieren, Blur, abgerundete Fensterecken (CachyOS) |
| **Screensaver** | Text in Blockschrift mit Effekten (Entschlüsseln, Matrix-Regen, Farbwelle) in Theme-Farben; startet nicht bei Videos/Spielen |
| **Aufgeräumte Systemeinstellungen** | Was Plasmarchy steuert (Globales Design, Farben, Plasma-Stil, Fensterdekoration, Symbole), wird dort ausgeblendet |

Die Oberfläche folgt der Systemsprache; Englisch und Deutsch sind enthalten.

## Bedienung

```
plasmarchy                    Theme-Auswahl
plasmarchy theme <name>       Theme direkt setzen (plasmarchy themes = Liste)
plasmarchy studio             Theme Studio
plasmarchy next-bg            Nächstes Hintergrundbild
plasmarchy screensaver        Screensaver starten
plasmarchy ask "Frage"        Den Assistenten im Terminal fragen
plasmarchy voice setup        Sprache einrichten (einmalig, ~650 MB)
plasmarchy llm setup          Lokales Modell (Ollama) als Ausweich-KI/offline einrichten
plasmarchy talk               Gespräch starten (= Tastenkürzel)
plasmarchy settings           Einstellungen des Assistenten (get | set KEY WERT)
plasmarchy ai-usage           KI-Nutzung und Limits im Terminal
plasmarchy layout             Leiste + Dock neu einrichten
plasmarchy restore            Look von vor Plasmarchy
```

Einstellungen: `~/.config/plasmarchy/` – eigene Themes (`themes/`), Screensaver (`screensaver.conf`),
Assistent, Limit-Hinweise und Sprache (`assistant.conf`), eigene Skripte bei Theme-Wechsel
(`hooks.d/`, bekommen den Theme-Namen als Argument).

### Eigenes Theme ohne Studio

Ein Theme ist ein Ordner in `~/.config/plasmarchy/themes/<name>/` mit:
- `colors.toml` – Omarchy-Format (`mode`, `accent`, `background`, `foreground`, …)
- `kde.conf` – `NAME="Anzeigename"` und `FOLDER_COLOR=teal` (Papirus-Ordnerfarbe)
- `backgrounds/` mit Bildern und/oder `backgrounds.list` mit Pfaden zu Bildern

### Übersetzungen

Ausgangssprache ist Englisch. Übersetzungen liegen in `lib/locale/<sprache>.json` als
`{"English text": "Übersetzung"}` – gemeinsam für Skripte, QML-Apps und Widget (der Installer erzeugt daraus
den gettext-Katalog fürs Widget). Für eine neue Sprache `de.json` kopieren und die Werte übersetzen.

## Voraussetzungen

KDE Plasma 6 (Wayland empfohlen) auf CachyOS oder Arch. Der Installer holt: `papirus-icon-theme`,
`ttf-jetbrains-mono-nerd`, `swayidle`, `imagemagick`, `qt6-declarative`, `qt6-imageformats`, `kimageformats`
und – nur auf CachyOS verfügbar – `kwin-effect-rounded-corners`. Dazu das Plasma-Widget
[Panel Colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer) (v8.0.0).

## Hinweise

- Die Claude-Limits fragt Plasmarchy wie `/usage` in Claude Code mit deinem lokalen Claude-Login bei
  Anthropic ab. Fragen an den Assistenten laufen über die jeweilige CLI und deren Konto.
- Die Cursor-Nutzung wird über eine inoffizielle Schnittstelle von cursor.com mit deinem lokalen
  Cursor-Login abgefragt (nur wenn angemeldet). Claude-Code-Daten bleiben lokal.
- Spracherkennung, Sprachausgabe und Weckwort laufen komplett auf deinem Rechner.
- Plasmarchy ist ein unabhängiges Projekt und nicht mit Omarchy, Basecamp oder KDE verbunden.

## Lizenz

MIT – siehe [LICENSE](LICENSE). Themes und Hintergründe stammen aus Omarchy (MIT), Details in
[THIRD-PARTY.md](THIRD-PARTY.md).
