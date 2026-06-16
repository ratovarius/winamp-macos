#include <metal_stdlib>
using namespace metal;

struct VizUniforms {
    float time;
    float bass;
    float mid;
    float treble;
    float2 resolution;
    uint mode;
    uint preset;
    float energy;
    uint spectrumBandCount;
    uint scopeSampleCount;
};

// Layout must stay byte-compatible with the Swift `VizUniforms` (MetalVisualizationPlugin.swift),
// which is memcpy'd into the uniform buffer. `VizUniformsLayoutTests` asserts the same numbers on
// the Swift side, so a field reorder/insert breaks both the shader build and a unit test rather
// than silently corrupting every visualization.
static_assert(sizeof(VizUniforms) == 48, "VizUniforms size must match Swift MemoryLayout<VizUniforms>.stride");
static_assert(alignof(VizUniforms) == 8, "VizUniforms alignment must match the Swift struct");

struct SpectrumVertexOut {
    float4 position [[position]];
    float2 uv;
    float level;
};

struct ScopeVertexOut {
    float4 position [[position]];
    float4 color;
};

// MARK: - Shared fullscreen quad

vertex float4 fullscreenVertex(uint vertexID [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0),
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

// MARK: - Mini spectrum bars

vertex SpectrumVertexOut spectrumVertex(uint vertexID [[vertex_id]],
                                         constant float *spectrum [[buffer(0)]],
                                         constant VizUniforms &uniforms [[buffer(1)]]) {
    const uint barCount = max(uniforms.spectrumBandCount, 1u);
    const uint corners[6] = {0, 1, 2, 2, 1, 3};

    uint tri = vertexID / 6;
    uint corner = corners[vertexID % 6];
    float barWidth = 2.0 / float(barCount);
    float x0 = -1.0 + float(tri) * barWidth;
    float x1 = x0 + barWidth * 0.82;

    float level = spectrum[min(tri, barCount - 1)];
    float yTop = -1.0 + level * 1.85;

    float2 position;
    if (corner == 0) position = float2(x0, -1.0);
    else if (corner == 1) position = float2(x1, -1.0);
    else if (corner == 2) position = float2(x0, yTop);
    else position = float2(x1, yTop);

    SpectrumVertexOut out;
    out.position = float4(position, 0.0, 1.0);
    out.uv = float2((position.x + 1.0) * 0.5, (position.y + 1.0) * 0.5);
    out.level = level;
    return out;
}

fragment float4 spectrumFragment(SpectrumVertexOut in [[stage_in]]) {
    // Authentic classic Winamp 2.91 VISCOLOR.TXT spectrum ramp (colors 2–17),
    // ordered bottom-of-bar (green) → top-of-bar (red).
    constexpr float3 viscolor[16] = {
        float3( 24, 132,  8) / 255.0, // 17 bottom of spec
        float3( 41, 148,  0) / 255.0, // 16
        float3( 49, 156,  8) / 255.0, // 15
        float3( 57, 181, 16) / 255.0, // 14
        float3( 50, 190, 16) / 255.0, // 13
        float3( 41, 206,  16) / 255.0, // 12
        float3(148, 222,  33) / 255.0, // 11
        float3(189, 222,  41) / 255.0, // 10
        float3(214, 181,  33) / 255.0, // 9
        float3(222, 165,  24) / 255.0, // 8
        float3(198, 123,   8) / 255.0, // 7
        float3(214, 115,   0) / 255.0, // 6
        float3(214, 102,   0) / 255.0, // 5
        float3(214,  90,   0) / 255.0, // 4
        float3(206,  41,  16) / 255.0, // 3
        float3(239,  49,  16) / 255.0, // 2 top of spec
    };
    float t = clamp(in.uv.y, 0.0, 1.0);
    float scaled = t * 15.0;
    int idx = int(scaled);
    int next = min(idx + 1, 15);
    float3 color = mix(viscolor[idx], viscolor[next], fract(scaled));
    return float4(color, 1.0);
}

// MARK: - Analyzer peak markers (classic 1px hold lines)

vertex SpectrumVertexOut spectrumPeakVertex(uint vertexID [[vertex_id]],
                                          constant float *peaks [[buffer(0)]],
                                          constant VizUniforms &uniforms [[buffer(1)]]) {
    const uint barCount = max(uniforms.spectrumBandCount, 1u);
    const uint corners[6] = {0, 1, 2, 2, 1, 3};

    uint tri = vertexID / 6;
    uint corner = corners[vertexID % 6];
    float barWidth = 2.0 / float(barCount);
    float x0 = -1.0 + float(tri) * barWidth;
    float x1 = x0 + barWidth * 0.82;

    float level = peaks[min(tri, barCount - 1)];
    float yBottom = -1.0 + level * 1.85;
    float yTop = min(yBottom + 0.12, 1.0);

    float2 position;
    if (corner == 0) position = float2(x0, yBottom);
    else if (corner == 1) position = float2(x1, yBottom);
    else if (corner == 2) position = float2(x0, yTop);
    else position = float2(x1, yTop);

    SpectrumVertexOut out;
    out.position = float4(position, 0.0, 1.0);
    out.uv = float2(0.0, 1.0);
    out.level = level;
    return out;
}

fragment float4 spectrumPeakFragment(SpectrumVertexOut in [[stage_in]]) {
    // VISCOLOR entry 24 — classic analyzer peak dot.
    return float4(214.0 / 255.0, 206.0 / 255.0, 181.0 / 255.0, 1.0);
}

fragment float4 spectrumCompositeFragment(float4 position [[position]],
                                          texture2d<float> currentFrame [[texture(0)]],
                                          texture2d<float> historyFrame [[texture(1)]],
                                          constant float &historyDecay [[buffer(0)]]) {
    constexpr sampler frameSampler(mag_filter::nearest, min_filter::nearest);
    float2 resolution = float2(currentFrame.get_width(), currentFrame.get_height());
    float2 uv = (position.xy + 0.5) / resolution;
    float4 current = currentFrame.sample(frameSampler, uv);
    float4 history = historyFrame.sample(frameSampler, uv);
    float3 persisted = max(current.rgb, history.rgb * historyDecay);
    return float4(persisted, 1.0);
}

// Passthrough copy used to present an offscreen texture into a `framebufferOnly` drawable
// (which cannot be a blit destination) via a fullscreen draw.
fragment float4 copyFragment(float4 position [[position]],
                             texture2d<float> source [[texture(0)]]) {
    constexpr sampler frameSampler(mag_filter::nearest, min_filter::nearest);
    float2 resolution = float2(source.get_width(), source.get_height());
    float2 uv = (position.xy + 0.5) / resolution;
    return float4(source.sample(frameSampler, uv).rgb, 1.0);
}

// MARK: - Mini oscilloscope (high-resolution line, classic Winamp style)

struct ScopeLineVertexOut {
    float4 position [[position]];
};

vertex ScopeLineVertexOut oscilloscopeLineVertex(uint vertexID [[vertex_id]],
                                                 constant float *columnLevels [[buffer(0)]],
                                                 constant VizUniforms &uniforms [[buffer(1)]]) {
    const uint columnCount = max(uniforms.scopeSampleCount, 2u);
    const uint index = min(vertexID, columnCount - 1u);
    const float x = -1.0 + (float(index) / float(columnCount - 1u)) * 2.0;
    const float y = columnLevels[index] * 0.92;

    ScopeLineVertexOut out;
    out.position = float4(x, y, 0.0, 1.0);
    return out;
}

fragment float4 oscilloscopeLineFragment(ScopeLineVertexOut in [[stage_in]]) {
    // Classic scope trace — bright neutral green-white (VISCOLOR 18).
    return float4(0.82, 0.98, 0.78, 1.0);
}

// Legacy column-fill scope (kept for reference)

struct ScopeColumnVertexOut {
    float4 position [[position]];
    float shade;
};

vertex ScopeColumnVertexOut oscilloscopeColumnVertex(uint vertexID [[vertex_id]],
                                                     constant float *columnLevels [[buffer(0)]],
                                                     constant VizUniforms &uniforms [[buffer(1)]]) {
    const uint columnCount = max(uniforms.scopeSampleCount, 2u);
    const uint corners[6] = {0, 1, 2, 2, 1, 3};

    uint tri = vertexID / 6;
    uint corner = corners[vertexID % 6];
    float columnWidth = 2.0 / float(columnCount);
    float x0 = -1.0 + float(tri) * columnWidth;
    float x1 = x0 + columnWidth;

    float level = columnLevels[min(tri, columnCount - 1)];
    float yCenter = level * 0.85;
    float yPrev = tri > 0 ? columnLevels[tri - 1] * 0.85 : yCenter;
    float yTop = min(yCenter, yPrev);
    float yBottom = max(yCenter, yPrev);
    if (tri == 0) {
        yTop = yCenter;
        yBottom = yCenter;
    }

    float2 position;
    if (corner == 0) position = float2(x0, yTop);
    else if (corner == 1) position = float2(x1, yTop);
    else if (corner == 2) position = float2(x0, yBottom);
    else position = float2(x1, yBottom);

    ScopeColumnVertexOut out;
    out.position = float4(position, 0.0, 1.0);
    out.shade = abs(yCenter);
    return out;
}

fragment float4 oscilloscopeColumnFragment(ScopeColumnVertexOut in [[stage_in]]) {
    // Classic scope ramp (VISCOLOR 18–22).
    constexpr float3 shades[5] = {
        float3( 41, 206,  16) / 255.0,
        float3(148, 222,  33) / 255.0,
        float3(214, 181,  33) / 255.0,
        float3(214, 115,   0) / 255.0,
        float3(239,  49,  16) / 255.0,
    };
    float t = clamp(in.shade, 0.0, 1.0);
    float scaled = t * 4.0;
    int idx = int(scaled);
    int next = min(idx + 1, 4);
    float3 color = mix(shades[idx], shades[next], fract(scaled));
    return float4(color, 1.0);
}

// Legacy line-strip oscilloscope (unused; kept for reference during migration)

vertex ScopeVertexOut oscilloscopeVertex(uint vertexID [[vertex_id]],
                                         constant float *waveLeft [[buffer(0)]],
                                         constant float *waveRight [[buffer(1)]],
                                         constant VizUniforms &uniforms [[buffer(2)]]) {
    const uint sampleCount = max(uniforms.scopeSampleCount, 2u);
    uint channel = vertexID / sampleCount;
    uint index = vertexID % sampleCount;

    float x = -1.0 + (float(index) / float(sampleCount - 1)) * 2.0;
    float sample = channel == 0 ? waveLeft[index] : waveRight[index];
    float y = channel == 0 ? -sample * 0.85 : sample * 0.85;

    ScopeVertexOut out;
    out.position = float4(x, y, 0.0, 1.0);
    out.color = channel == 0 ? float4(1.0, 0.0, 0.0, 1.0) : float4(0.0, 0.5, 1.0, 1.0);
    return out;
}

fragment float4 oscilloscopeFragment(ScopeVertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Fullscreen Milkdrop-style presets

static float2 kaleidoscope(float2 uv, float time, float energy) {
    float2 p = uv - 0.5;
    float angle = atan2(p.y, p.x);
    float radius = length(p);
    float segments = 6.0 + energy * 4.0;
    angle = fmod(angle, 3.14159265 * 2.0 / segments);
    angle = abs(angle - 3.14159265 / segments);
    float2 q = float2(cos(angle), sin(angle)) * radius;
    q += 0.15 * sin(time * 1.4 + radius * 12.0 + energy * 6.0);
    return q + 0.5;
}

static float3 plasma(float2 uv, float time, float bass, float treble) {
    float v = sin(uv.x * 10.0 + time) + sin(uv.y * 10.0 + time * 1.3);
    v += sin((uv.x + uv.y) * 10.0 + time * 0.7 + bass * 4.0);
    v += sin(length(uv - 0.5) * 20.0 - time * 2.0 + treble * 5.0);
    float3 col = float3(
        0.5 + 0.5 * sin(v + 0.0),
        0.5 + 0.5 * sin(v + 2.1),
        0.5 + 0.5 * sin(v + 4.2)
    );
    return col;
}

static float3 frequencyRings(float2 uv, float time, float bass, float mid) {
    float2 p = uv - 0.5;
    float radius = length(p);
    float rings = sin(radius * 40.0 - time * 2.5 + bass * 8.0) * 0.5 + 0.5;
    float swirl = sin(atan2(p.y, p.x) * 8.0 + time + mid * 6.0) * 0.5 + 0.5;
    return float3(rings, swirl, 1.0 - radius);
}

static float3 waveformTunnel(float2 uv, float time, float energy) {
    float2 p = (uv - 0.5) * 2.0;
    float a = atan2(p.y, p.x);
    float r = length(p);
    float tunnel = sin(8.0 / max(r, 0.05) - time * 3.0 + energy * 10.0);
    float3 col = float3(0.2, 0.6, 1.0) * (tunnel * 0.5 + 0.5);
    col += float3(1.0, 0.4, 0.1) * (sin(a * 5.0 + time) * 0.5 + 0.5) * (1.0 - r);
    return col;
}

// MARK: - Procedural noise helpers (shared by the cloud/particle presets)

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 hash22(float2 p) {
    float n = sin(dot(p, float2(41.0, 289.0)));
    return fract(float2(262144.0, 32768.0) * n);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * valueNoise(p);
        p = p * 2.0 + 13.0;
        amp *= 0.5;
    }
    return v;
}

// MARK: - Additional fullscreen presets (one per VisualizationPreset case)

static float3 spiralGalaxy(float2 uv, float time, float energy, float bass) {
    float2 p = uv - 0.5;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float spiral = sin(2.0 * a + r * 18.0 - time * 1.5 - bass * 4.0);
    float arms = pow(max(spiral, 0.0), 2.0) * (1.0 - r);
    float core = smoothstep(0.45, 0.0, r);
    float3 col = float3(0.6, 0.4, 1.0) * arms;
    col += float3(1.0, 0.8, 0.5) * core * (0.6 + energy);
    return col;
}

static float3 oscillatorGrid(float2 uv, float time, float mid, float treble) {
    float2 cell = fract(uv * 8.0) - 0.5;
    float2 id = floor(uv * 8.0);
    float phase = time * 2.0 + (id.x + id.y) * 0.5;
    float pulse = sin(phase + mid * 6.0) * 0.5 + 0.5;
    float dot = smoothstep(0.42 * pulse, 0.34 * pulse, length(cell));
    float3 col = mix(float3(0.0, 0.08, 0.18), float3(0.2, 0.9, 0.8), dot);
    col += treble * 0.3 * dot;
    return col;
}

static float3 particleStorm(float2 uv, float time, float energy) {
    float3 col = float3(0.0);
    for (int i = 0; i < 20; i++) {
        float fi = float(i);
        float2 seed = hash22(float2(fi, fi * 1.7 + 2.0));
        float2 pos = fract(seed + float2(sin(time * 0.3 + fi), time * (0.1 + seed.x * 0.3)));
        float d = length(uv - pos);
        float spark = 0.004 / (d + 0.002);
        col += spark * (0.5 + energy) * float3(0.7 + seed.x * 0.3, 0.5, 1.0 - seed.y * 0.5);
    }
    return col;
}

static float3 lfoMorph(float2 uv, float time, float bass, float mid, float treble) {
    float lfo = sin(time * 0.5) * 0.5 + 0.5;
    float3 a = plasma(uv, time, bass, treble);
    float3 b = frequencyRings(uv, time, bass, mid);
    return mix(a, b, lfo);
}

static float3 nebulaGalaxy(float2 uv, float time, float energy) {
    float2 p = uv * 3.0;
    float clouds = fbm(p + float2(time * 0.1, time * 0.05));
    float veil = fbm(p * 1.5 - float2(time * 0.08, 0.0));
    float3 col = mix(float3(0.08, 0.0, 0.18), float3(0.9, 0.3, 0.6), clouds);
    col += float3(0.2, 0.4, 0.9) * veil * 0.6;
    col *= 0.5 + energy * 0.8;
    return col;
}

static float3 starfieldFlight(float2 uv, float time, float energy) {
    float2 p = uv - 0.5;
    float3 col = float3(0.0);
    for (int i = 0; i < 32; i++) {
        float fi = float(i);
        float2 dir = normalize(hash22(float2(fi, fi + 3.0)) - 0.5);
        float speed = 0.2 + hash21(float2(fi, 7.0)) * 0.8;
        float z = fract(time * speed + hash21(float2(fi, 1.0)));
        float2 sp = dir * z * 0.7;
        float d = length(p - sp);
        col += (0.0018 / (d + 0.001)) * z * (0.6 + energy);
    }
    return col;
}

static float3 starWarsCrawl(float2 uv, float time, float energy) {
    float2 p = float2(uv.x - 0.5, uv.y);
    float horizon = 0.85;
    float persp = horizon - p.y;
    if (persp <= 0.001) {
        return float3(0.0, 0.0, 0.04);
    }
    float2 q = float2(p.x / persp, time * 0.3 + 0.2 / persp);
    float bands = step(0.5, fract(q.y * 6.0));
    float text = bands * smoothstep(1.2, 0.2, abs(q.x));
    float3 col = float3(1.0, 0.85, 0.2) * text * clamp(persp * 3.0, 0.0, 1.0);
    col += float3(0.0, 0.0, 0.04);
    col *= 0.7 + energy * 0.5;
    return col;
}

// Dispatches one distinct effect per `VisualizationPreset` case. There is intentionally NO
// modulo/wraparound: each raw value maps to its own named visual, and the final `else` covers
// the last case. Adding a preset = add a `VisualizationPreset` case + a branch here (see
// `VisualizationPresetTests.testPresetCountMatchesShaderBranchCount`).
fragment float4 fullscreenFragment(float4 position [[position]],
                                   constant VizUniforms &uniforms [[buffer(0)]]) {
    float2 uv = position.xy / uniforms.resolution;
    uv.y = 1.0 - uv.y;

    float time = uniforms.time;
    float energy = uniforms.energy;
    float bass = uniforms.bass;
    float mid = uniforms.mid;
    float treble = uniforms.treble;
    uint preset = uniforms.preset;

    float3 color;
    if (preset == 0u) {            // spiralGalaxy
        color = spiralGalaxy(uv, time, energy, bass);
    } else if (preset == 1u) {     // oscillatorGrid
        color = oscillatorGrid(uv, time, mid, treble);
    } else if (preset == 2u) {     // plasmaField
        color = plasma(uv, time, bass, treble);
    } else if (preset == 3u) {     // particleStorm
        color = particleStorm(uv, time, energy);
    } else if (preset == 4u) {     // frequencyRings
        color = frequencyRings(uv, time, bass, mid);
    } else if (preset == 5u) {     // waveformTunnel
        color = waveformTunnel(uv, time, energy);
    } else if (preset == 6u) {     // kaleidoscope
        float2 k = kaleidoscope(uv, time, energy);
        color = plasma(k, time, bass, treble);
    } else if (preset == 7u) {     // lfoMorph
        color = lfoMorph(uv, time, bass, mid, treble);
    } else if (preset == 8u) {     // nebulaGalaxy
        color = nebulaGalaxy(uv, time, energy);
    } else if (preset == 9u) {     // starfieldFlight
        color = starfieldFlight(uv, time, energy);
    } else {                       // starWarsCrawl (10)
        color = starWarsCrawl(uv, time, energy);
    }

    color *= 0.85 + energy * 0.35;
    return float4(color, 1.0);
}
