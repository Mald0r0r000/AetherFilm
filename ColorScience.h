#pragma once
#include <cmath>
#include <algorithm>

// ─────────────────────────────────────────────────────────────────────────────
// Basic types
// ─────────────────────────────────────────────────────────────────────────────
struct float3 {
    float r, g, b;
    float3() : r(0), g(0), b(0) {}
    float3(float r, float g, float b) : r(r), g(g), b(b) {}
};

inline float3 operator+(const float3 &a, const float3 &b) { return {a.r+b.r, a.g+b.g, a.b+b.b}; }
inline float3 operator*(const float3 &a, float s)          { return {a.r*s,   a.g*s,   a.b*s};   }
inline float3 lerp3(const float3 &a, const float3 &b, float t) {
    return { a.r + (b.r-a.r)*t, a.g + (b.g-a.g)*t, a.b + (b.b-a.b)*t };
}
inline float clamp01(float x) { return std::max(0.0f, std::min(1.0f, x)); }
inline float clampf(float x, float lo, float hi) { return std::max(lo, std::min(hi, x)); }

// Soft clip for HDR highlights — compresses values > threshold smoothly
// Higher threshold (1.5 = ~+3 stops) to preserve more of the HDR range
inline float softClip(float x, float threshold = 1.5f) {
    if (x <= threshold) return x;
    // Hyperbolic tangent soft shoulder - asymptotically approaches threshold + (1-threshold)
    // For threshold=1.5, max output ~2.0
    return threshold + (1.0f - threshold) * std::tanh((x - threshold) / (1.0f - threshold));
}

// ─────────────────────────────────────────────────────────────────────────────
// Input colour space → linear scene
// Simple log-to-linear transforms. Replace with precise primaries later.
// ─────────────────────────────────────────────────────────────────────────────
inline float3 toLinear(float3 c, int inputCS)
{
    auto dwgToLinear = [](float x) -> float {
        // DaVinci Intermediate log → linear
        const float A = 0.0075f, B = 7.0f, C = 0.07329248f;
        const float M = 10.44426855f, LIN_BREAK = 0.00262409f;
        if (x <= C * std::log10(B * LIN_BREAK + A) + 0.1f)
            return (std::pow(10.0f, (x - 0.1f) / C) - A) / B;
        return (std::exp((x - 0.1f) / 0.07329248f) - 1.0f) / M;
        // Note: simplified — use BMD's exact spec for production
    };

    auto redLogToLinear = [](float x) -> float {
        // REDWideGamut Log3G10 → linear
        const float a = 0.224282f, b = 155.975327f, c = 0.01f, g = 15.1927f;
        if (x < 0.0f) return x / g;
        return (std::pow(10.0f, x / a) - c) / b;
    };

    auto logCToLinear = [](float x) -> float {
        // ARRI LogC3 EI800 approximation
        const float cut = 0.010591f, a = 5.555556f, b = 0.052272f;
        const float c = 0.247190f, d = 0.385537f, e = 5.367655f, f = 0.092809f;
        if (x > e * cut + f)
            return (std::pow(10.0f, (x - d) / c) - b) / a;
        return (x - f) / e;
    };

    auto slog3ToLinear = [](float x) -> float {
        // Sony S-Log3 → linear
        if (x >= 171.2102946929f / 1023.0f)
            return std::pow(10.0f, (x - 0.410557184750733f) / 0.341075990077990f) - 0.01f;
        return (x - 0.030001222851889303f) / 4.6f;
    };

    switch (inputCS) {
        case 0: return { dwgToLinear(c.r), dwgToLinear(c.g), dwgToLinear(c.b) };
        case 1: return { redLogToLinear(c.r), redLogToLinear(c.g), redLogToLinear(c.b) };
        case 2: return { logCToLinear(c.r), logCToLinear(c.g), logCToLinear(c.b) };
        case 3: return { slog3ToLinear(c.r), slog3ToLinear(c.g), slog3ToLinear(c.b) };
        default: return c; // linear passthrough
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exposure offset (in stops, applied in linear)
// ─────────────────────────────────────────────────────────────────────────────
inline float3 applyExposure(float3 c, float stops)
{
    float gain = std::pow(2.0f, stops);
    return { c.r * gain, c.g * gain, c.b * gain };
}

// ─────────────────────────────────────────────────────────────────────────────
// H&D curve model
// Parameterised toe/shoulder using a smooth S-curve.
// Each stock has separate R, G, B parameters to model real dye layer responses.
// Reference: Kodak/Fuji D-logE datasheets + Colour Science Python (colour-science.org)
// ─────────────────────────────────────────────────────────────────────────────
struct HDParams {
    // Per-channel: toe, shoulder, gamma (slope at middle grey)
    float toeR, shoulderR, gammaR;
    float toeG, shoulderG, gammaG;
    float toeB, shoulderB, gammaB;
};

// Invert negative density (negative = 1 - density)
inline float3 invertNegative(float3 density) {
    return { 1.0f - density.r, 1.0f - density.g, 1.0f - density.b };
}

// Smooth sigmoid — maps [0,1] input to [0,1] density
// toe < 0.5 < shoulder, gamma controls mid-slope
inline float hdCurve(float x, float toe, float shoulder, float gamma)
{
    // Convert to log2 stops relative to middle grey (0.18)
    float stops = std::log2(std::max(x, 1e-6f) / 0.18f);

    // Map stops to a normalized input domain for the sigmoid
    // In a real negative, -4 stops = toe, +6 stops = shoulder.
    // Middle grey (0 stops) should sit a bit below the midpoint. 
    float norm = (stops + 4.5f) / 10.5f; 
    
    // Clamp norm to avoid extreme extrapolation in shadows/highlights
    // This prevents color shifts in deep shadows from per-channel toe differences
    norm = std::max(0.0f, std::min(1.0f, norm));

    // Sigmoid with midpoint at 0.5 (mid-grey falls around 0.33)
    float s = 1.0f / (1.0f + std::exp(-gamma * (norm - 0.5f)));

    // Apply toe/shoulder soft limiting
    s = toe + (shoulder - toe) * s;
    // Clamp output to valid density range [0, 1]
    return std::max(0.0f, std::min(1.0f, s));
}

// Apply H&D curve per channel with push/pull modulation
inline float3 applyHDCurve(float3 lin, const HDParams &p, float pushPull)
{
    // Push/Pull: increase gamma (contrast) and shift toe/shoulder
    float ppGain = 1.0f + pushPull * 0.35f;
    float ppToeShift = pushPull * 0.03f;

    float r = hdCurve(lin.r,
        p.toeR + ppToeShift, p.shoulderR - ppToeShift, p.gammaR * ppGain);
    float g = hdCurve(lin.g,
        p.toeG + ppToeShift, p.shoulderG - ppToeShift, p.gammaG * ppGain);
    float b = hdCurve(lin.b,
        p.toeB + ppToeShift, p.shoulderB - ppToeShift, p.gammaB * ppGain);

    return { r, g, b };
}

// ─────────────────────────────────────────────────────────────────────────────
// Interlayer crosstalk (3x3 matrix)
// Models dye cloud sensitivity overlap between layers.
// Values estimated from Colour Science Python film spectral data.
// ─────────────────────────────────────────────────────────────────────────────
struct CrosstalkMatrix {
    // row = output channel, col = input channel
    float m[3][3];
};

inline float3 applyCrosstalk(float3 c, const CrosstalkMatrix &m, float strength)
{
    float3 out;
    out.r = m.m[0][0]*c.r + m.m[0][1]*c.g + m.m[0][2]*c.b;
    out.g = m.m[1][0]*c.r + m.m[1][1]*c.g + m.m[1][2]*c.b;
    out.b = m.m[2][0]*c.r + m.m[2][1]*c.g + m.m[2][2]*c.b;
    return lerp3(c, out, strength);
}

// ─────────────────────────────────────────────────────────────────────────────
// Neutral curve blend
// At 0: real stock curves. At 1: channels are aligned (neutral response).
// ─────────────────────────────────────────────────────────────────────────────
inline float3 applyNeutralBlend(float3 stock, float3 lin, float blend)
{
    // Neutral = average of channels applied uniformly
    float avg = (lin.r + lin.g + lin.b) / 3.0f;
    float3 neutral = applyHDCurve({avg, avg, avg}, {
        // "Average" neutral params
        0.02f, 0.97f, 8.0f,
        0.02f, 0.97f, 8.0f,
        0.02f, 0.97f, 8.0f
    }, 0.0f);
    return lerp3(stock, neutral, blend);
}

// ─────────────────────────────────────────────────────────────────────────────
// Bleach Bypass
// Models skipped bleaching: retains silver, increasing contrast + desaturation.
// ─────────────────────────────────────────────────────────────────────────────
inline float3 applyBleachBypass(float3 c, float strength)
{
    if (strength <= 0.0f) return c;
    float luma = 0.2126f*c.r + 0.7152f*c.g + 0.0722f*c.b;
    // Silver retention lifts contrast via a gentle S on luma
    float silverLuma = luma * (1.0f + 0.5f * strength);
    // Don't clamp — preserve HDR
    // Blend original chroma with desaturated version
    float desat = strength * 0.6f;
    float3 grey = { silverLuma, silverLuma, silverLuma };
    float3 result = lerp3(c, grey, desat);
    // Add contrast from silver luma
    float contrastMix = strength * 0.4f;
    result.r = result.r + (silverLuma - luma) * contrastMix;
    result.g = result.g + (silverLuma - luma) * contrastMix;
    result.b = result.b + (silverLuma - luma) * contrastMix;
    return result; // No clamp — let HDR values through
}

// ─────────────────────────────────────────────────────────────────────────────
// Printer Points
// 25 = neutral. Each unit ≈ 1/6 stop of coloured printer light (reduced for finer control).
// ─────────────────────────────────────────────────────────────────────────────
inline float3 applyPrinterPoints(float3 c, float ppR, float ppG, float ppB)
{
    // Convert printer points to exposure multiplier
    // Reduced from 0.05 to 0.02 for finer control (≈1/10 stop per point)
    auto ppToGain = [](float pp) -> float {
        return std::pow(2.0f, (pp - 25.0f) * 0.02f);
    };
    return {
        c.r * ppToGain(ppR),
        c.g * ppToGain(ppG),
        c.b * ppToGain(ppB)
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Display target — density → display gamma
// ─────────────────────────────────────────────────────────────────────────────
inline float3 applyDisplayGamma(float3 c, int displayTarget)
{
    // If linear output requested, passthrough
    if (displayTarget == 3) return c;
    
    // For Rec.709/sRGB output, the sigmoid already maps to [0,1] display range
    // No additional gamma needed - sigmoid output is already display-referred
    // Only apply soft clip for any values that escaped the sigmoid
    return {
        std::min(1.0f, softClip(c.r, 0.95f)),
        std::min(1.0f, softClip(c.g, 0.95f)),
        std::min(1.0f, softClip(c.b, 0.95f))
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stock database
// ─────────────────────────────────────────────────────────────────────────────

// Kodak Vision3 250D 5207
// Daylight stock — warm-neutral shadow, clean highlights
// Source: estimated from Colour Science Python + Kodak TDS
inline HDParams getNegParams_Kodak250D()
{
    return {
        // R: warm toe, extended shoulder
        0.025f, 0.960f, 7.8f,
        // G: reference channel, slightly more contrast
        0.020f, 0.970f, 8.2f,
        // B: compressed toe, cooler shadows
        0.030f, 0.955f, 7.5f
    };
}
inline CrosstalkMatrix getCrosstalk_Kodak250D()
{
    return {{
        { 0.900f, 0.060f, 0.040f },  // R influenced slightly by G
        { 0.030f, 0.935f, 0.035f },  // G dominant
        { 0.025f, 0.055f, 0.920f }   // B influenced by G in shadows
    }};
}

// Kodak Vision3 500T 5219
// Tungsten stock — richer shadows, stronger grain, slight blue correction
inline HDParams getNegParams_Kodak500T()
{
    return {
        0.030f, 0.950f, 8.0f,
        0.022f, 0.965f, 8.4f,
        0.035f, 0.945f, 7.8f
    };
}
inline CrosstalkMatrix getCrosstalk_Kodak500T()
{
    return {{
        { 0.890f, 0.068f, 0.042f },
        { 0.032f, 0.928f, 0.040f },
        { 0.028f, 0.062f, 0.910f }
    }};
}

// Fuji Eterna 500T 8673
// Cooler, greener shadows, flatter highlights, characteristic Fuji palette
inline HDParams getNegParams_FujiEterna500T()
{
    return {
        0.028f, 0.945f, 7.6f,
        0.018f, 0.968f, 8.5f,   // G: Fuji's strong green channel
        0.038f, 0.940f, 7.2f    // B: compressed, cooler
    };
}
inline CrosstalkMatrix getCrosstalk_FujiEterna500T()
{
    return {{
        { 0.880f, 0.075f, 0.045f },
        { 0.028f, 0.942f, 0.030f },  // strong G dominance
        { 0.022f, 0.070f, 0.908f }
    }};
}

// Kodak Double-X 5222
// B&W stock — single channel response, high contrast
inline HDParams getNegParams_DoubleX()
{
    return {
        0.015f, 0.965f, 9.2f,   // Higher gamma = more contrast
        0.015f, 0.965f, 9.2f,
        0.015f, 0.965f, 9.2f
    };
}
inline CrosstalkMatrix getCrosstalk_DoubleX()
{
    // B&W: all channels collapse to luma
    return {{
        { 0.299f, 0.587f, 0.114f },
        { 0.299f, 0.587f, 0.114f },
        { 0.299f, 0.587f, 0.114f }
    }};
}

// Print stock H&D — applied after printer points
// Kodak 2383: warm, slightly boosted reds, classic cinema look
inline HDParams getPrintParams_2383()
{
    return {
        0.018f, 0.975f, 8.8f,   // R: warm, extended
        0.015f, 0.978f, 9.0f,   // G: neutral reference
        0.022f, 0.968f, 8.5f    // B: slightly compressed
    };
}

inline HDParams getPrintParams_2393()
{
    return {
        0.016f, 0.980f, 9.2f,
        0.014f, 0.982f, 9.4f,
        0.020f, 0.972f, 8.8f
    };
}

inline HDParams getPrintParams_Fuji3510()
{
    return {
        0.020f, 0.970f, 8.6f,
        0.016f, 0.975f, 9.1f,
        0.025f, 0.960f, 8.2f
    };
}
