#!/bin/sh
# Compiles the wallpaper shaders (*.frag.in, *.vert.in) into Qt's .qsb format (needs qt6-shadertools).
# GLSL 1.00 / 1.20 too, because Qt picks those on OpenGL compatibility contexts.
cd "$(dirname "$0")" || exit 1
for f in *.frag.in *.vert.in; do
    out="../contents/shaders/${f%.in}.qsb"
    python3 -I -c '
import re, sys
s = open(sys.argv[1]).read()
print(re.sub(r"#include \"([^\"]+)\"", lambda m: open(m.group(1)).read(), s))' "$f" > /tmp/plasmarchy-shader."${f%.in}"
    /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$out" /tmp/plasmarchy-shader."${f%.in}" || exit 1
    rm -f /tmp/plasmarchy-shader."${f%.in}"
done
