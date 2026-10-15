#!/bin/bash
# Screensaver loop, modeled on Omarchy's: runs inside a fullscreen Alacritty window and plays random
# terminaltexteffects (tte) animations of the branding logo (~/.config/plasmarchy/branding/screensaver.txt),
# colored with the active theme. Any key, click or mouse movement ends it.
#   screensaver.sh <logo.txt> <tte binary> <gradient colors...>
LOGO="$1"; TTE="$2"; shift 2
COLORS=("$@")

quit() {
    pkill -P $$ -x tte 2>/dev/null
    printf '\033[?1003l\033[?1006l\033[?25h'   # mouse reporting off, cursor on
    exit 0
}
trap quit INT TERM HUP QUIT

printf '\033[?25l\033[2J'                       # hide cursor, clear
printf '\033[?1003h\033[?1006h'                 # report every mouse movement -> arrives on stdin -> quit
stty -echo 2>/dev/null

effects=(beams binarypath blackhole bouncyballs bubbles burn colorshift crumble decrypt errorcorrect expand
         fireworks highlight laseretch matrix middleout orbittingvolley overflow pour print rain randomsequence
         rings scattered slice slide smoke spotlights spray swarm sweep thunderstorm unstable vhstape waves wipe)

# Ignore input that is already queued (the key press or mouse jitter that started us)
sleep 0.6; while read -r -t 0.05 -n 1000 _; do :; done

while true; do
    effect="${effects[RANDOM % ${#effects[@]}]}"
    "$TTE" -i "$LOGO" --frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas \
        --anchor-canvas c --anchor-text c --no-eol --no-restore-cursor \
        "$effect" --final-gradient-stops "${COLORS[@]}" --final-gradient-direction diagonal \
        </dev/null 2>/dev/null &
    tte_pid=$!
    while kill -0 "$tte_pid" 2>/dev/null; do
        if read -r -t 0.2 -n 1 _; then quit; fi
    done
    # Hold the finished logo a moment before the next effect
    for _ in $(seq 15); do read -r -t 0.2 -n 1 _ && quit; done
done
