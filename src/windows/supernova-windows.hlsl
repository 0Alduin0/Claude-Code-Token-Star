// Ghostty Supernova for Windows Terminal.
//
// This is the static template. token-mass-windows.ps1 prepends live TOKEN_*
// defines and writes supernova-windows.generated.hlsl. Windows Terminal loads
// the generated file through experimental.pixelShaderPath.

#ifndef TOKEN_LEVEL
#define TOKEN_LEVEL 0.0
#endif
#ifndef TOKEN_MASS_K
#define TOKEN_MASS_K 0.0
#endif
#ifndef TOKEN_ACTIVE
#define TOKEN_ACTIVE 0
#endif

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float Time;
    float Scale;
    float2 Resolution;
    float4 Background;
};

static const float WORK_AREA = 0.28;
static const float GLOW_GAIN = 1.15;
static const float STAR_SPEED = 0.22;
static const float MIN_RADIUS = 0.025;
static const float MAX_RADIUS = 0.215;
static const float NEUTRON_SPIN = 10.0;
static const float QUASAR_RPS = 600.0;
static const float TAU = 6.28318530718;

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float noise21(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float fbm(float2 p)
{
    float value = 0.0;
    float amplitude = 0.55;
    [unroll]
    for (int i = 0; i < 5; i++)
    {
        value += amplitude * noise21(p);
        p = mul(float2x2(1.62, 1.17, -1.17, 1.62), p) + 2.31;
        amplitude *= 0.48;
    }
    return value;
}

float2 rotate2(float2 p, float angle)
{
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

int glyphRow(int code, int row)
{
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
    if (code == 10) { return row == 0 ? 5 : (row == 1 || row == 2 ? 7 : 5); }
    if (code == 11) { return row == 0 ? 2 : (row == 2 ? 7 : 5); }
    if (code == 12) { if (row == 0 || row == 2 || row == 4) return 7; return row == 1 ? 4 : 1; }
    if (code == 13) { if (row == 0 || row == 4) return 5; if (row == 2) return 4; return 6; }
    return 0;
}

float glyph3x5(float2 q, int code)
{
    if (q.x < 0.0 || q.x >= 3.0 || q.y < 0.0 || q.y >= 5.0) return 0.0;
    int col = (int)floor(q.x);
    int row = (int)floor(q.y);
    int bits = glyphRow(code, row);
    int lit = (bits >> (2 - col)) & 1;
    if (lit == 0) return 0.0;
    float2 cell = abs(frac(q) - 0.5);
    return 1.0 - smoothstep(0.33, 0.47, max(cell.x, cell.y));
}

float putGlyph(float2 px, float2 origin, float size, float column, int code)
{
    return glyph3x5((px - origin) / size - float2(column, 0.0), code);
}

float2 massLabel(float2 px, float2 centerPx, float massK, float radiusPx, float verticalSide)
{
    float size = clamp(Resolution.y / 250.0, 2.80, 4.60);
    int mass = (int)clamp(floor(massK + 0.5), 0.0, 4095.0);
    int digitCount = mass >= 1000 ? 4 : (mass >= 100 ? 3 : (mass >= 10 ? 2 : 1));
    float widthCells = 20.0 + 4.0 * (float)digitCount;
    float labelGap = radiusPx + 16.0 + sin(Time * 0.7);
    float originY = verticalSide > 0.0
        ? centerPx.y + labelGap
        : centerPx.y - labelGap - 5.0 * size;
    float2 origin = float2(centerPx.x - 0.5 * widthCells * size, originY);
    int d0 = (mass / 1000) % 10;
    int d1 = (mass / 100) % 10;
    int d2 = (mass / 10) % 10;
    int d3 = mass % 10;

    float ink = 0.0;
    ink += putGlyph(px, origin, size, 0.0, 10);
    ink += putGlyph(px, origin, size, 4.0, 11);
    ink += putGlyph(px, origin, size, 8.0, 12);
    ink += putGlyph(px, origin, size, 12.0, 12);
    float column = 17.0;
    if (digitCount == 4) { ink += putGlyph(px, origin, size, column, d0); column += 4.0; }
    if (digitCount >= 3) { ink += putGlyph(px, origin, size, column, d1); column += 4.0; }
    if (digitCount >= 2) { ink += putGlyph(px, origin, size, column, d2); column += 4.0; }
    ink += putGlyph(px, origin, size, column, d3);
    column += 4.0;
    ink += putGlyph(px, origin, size, column, 13);

    float2 panelCenter = origin + float2(widthCells * size * 0.5, 2.5 * size);
    float2 panelHalf = float2(widthCells * size * 0.5 + 6.0, 2.5 * size + 5.0);
    float2 panelQ = abs(px - panelCenter) - panelHalf;
    float panelSdf = length(max(panelQ, 0.0)) + min(max(panelQ.x, panelQ.y), 0.0);
    float panel = 1.0 - smoothstep(-0.5, 1.5, panelSdf);
    return float2(clamp(ink, 0.0, 1.0), panel);
}

float3 phaseColor(float level)
{
    if (level < 0.15) return float3(0.88, 0.07, 0.025);
    if (level < 0.35) return float3(1.00, 0.76, 0.30);
    if (level < 0.55) return float3(0.46, 0.68, 1.00);
    if (level < 0.75) return float3(1.00, 0.88, 0.46);
    if (level < 0.90) return float3(0.46, 0.84, 1.00);
    return float3(0.68, 0.86, 1.00);
}

float4 main(float4 position : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 terminal = shaderTexture.Sample(samplerState, tex);
    if (TOKEN_ACTIVE == 0)
    {
        return terminal;
    }

    float2 res = Resolution;
    float2 fragCoord = position.xy;
    float2 uv = tex;
    float level = clamp((float)TOKEN_LEVEL, 0.0, 1.0);
    float aspect = res.x / res.y;
    float growth = pow(level, 0.72);
    float radius = lerp(MIN_RADIUS, MAX_RADIUS, growth);
    float2 center = lerp(float2(0.89, 0.14), float2(0.55, 0.34), smoothstep(0.05, 0.96, growth));
    center += float2(0.010 * sin(Time * 0.21), 0.008 * sin(Time * 0.17 + 1.7)) * (0.25 + level);
    float safeY = min(radius * 1.04 + 0.006, 0.48);
    float safeX = min(safeY / aspect, 0.48);
    center = clamp(center, float2(safeX, safeY), float2(1.0 - safeX, 1.0 - safeY));

    float2 p = (uv - center) * float2(aspect, 1.0);
    float d = length(p);
    float angle = atan2(p.y, p.x);
    float yShield = smoothstep(WORK_AREA, WORK_AREA + 0.10, 1.0 - uv.y);
    float hypergiant = step(0.55, level) * (1.0 - step(0.75, level));
    float neutron = step(0.75, level) * (1.0 - step(0.90, level));
    float activeNucleus = step(0.90, level);
    float quasar = step(0.90, level);

    float2 sampleUV = uv;
    if (activeNucleus > 0.0)
    {
        float lensRadius = radius * lerp(1.0, 1.55, quasar);
        float lens = activeNucleus * exp(-pow(d / max(lensRadius * 2.6, 0.0001), 2.0));
        float2 dir = p / max(d, 0.00001);
        float2 warpedP = p + dir * lens * radius * 0.20 / max(d / radius, 0.35);
        sampleUV = center + warpedP / float2(aspect, 1.0);
        terminal = shaderTexture.Sample(samplerState, clamp(sampleUV, 0.0, 1.0));
    }

    float3 color = terminal.rgb;
    float3 starColor = phaseColor(level);
    float2 starCell = floor(fragCoord / 22.0);
    float2 starLocal = abs(frac(fragCoord / 22.0) - 0.5);
    float starSeed = hash21(starCell);
    float starPoint = (1.0 - smoothstep(0.025, 0.105, length(starLocal))) * step(0.955, starSeed);
    float starTwinkle = 0.55 + 0.45 * sin(Time * (1.2 + starSeed * 2.3) + starSeed * 31.0);
    float terminalInk = smoothstep(0.16, 0.48, max(terminal.r, max(terminal.g, terminal.b)));
    color += float3(0.46, 0.66, 1.00) * starPoint * starTwinkle *
             (1.0 - terminalInk) * yShield * (0.10 + 0.22 * level);

    float normalStar = 1.0 - step(0.75, level);
    float surfaceNoise = fbm(rotate2(p, Time * STAR_SPEED) / max(radius, 0.0001) * 4.0 + 8.0);
    float limb = sqrt(clamp(1.0 - (d * d) / max(radius * radius, 0.00001), 0.0, 1.0));
    float sphere = 1.0 - smoothstep(radius * 0.965, radius, d);
    float3 surface = starColor * (0.48 + 0.75 * limb + 0.42 * surfaceNoise);
    surface += float3(1.0, 0.82, 0.55) * pow(max(limb, 0.0), 7.0) * 0.55;
    color = lerp(color, surface, sphere * normalStar * yShield);

    float rayNoise = 0.55 + 0.45 * sin(angle * lerp(13.0, 37.0, level) + Time * (0.7 + level));
    float corona = exp(-max(d - radius, 0.0) / max(radius * lerp(0.22, 0.72, level), 0.0001));
    corona *= 0.45 + 0.55 * pow(abs(rayNoise), 3.0);
    corona *= 1.0 - sphere;
    color += starColor * corona * normalStar * yShield * GLOW_GAIN * (0.45 + 0.75 * level);

    float crownPattern = pow(0.5 + 0.5 * cos(angle * (10.0 + 8.0 * level) - Time * 0.45), 12.0);
    float crown = crownPattern * exp(-max(d - radius, 0.0) /
                  max(radius * (0.65 + level * 0.85), 0.0001)) * (1.0 - sphere);
    color += yShield * normalStar * starColor * crown * (0.18 + 0.72 * level);

    float windShellA = exp(-pow((d - radius * 1.38) / max(radius * 0.055, 0.0001), 2.0));
    float windShellB = exp(-pow((d - radius * 1.78) / max(radius * 0.075, 0.0001), 2.0));
    color += yShield * hypergiant * float3(1.00, 0.62, 0.12) *
             (windShellA * 0.78 + windShellB * 0.44);

    if (neutron > 0.0)
    {
        float coreR = radius * 0.18;
        float core = exp(-pow(d / max(coreR, 0.0001), 3.2));
        float crust = exp(-pow((d - coreR * 0.92) / max(coreR * 0.10, 0.0001), 2.0));
        float2 bp = rotate2(p, Time * NEUTRON_SPIN + 0.22);
        float beamCore = exp(-pow(abs(bp.y) / max(radius * 0.035, 0.0001), 2.0));
        float beamSheath = exp(-pow(abs(bp.y) / max(radius * 0.11, 0.0001), 2.0));
        float beamReach = smoothstep(radius * 0.07, radius * 0.38, abs(bp.x)) *
                          (1.0 - smoothstep(radius * 2.05, radius * 2.65, abs(bp.x)));
        float beam = (beamCore * 1.25 + beamSheath * 0.30) * beamReach;
        float3 neutronColor = lerp(float3(0.22, 0.62, 1.00), float3(0.86, 0.98, 1.00), core);
        color += yShield * neutron * (neutronColor * (core * 3.5 + crust * 1.6) +
                 float3(0.36, 0.78, 1.00) * beam * 1.82);
    }

    if (activeNucleus > 0.0)
    {
        float quasarRise = smoothstep(0.90, 1.00, level);
        float grandeur = 1.0 + 1.65 * quasarRise;
        float2 diskP = rotate2(p, -0.22);
        float diskD = length(float2(diskP.x, diskP.y * 4.2));
        float holeR = radius * lerp(0.34, 0.48, quasar);
        float diskBand = exp(-pow((diskD - holeR * 1.82) / max(holeR * 0.23, 0.0001), 2.0));
        float diskAngle = atan2(diskP.y * 4.2, diskP.x);
        float physicalSpin = frac(Time * QUASAR_RPS) * TAU;
        float spiralPhase = diskAngle * 5.0 - log(max(diskD / max(holeR, 0.0001), 0.22)) * 11.0;
        float spiral = 0.58 + 0.42 * pow(0.5 + 0.5 * sin(spiralPhase - physicalSpin), 5.0);
        float fastGrainA = sin(diskAngle * 23.0 - physicalSpin * 1.35 + surfaceNoise * 6.0);
        float fastGrainB = sin(diskAngle * 23.0 - physicalSpin * 1.35 + 0.82 + surfaceNoise * 6.0);
        float diskGrain = (0.68 + 0.16 * (fastGrainA + fastGrainB)) * spiral;
        float hotSide = 0.36 + 0.64 * smoothstep(-holeR * 2.1, holeR * 2.1, diskP.x);
        float3 diskColor = lerp(float3(1.0, 0.055, 0.006), float3(1.0, 0.94, 0.58), hotSide);
        float farDisk = diskBand * (1.0 - smoothstep(-holeR * 0.08, holeR * 0.08, diskP.y));
        float frontDisk = diskBand * smoothstep(-holeR * 0.08, holeR * 0.08, diskP.y);
        float shadow = 1.0 - smoothstep(holeR * 0.94, holeR, d);
        color += yShield * activeNucleus * diskColor * farDisk * diskGrain *
                 (1.45 + 2.25 * quasar) * grandeur;
        color = lerp(color, float3(0.0, 0.0, 0.0), shadow * activeNucleus * yShield);
        color += yShield * activeNucleus * diskColor * frontDisk * diskGrain *
                 (1.85 + 2.8 * quasar) * grandeur;
        float photon = exp(-pow((d - holeR * 1.045) / max(holeR * 0.038, 0.0001), 2.0));
        float photonBeaming = 0.62 + 0.38 * smoothstep(-0.9, 0.8, cos(angle + 0.22));
        color += yShield * activeNucleus * photon * photonBeaming *
                 float3(1.0, 0.64, 0.20) * (2.05 + 2.4 * quasarRise);
        float innerHalo = exp(-pow((d - holeR * 1.18) / max(holeR * 0.20, 0.0001), 2.0));
        color += yShield * activeNucleus * innerHalo * float3(0.40, 0.12, 0.025) * 0.32;
        float outerDisk = exp(-pow((diskD - holeR * 2.38) / max(holeR * 0.34, 0.0001), 2.0));
        float orbitSparks = pow(0.5 + 0.5 * sin(diskAngle * 31.0 - physicalSpin * 1.7), 10.0);
        color += yShield * quasar * outerDisk *
                 lerp(float3(0.44, 0.18, 1.00), float3(1.00, 0.48, 0.08), hotSide) *
                 (0.34 + orbitSparks * (0.82 + 1.25 * quasarRise)) * grandeur;

        float2 jp = rotate2(p, -0.22);
        float jetT = clamp(abs(jp.y) / max(radius * 3.4, 0.0001), 0.0, 1.0);
        float jetWidth = radius * lerp(0.125, 0.030, jetT) * (1.0 + 0.34 * quasarRise);
        float jetCore = exp(-pow(abs(jp.x) / max(jetWidth * 0.42, 0.0001), 2.0));
        float jetSheath = exp(-pow(abs(jp.x) / max(jetWidth, 0.0001), 2.0));
        float jetReach = smoothstep(holeR * 0.82, holeR * 1.04, abs(jp.y)) *
                         (1.0 - smoothstep(radius * 2.9, radius * 3.75, abs(jp.y)));
        float jetFlow = abs(jp.y) * 34.0 / max(radius, 0.0001) - Time * (11.0 + 9.0 * quasarRise);
        float knots = 0.62 + 0.38 * pow(0.5 + 0.5 * sin(jetFlow), 3.0);
        float shockDiamonds = pow(0.5 + 0.5 * cos(jetFlow * 0.52), 16.0);
        float3 jetColor = float3(0.22, 0.48, 1.00) * jetSheath * (1.35 + 0.75 * quasarRise) +
                          float3(0.92, 0.98, 1.00) * jetCore * (2.85 + 3.2 * quasarRise);
        color += yShield * quasar * jetColor * jetReach * (knots + shockDiamonds * 0.85);
        float jetCocoon = exp(-pow(abs(jp.x) / max(jetWidth * 2.8, 0.0001), 2.0)) * jetReach;
        color += yShield * quasar * jetCocoon *
                 lerp(float3(0.12, 0.20, 0.78), float3(0.42, 0.18, 1.00), jetT) *
                 (0.44 + 0.72 * quasarRise);
        float polarNozzle = exp(-pow(abs(jp.x) / max(radius * 0.045, 0.0001), 2.0)) *
                            exp(-pow((abs(jp.y) - holeR * 1.08) /
                                max(holeR * 0.13, 0.0001), 2.0));
        color += yShield * quasar * polarNozzle * float3(0.78, 0.93, 1.00) *
                 (1.8 + 2.2 * quasarRise);
    }

    float halo = exp(-d / max(radius * lerp(1.5, 2.7, level), 0.0001));
    float bloom = exp(-pow(d / max(radius * lerp(1.15, 1.85, level), 0.0001), 1.55));
    color += yShield * starColor * (halo * 0.13 + bloom * 0.08) * (1.0 + level);

    float massK = (float)TOKEN_MASS_K;
    float2 labelCenter = center * res;
    float labelSide = center.x < 0.5 ? 1.0 : -1.0;
    labelCenter.x += labelSide * quasar * (radius * res.y * 1.30 + 64.0);
    float labelMargin = min(74.0, res.x * 0.45);
    labelCenter.x = clamp(labelCenter.x, labelMargin, res.x - labelMargin);
    float labelVerticalSide = center.y < 0.5 ? 1.0 : -1.0;
    float2 label = massLabel(fragCoord, labelCenter, massK, radius * res.y, labelVerticalSide);
    color = lerp(color, float3(0.003, 0.006, 0.012), label.y * yShield * 0.97);
    color = lerp(color, float3(0.96, 0.985, 1.00), label.x * yShield);

    float3 excess = max(color - 1.0, 0.0);
    color = min(color, 1.0) + excess / (1.0 + excess);
    return float4(color, terminal.a);
}
