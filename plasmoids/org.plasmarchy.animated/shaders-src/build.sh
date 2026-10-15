#!/bin/sh
# Compiles the wallpaper shaders (*.frag.in) into Qt's .qsb format (needs qt6-shadertools).
# GLSL 1.00 / 1.20 too, because Qt picks those on OpenGL compatibility contexts.
cd "$(dirname "$0")" || exit 1
for f in *.frag.in; do
    out="../contents/shaders/${f%.in}.qsb"
    python3 -I -c 'import sys; s=open(sys.argv[1]).read(); print(s.replace("#include \"common.glsl\"", open("common.glsl").read()))' "$f" > /tmp/plasmarchy-shader.frag
    /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$out" /tmp/plasmarchy-shader.frag || exit 1
done
rm -f /tmp/plasmarchy-shader.frag
