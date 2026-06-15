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
        float3( 41, 206, 16) / 255.0, // 12
        float3(148, 222, 33) / 255.0, // 11
        float3(189, 222, 41) / 255.0, // 10
        float3(214, 181, 33) / 255.0, // 9
        float3(222, 165, 24) / 255.0, // 8
        float3(198, 123,  8) / 255.0, // 7
        float3(214, 115,  0) / 255.0, // 6
        float3(214, 102,  0) / 255.0, // 5
        float3(214,  90,  0) / 255.0, // 4
        float3(206,  41, 16) / 255.0, // 3
        float3(239,  49, 16) / 255.0, // 2 top of spec
    };
    float t = clamp(in.uv.y, 0.0, 1.0);
    float scaled = t * 15.0;
    int idx = int(scaled);
    int next = min(idx + 1, 15);
    float3 color = mix(viscolor[idx], viscolor[next], fract(scaled));
    return float4(color, 1.0);
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

// MARK: - Mini oscilloscope

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

fragment float4 fullscreenFragment(float4 position [[position]],
                                   constant VizUniforms &uniforms [[buffer(0)]]) {
    float2 uv = position.xy / uniforms.resolution;
    uv.y = 1.0 - uv.y;

    float time = uniforms.time;
    float energy = uniforms.energy;
    uint preset = uniforms.preset % 4;

    float3 color;
    if (preset == 0) {
        float2 k = kaleidoscope(uv, time, energy);
        color = plasma(k, time, uniforms.bass, uniforms.treble);
    } else if (preset == 1) {
        color = plasma(uv, time, uniforms.bass, uniforms.treble);
    } else if (preset == 2) {
        color = frequencyRings(uv, time, uniforms.bass, uniforms.mid);
    } else {
        color = waveformTunnel(uv, time, energy);
    }

    color *= 0.85 + energy * 0.35;
    return float4(color, 1.0);
}
