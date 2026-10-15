layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // scene size
    vec2 origin;      // top left of the logo
    vec2 cellSize;    // one ASCII cell
    float slotWidth;  // a glyph's slot in the atlas (wider than a cell: glyphs overlap a little)
    float cols;
    float rows;
    float t;          // 0..1 build-up, 1 standing, 1..2 dissolve
    float mode;       // 0 decrypt, 1 scatter, 2 fall, 3 sweep
    float shimmer;
    float noiseCount;
    vec4 fg;
    vec4 accent;
    vec4 c0;
    vec4 c1;
    vec4 c2;
    vec4 c3;
};
