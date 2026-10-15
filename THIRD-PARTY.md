# Third-party components

| Component | Source | License | In this repository |
|---|---|---|---|
| Themes (`themes/*/colors.toml`, wallpapers, `preview.png`) | [Omarchy](https://github.com/basecamp/omarchy) – github.com/basecamp/omarchy @ 246f33a (2026-10-15) | MIT, © David Heinemeier Hansson – see `themes/LICENSE-omarchy` | yes |
| Theme palette format, screensaver idea | Omarchy | MIT | modeled after it |
| Panel Colorizer | [luisbocanegra/plasma-panel-colorizer](https://github.com/luisbocanegra/plasma-panel-colorizer) | GPL-3.0 | no – downloaded by the installer |
| Papirus icons | [PapirusDevelopmentTeam](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme) | GPL-3.0 | no – package `papirus-icon-theme` |
| whisper.cpp + Whisper models (speech recognition) | [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp), models by OpenAI | MIT | no – built/downloaded by `plasmarchy voice setup` |
| Piper (text-to-speech) | [rhasspy/piper](https://github.com/rhasspy/piper) | MIT | no – `plasmarchy voice setup` |
| Piper voices (Thorsten, Kerstin, Ramona, Ryan, Amy, Alba) | [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices) | per voice, see its model card | no – downloaded on selection |
| openWakeWord + bundled wake word models | [dscripka/openWakeWord](https://github.com/dscripka/openWakeWord) | Apache-2.0 (code); models CC BY-NC-SA 4.0 | no – installed when a wake word is chosen |
| Ollama + local model (default qwen3:4b) | [ollama/ollama](https://github.com/ollama/ollama), [Qwen](https://huggingface.co/Qwen) | MIT / Apache-2.0 | no – `plasmarchy llm setup` |
| terminaltexteffects (screensaver) | [ChrisBuilds/terminaltexteffects](https://github.com/ChrisBuilds/terminaltexteffects) | MIT | no – `plasmarchy screensaver setup` |
| Screensaver concept | Omarchy (`omarchy-cmd-screensaver`) | MIT | modeled after it |
| JetBrains Mono Nerd Font | [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts) | OFL-1.1 | no – package `ttf-jetbrains-mono-nerd` |

The rights to the wallpapers belong to their respective artists; they are passed on as in the Omarchy
project.
