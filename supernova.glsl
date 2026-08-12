// Ghostty Supernova — turn Claude Code context usage into a stellar evolution.
//
// Install in Ghostty:
//   custom-shader = /absolute/path/to/supernova.glsl
//   custom-shader-animation = true
//
// The companion token-mass.py command sends two OSC 12 cursor-color packets:
// a coarse absolute mass packet followed by a signed 0..100% fill packet.
// Ghostty exposes those as iPreviousCursorColor and iCurrentCursorColor.
// No files are rewritten and the shader never needs to reload.

// ------------------------------ tuning
const float WORK_AREA = 0.28;       // bottom fraction left visually untouched
const float GLOW_GAIN = 1.15;
const float STAR_SPEED = 0.22;
const float MIN_RADIUS = 0.025;     // screen-height units
const float MAX_RADIUS = 0.215;
const float NEUTRON_SPIN = 10.0;    // radians/sec for the polar beam axis
const float QUASAR_RPS = 600.0;     // physical accretion-flow revolutions/sec

// Set to 0..1 for a manual preview. -1 means live cursor-channel only.
#define TOKEN_LEVEL -1

const ivec3 LEVEL_BASE_HI = ivec3(0xF, 0xB, 0x0);
const ivec3 MASS_BASE_HI  = ivec3(0xE, 0xA, 0x1);

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise21(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 5; i++) {
        v += a * noise21(p);
        p = mat2(1.62, 1.17, -1.17, 1.62) * p + 2.31;
        a *= 0.48;
    }
    return v;
}

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

float levelFromBytes(ivec3 v) {
    ivec3 lo = v & 0xF;
    if ((v >> 4) != LEVEL_BASE_HI || lo.r != (lo.g ^ lo.b ^ 0x5)) return -1.0;
    int fill = (lo.g << 4) | lo.b;
    return fill > 250 ? -1.0 : float(fill) / 250.0;
}

float decodeLevel(vec3 cc) {
    vec3 c = clamp(cc, 0.0, 1.0);
    float result = levelFromBytes(ivec3(floor(c * 255.0 + 0.5)));
    if (result >= 0.0) return result;

    // Defensive fallback in case a renderer ever supplies linearized colors.
    vec3 srgb = mix(c * 12.92,
                    1.055 * pow(max(c, 1e-6), vec3(1.0 / 2.4)) - 0.055,
                    step(0.0031308, c));
    return levelFromBytes(ivec3(floor(clamp(srgb, 0.0, 1.0) * 255.0 + 0.5)));
}

float massFromBytes(ivec3 v) {
    if ((v >> 4) != MASS_BASE_HI) return -1.0;
    ivec3 lo = v & 0xF;
    return float((lo.r << 8) | (lo.g << 4) | lo.b); // thousands of tokens
}

float decodeMassK(vec3 cc) {
    vec3 c = clamp(cc, 0.0, 1.0);
    float result = massFromBytes(ivec3(floor(c * 255.0 + 0.5)));
    if (result >= 0.0) return result;
    vec3 srgb = mix(c * 12.92,
                    1.055 * pow(max(c, 1e-6), vec3(1.0 / 2.4)) - 0.055,
                    step(0.0031308, c));
    return massFromBytes(ivec3(floor(clamp(srgb, 0.0, 1.0) * 255.0 + 0.5)));
}

float liveLevel() {
    float current = decodeLevel(iCurrentCursorColor.rgb);
    return current >= 0.0 ? current : float(TOKEN_LEVEL);
}

// ------------------------------ tiny 3x5 bitmap font
// Codes 0..9 are digits; 10=M, 11=A, 12=S, 13=K.
int glyphRow(int code, int row) {
    if (code == 0) { if (row == 0 || row == 4) return 7; return 5; }
    if (code == 1) { if (row == 0) return 2; if (row == 4) return 7; return 6; }
    if (code == 2) { if (row == 0 || row == 2 || row == 4) return 7; return row == 1 ? 1 : 4; }
    if (code == 3) { if (row == 0 || row == 2 || row == 4) return 7; return 1; }
    if (code == 4) { if (row == 2) return 7; if (row < 2) return 5; return 1; }
    if (code == 5) { if (row == 0 || row == 2 || row == 4) return 7; return row == 1 ? 4 : 1; }
    if (code == 6) { if (row == 0 || row == 2 || row == 4) return 7; return row == 1 ? 4 : 5; }
    if (code == 7) { if (row == 0) return 7; return 1; }
    if (code == 8) { if (row == 0 || row == 2 || row == 4) return 7; return 5; }
    if (code == 9) { if (row == 0 || row == 2 || row == 4) return 7; return row == 3 ? 1 : 5; }
    if (code == 10) { return row == 0 ? 5 : (row == 1 || row == 2 ? 7 : 5); } // M
    if (code == 11) { return row == 0 ? 2 : (row == 2 ? 7 : 5); }              // A
    if (code == 12) { if (row == 0 || row == 2 || row == 4) return 7; return row == 1 ? 4 : 1; } // S
    if (code == 13) { if (row == 0 || row == 4) return 5; if (row == 2) return 4; return 6; } // K
    return 0;
}

float glyph3x5(vec2 q, int code) {
    if (q.x < 0.0 || q.x >= 3.0 || q.y < 0.0 || q.y >= 5.0) return 0.0;
    int col = int(floor(q.x));
    int row = int(floor(q.y));
    int bits = glyphRow(code, row);
    int lit = (bits >> (2 - col)) & 1;
    if (lit == 0) return 0.0;
    vec2 cell = abs(fract(q) - 0.5);
    return 1.0 - smoothstep(0.33, 0.47, max(cell.x, cell.y));
}

float putGlyph(vec2 px, vec2 origin, float size, float column, int code) {
    return glyph3x5((px - origin) / size - vec2(column, 0.0), code);
}

vec2 massLabel(vec2 px, vec2 centerPx, float massK, float radiusPx, float verticalSide) {
    // Fixed pixel scale keeps the label equally legible in every stage,
    // including the physically tiny red dwarf and neutron star.
    float size = clamp(iResolution.y / 250.0, 2.80, 4.60);
    int mass = int(clamp(floor(massK + 0.5), 0.0, 4095.0));
    int digitCount = mass >= 1000 ? 4 : (mass >= 100 ? 3 : (mass >= 10 ? 2 : 1));
    float widthCells = 20.0 + 4.0 * float(digitCount);
    float labelGap = radiusPx + 16.0 + 1.0 * sin(iTime * 0.7);
    float originY = verticalSide > 0.0
        ? centerPx.y + labelGap
        : centerPx.y - labelGap - 5.0 * size;
    vec2 origin = vec2(centerPx.x - 0.5 * widthCells * size, originY);
    int d0 = (mass / 1000) % 10;
    int d1 = (mass / 100) % 10;
    int d2 = (mass / 10) % 10;
    int d3 = mass % 10;

    float ink = 0.0;
    ink += putGlyph(px, origin, size,  0.0, 10);
    ink += putGlyph(px, origin, size,  4.0, 11);
    ink += putGlyph(px, origin, size,  8.0, 12);
    ink += putGlyph(px, origin, size, 12.0, 12);
    float column = 17.0;
    if (digitCount == 4) { ink += putGlyph(px, origin, size, column, d0); column += 4.0; }
    if (digitCount >= 3) { ink += putGlyph(px, origin, size, column, d1); column += 4.0; }
    if (digitCount >= 2) { ink += putGlyph(px, origin, size, column, d2); column += 4.0; }
    ink += putGlyph(px, origin, size, column, d3);
    column += 4.0;
    ink += putGlyph(px, origin, size, column, 13);

    vec2 panelCenter = origin + vec2(widthCells * size * 0.5, 2.5 * size);
    vec2 panelHalf = vec2(widthCells * size * 0.5 + 6.0, 2.5 * size + 5.0);
    vec2 panelQ = abs(px - panelCenter) - panelHalf;
    float panelSdf = length(max(panelQ, 0.0)) + min(max(panelQ.x, panelQ.y), 0.0);
    float panel = 1.0 - smoothstep(-0.5, 1.5, panelSdf);
    return vec2(clamp(ink, 0.0, 1.0), panel);
}

vec3 phaseColor(float level) {
    if (level < 0.15) return vec3(0.88, 0.07, 0.025); // red dwarf
    if (level < 0.35) return vec3(1.00, 0.76, 0.30);  // main sequence
    if (level < 0.55) return vec3(0.46, 0.68, 1.00);  // blue giant
    if (level < 0.75) return vec3(1.00, 0.88, 0.46);  // hypergiant
    if (level < 0.90) return vec3(0.46, 0.84, 1.00);  // neutron star
    return vec3(0.68, 0.86, 1.00);                    // quasar
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;
    float level = liveLevel();
    vec4 terminal = texture(iChannel0, uv);
    if (level < 0.0) {
        fragColor = terminal;
        return;
    }

    level = clamp(level, 0.0, 1.0);
    float aspect = res.x / res.y;
    float growth = pow(level, 0.72);
    float radius = mix(MIN_RADIUS, MAX_RADIUS, growth);
    vec2 center = mix(vec2(0.89, 0.14), vec2(0.55, 0.34), smoothstep(0.05, 0.96, growth));
    center += vec2(0.010 * sin(iTime * 0.21), 0.008 * sin(iTime * 0.17 + 1.7)) * (0.25 + level);
    // Browser preview sets iMouse.z while a manual placement is active.
    // Stock Ghostty currently leaves iMouse unset, so its automatic orbit remains intact.
    if (iMouse.z > 0.5) center = iMouse.xy / res;
    // Keep the luminous body inside the viewport while still allowing it to
    // approach corners closely; the label independently flips toward the screen.
    float safeY = min(radius * 1.04 + 0.006, 0.48);
    float safeX = min(safeY / aspect, 0.48);
    center = clamp(center, vec2(safeX, safeY), vec2(1.0 - safeX, 1.0 - safeY));

    vec2 p = (uv - center) * vec2(aspect, 1.0);
    float d = length(p);
    float angle = atan(p.y, p.x);
    float yShield = iMouse.z > 0.5
        ? 1.0
        : smoothstep(WORK_AREA, WORK_AREA + 0.10, 1.0 - uv.y);

    // Stage changes are intentional hard cuts: no crossfade or morphing.
    float hypergiant = step(0.55, level) * (1.0 - step(0.75, level));
    float neutron = step(0.75, level) * (1.0 - step(0.90, level));
    float activeNucleus = step(0.90, level);
    float quasar = step(0.90, level);

    // Approximate lensing in the black-hole and quasar phases.
    vec2 sampleUV = uv;
    if (activeNucleus > 0.0) {
        float lensRadius = radius * mix(1.0, 1.55, quasar);
        float lens = activeNucleus * exp(-pow(d / max(lensRadius * 2.6, 1e-4), 2.0));
        vec2 dir = p / max(d, 1e-5);
        vec2 warpedP = p + dir * lens * radius * 0.20 / max(d / radius, 0.35);
        sampleUV = center + warpedP / vec2(aspect, 1.0);
        terminal = texture(iChannel0, clamp(sampleUV, 0.0, 1.0));
    }

    vec3 color = terminal.rgb;
    vec3 starColor = phaseColor(level);

    // Sparse, restrained background stars make the object feel embedded in
    // space while bright terminal glyphs remain untouched.
    vec2 starCell = floor(fragCoord / 22.0);
    vec2 starLocal = abs(fract(fragCoord / 22.0) - 0.5);
    float starSeed = hash21(starCell);
    float starPoint = (1.0 - smoothstep(0.025, 0.105, length(starLocal))) *
                      step(0.955, starSeed);
    float starTwinkle = 0.55 + 0.45 * sin(iTime * (1.2 + starSeed * 2.3) + starSeed * 31.0);
    float terminalInk = smoothstep(0.16, 0.48, max(terminal.r, max(terminal.g, terminal.b)));
    color += vec3(0.46, 0.66, 1.00) * starPoint * starTwinkle *
             (1.0 - terminalInk) * yShield * (0.10 + 0.22 * level);

    // Ordinary stellar sphere, used through the hypergiant phase.
    float normalStar = 1.0 - step(0.75, level);
    float surfaceNoise = fbm(rot(iTime * STAR_SPEED) * p / max(radius, 1e-4) * 4.0 + 8.0);
    float limb = sqrt(clamp(1.0 - (d * d) / max(radius * radius, 1e-5), 0.0, 1.0));
    float sphere = 1.0 - smoothstep(radius * 0.965, radius, d);
    vec3 surface = starColor * (0.48 + 0.75 * limb + 0.42 * surfaceNoise);
    surface += vec3(1.0, 0.82, 0.55) * pow(max(limb, 0.0), 7.0) * 0.55;
    color = mix(color, surface, sphere * normalStar * yShield);

    // Corona grows increasingly unstable with mass.
    float rayNoise = 0.55 + 0.45 * sin(angle * mix(13.0, 37.0, level) + iTime * (0.7 + level));
    float corona = exp(-max(d - radius, 0.0) / max(radius * mix(0.22, 0.72, level), 1e-4));
    corona *= (0.45 + 0.55 * pow(abs(rayNoise), 3.0));
    corona *= 1.0 - sphere;
    color += starColor * corona * normalStar * yShield * GLOW_GAIN * (0.45 + 0.75 * level);

    // Long diffraction-like crown rays intensify with stellar mass.
    float crownPattern = pow(0.5 + 0.5 * cos(angle * (10.0 + 8.0 * level) - iTime * 0.45), 12.0);
    float crown = crownPattern * exp(-max(d - radius, 0.0) /
                  max(radius * (0.65 + level * 0.85), 1e-4)) * (1.0 - sphere);
    color += yShield * normalStar * starColor * crown * (0.18 + 0.72 * level);

    // Hypergiant: two clean, concentric stellar-wind halos.
    float windShellA = exp(-pow((d - radius * 1.38) / max(radius * 0.055, 1e-4), 2.0));
    float windShellB = exp(-pow((d - radius * 1.78) / max(radius * 0.075, 1e-4), 2.0));
    color += yShield * hypergiant * vec3(1.00, 0.62, 0.12) *
             (windShellA * 0.78 + windShellB * 0.44);

    // Neutron star: compact layered core and rotating polar laser beams.
    if (neutron > 0.0) {
        float coreR = radius * 0.18;
        float core = exp(-pow(d / max(coreR, 1e-4), 3.2));
        float crust = exp(-pow((d - coreR * 0.92) / max(coreR * 0.10, 1e-4), 2.0));
        vec2 bp = rot(iTime * NEUTRON_SPIN + 0.22) * p;
        float beamCore = exp(-pow(abs(bp.y) / max(radius * 0.035, 1e-4), 2.0));
        float beamSheath = exp(-pow(abs(bp.y) / max(radius * 0.11, 1e-4), 2.0));
        float beamReach = smoothstep(radius * 0.07, radius * 0.38, abs(bp.x)) *
                          (1.0 - smoothstep(radius * 2.05, radius * 2.65, abs(bp.x)));
        float beam = (beamCore * 1.25 + beamSheath * 0.30) * beamReach;
        vec3 neutronColor = mix(vec3(0.22, 0.62, 1.00), vec3(0.86, 0.98, 1.00), core);
        color += yShield * neutron * (neutronColor * (core * 3.5 + crust * 1.6) +
                 vec3(0.36, 0.78, 1.00) * beam * 1.82);
    }

    // Quasar: an active black-hole engine, accretion disk and lensed photon ring.
    if (activeNucleus > 0.0) {
        float quasarRise = smoothstep(0.90, 1.00, level);
        float grandeur = 1.0 + 1.65 * quasarRise;
        vec2 diskP = rot(-0.22) * p;
        float diskD = length(vec2(diskP.x, diskP.y * 4.2));
        float holeR = radius * mix(0.34, 0.48, quasar);
        float diskBand = exp(-pow((diskD - holeR * 1.82) / max(holeR * 0.23, 1e-4), 2.0));
        float diskAngle = atan(diskP.y * 4.2, diskP.x);
        float physicalSpin = fract(iTime * QUASAR_RPS) * 6.28318530718;
        float spiralPhase = diskAngle * 5.0 - log(max(diskD / max(holeR, 1e-4), 0.22)) * 11.0;
        float spiral = 0.58 + 0.42 * pow(0.5 + 0.5 * sin(spiralPhase - physicalSpin), 5.0);
        float fastGrainA = sin(diskAngle * 23.0 - physicalSpin * 1.35 + surfaceNoise * 6.0);
        float fastGrainB = sin(diskAngle * 23.0 - physicalSpin * 1.35 + 0.82 + surfaceNoise * 6.0);
        float diskGrain = (0.68 + 0.16 * (fastGrainA + fastGrainB)) * spiral;
        float hotSide = 0.36 + 0.64 * smoothstep(-holeR * 2.1, holeR * 2.1, diskP.x);
        vec3 diskColor = mix(vec3(1.0, 0.055, 0.006), vec3(1.0, 0.94, 0.58), hotSide);
        float farDisk = diskBand * (1.0 - smoothstep(-holeR * 0.08, holeR * 0.08, diskP.y));
        float frontDisk = diskBand * smoothstep(-holeR * 0.08, holeR * 0.08, diskP.y);
        float shadow = 1.0 - smoothstep(holeR * 0.94, holeR, d);
        color += yShield * activeNucleus * diskColor * farDisk * diskGrain *
                 (1.45 + 2.25 * quasar) * grandeur;
        color = mix(color, vec3(0.0), shadow * activeNucleus * yShield);
        color += yShield * activeNucleus * diskColor * frontDisk * diskGrain *
                 (1.85 + 2.8 * quasar) * grandeur;
        float photon = exp(-pow((d - holeR * 1.045) / max(holeR * 0.038, 1e-4), 2.0));
        float photonBeaming = 0.62 + 0.38 * smoothstep(-0.9, 0.8, cos(angle + 0.22));
        color += yShield * activeNucleus * photon * photonBeaming *
                 vec3(1.0, 0.64, 0.20) * (2.05 + 2.4 * quasarRise);
        float innerHalo = exp(-pow((d - holeR * 1.18) / max(holeR * 0.20, 1e-4), 2.0));
        color += yShield * activeNucleus * innerHalo * vec3(0.40, 0.12, 0.025) * 0.32;
        float outerDisk = exp(-pow((diskD - holeR * 2.38) / max(holeR * 0.34, 1e-4), 2.0));
        float orbitSparks = pow(0.5 + 0.5 * sin(diskAngle * 31.0 - physicalSpin * 1.7), 10.0);
        color += yShield * quasar * outerDisk *
                 mix(vec3(0.44, 0.18, 1.00), vec3(1.00, 0.48, 0.08), hotSide) *
                 (0.34 + orbitSparks * (0.82 + 1.25 * quasarRise)) * grandeur;

        // Quasar jets emerge from the active disk's poles with a blue sheath.
        vec2 jp = rot(-0.22) * p;
        float jetT = clamp(abs(jp.y) / max(radius * 3.4, 1e-4), 0.0, 1.0);
        float jetWidth = radius * mix(0.125, 0.030, jetT) * (1.0 + 0.34 * quasarRise);
        float jetCore = exp(-pow(abs(jp.x) / max(jetWidth * 0.42, 1e-4), 2.0));
        float jetSheath = exp(-pow(abs(jp.x) / max(jetWidth, 1e-4), 2.0));
        float jetReach = smoothstep(holeR * 0.82, holeR * 1.04, abs(jp.y)) *
                         (1.0 - smoothstep(radius * 2.9, radius * 3.75, abs(jp.y)));
        float jetFlow = abs(jp.y) * 34.0 / max(radius, 1e-4) - iTime * (11.0 + 9.0 * quasarRise);
        float knots = 0.62 + 0.38 * pow(0.5 + 0.5 * sin(jetFlow), 3.0);
        float shockDiamonds = pow(0.5 + 0.5 * cos(jetFlow * 0.52), 16.0);
        vec3 jetColor = vec3(0.22, 0.48, 1.00) * jetSheath * (1.35 + 0.75 * quasarRise) +
                        vec3(0.92, 0.98, 1.00) * jetCore * (2.85 + 3.2 * quasarRise);
        color += yShield * quasar * jetColor * jetReach * (knots + shockDiamonds * 0.85);
        float jetCocoon = exp(-pow(abs(jp.x) / max(jetWidth * 2.8, 1e-4), 2.0)) * jetReach;
        color += yShield * quasar * jetCocoon *
                 mix(vec3(0.12, 0.20, 0.78), vec3(0.42, 0.18, 1.00), jetT) *
                 (0.44 + 0.72 * quasarRise);
        float polarNozzle = exp(-pow(abs(jp.x) / max(radius * 0.045, 1e-4), 2.0)) *
                            exp(-pow((abs(jp.y) - holeR * 1.08) /
                                max(holeR * 0.13, 1e-4), 2.0));
        color += yShield * quasar * polarNozzle * vec3(0.78, 0.93, 1.00) *
                 (1.8 + 2.2 * quasarRise);
    }

    // A restrained glow over empty areas, never over the protected prompt band.
    float halo = exp(-d / max(radius * mix(1.5, 2.7, level), 1e-4));
    float bloom = exp(-pow(d / max(radius * mix(1.15, 1.85, level), 1e-4), 1.55));
    color += yShield * starColor * (halo * 0.13 + bloom * 0.08) * (1.0 + level);

    // Absolute context mass. The mass packet usually lives in previous color;
    // after a cursor move, fall back to the normalized value until refreshed.
    float massK = decodeMassK(iPreviousCursorColor.rgb);
    if (massK < 0.0) massK = level * 200.0;
    vec2 labelCenter = center * res;
    float labelSide = center.x < 0.5 ? 1.0 : -1.0;
    labelCenter.x += labelSide * quasar * (radius * res.y * 1.30 + 64.0);
    float labelMargin = min(74.0, res.x * 0.45);
    labelCenter.x = clamp(labelCenter.x, labelMargin, res.x - labelMargin);
    float labelVerticalSide = center.y < 0.5 ? 1.0 : -1.0;
    vec2 label = massLabel(fragCoord, labelCenter, massK, radius * res.y, labelVerticalSide);
    color = mix(color, vec3(0.003, 0.006, 0.012), label.y * yShield * 0.97);
    vec3 labelColor = vec3(0.96, 0.985, 1.00);
    color = mix(color, labelColor, label.x * yShield);

    // Gentle filmic compression; terminal text remains close to its source.
    vec3 excess = max(color - 1.0, 0.0);
    color = min(color, 1.0) + excess / (1.0 + excess);
    fragColor = vec4(color, terminal.a);
}
