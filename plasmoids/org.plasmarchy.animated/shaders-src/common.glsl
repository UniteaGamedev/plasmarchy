// hash without integers or sin() (works on GLSL 1.00 / 1.20 and stays stable for large inputs)
float rnd(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
