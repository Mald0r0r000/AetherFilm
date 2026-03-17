#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Parameter Structures
// ─────────────────────────────────────────────────────────────────────────────
struct HDParams {
    float toeR, shoulderR, gammaR;
    float toeG, shoulderG, gammaG;
    float toeB, shoulderB, gammaB;
};

struct CrosstalkMatrix {
    float m[3][3];
};

struct ColorParams {
    int inputCS;
    bool textureOnly;
    int negStock;
    float exposure;
    bool enableDev;
    float pushPull;
    float interlayer;
    float bleachNeg;
    float neutralNeg;
    bool enablePrint;
    bool gangPrinter;
    float ppR;
    float ppG;
    float ppB;
    int printStock;
    float bleachPrint;
    float neutralPrint;
    int displayTgt;
};

struct HalationParams {
    float strength;
    float radius;
    float3 tint;
    float threshold;
    float softness;
};

// ─────────────────────────────────────────────────────────────────────────────
// Color Science Functions
// ─────────────────────────────────────────────────────────────────────────────

inline float3 toLinear(float3 c, int inputCS) {
    if (inputCS == 0) { // DWG
        constexpr float A = 0.0075f, B = 7.0f, C = 0.07329248f, M = 10.44426855f, LIN_BREAK = 0.00262409f;
        float3 out;
        out.r = (c.r <= C * log10(B * LIN_BREAK + A) + 0.1f) ? (pow(10.0f, (c.r - 0.1f) / C) - A) / B : (exp((c.r - 0.1f) / 0.07329248f) - 1.0f) / M;
        out.g = (c.g <= C * log10(B * LIN_BREAK + A) + 0.1f) ? (pow(10.0f, (c.g - 0.1f) / C) - A) / B : (exp((c.g - 0.1f) / 0.07329248f) - 1.0f) / M;
        out.b = (c.b <= C * log10(B * LIN_BREAK + A) + 0.1f) ? (pow(10.0f, (c.b - 0.1f) / C) - A) / B : (exp((c.b - 0.1f) / 0.07329248f) - 1.0f) / M;
        return out;
    } else if (inputCS == 1) { // REDWideGamut
        constexpr float a = 0.224282f, b = 155.975327f, c_val = 0.01f, g = 15.1927f;
        float3 out;
        out.r = (c.r < 0.0f) ? c.r / g : (pow(10.0f, c.r / a) - c_val) / b;
        out.g = (c.g < 0.0f) ? c.g / g : (pow(10.0f, c.g / a) - c_val) / b;
        out.b = (c.b < 0.0f) ? c.b / g : (pow(10.0f, c.b / a) - c_val) / b;
        return out;
    } else if (inputCS == 2) { // LogC3
        constexpr float cut = 0.010591f, a = 5.555556f, b = 0.052272f, c_val = 0.247190f, d = 0.385537f, e = 5.367655f, f = 0.092809f;
        float3 out;
        out.r = (c.r > e * cut + f) ? (pow(10.0f, (c.r - d) / c_val) - b) / a : (c.r - f) / e;
        out.g = (c.g > e * cut + f) ? (pow(10.0f, (c.g - d) / c_val) - b) / a : (c.g - f) / e;
        out.b = (c.b > e * cut + f) ? (pow(10.0f, (c.b - d) / c_val) - b) / a : (c.b - f) / e;
        return out;
    } else if (inputCS == 3) { // Slog3
        float3 out;
        out.r = (c.r >= 171.2102946929f / 1023.0f) ? pow(10.0f, (c.r - 0.410557184750733f) / 0.341075990077990f) - 0.01f : (c.r - 0.030001222851889303f) / 4.6f;
        out.g = (c.g >= 171.2102946929f / 1023.0f) ? pow(10.0f, (c.g - 0.410557184750733f) / 0.341075990077990f) - 0.01f : (c.g - 0.030001222851889303f) / 4.6f;
        out.b = (c.b >= 171.2102946929f / 1023.0f) ? pow(10.0f, (c.b - 0.410557184750733f) / 0.341075990077990f) - 0.01f : (c.b - 0.030001222851889303f) / 4.6f;
        return out;
    }
    return c;
}

inline float hdCurve(float x, float toe, float shoulder, float gamma) {
    // 1. Convert to log2 stops relative to middle grey 0.18
    float stops = log2(max(x, 1e-6f) / 0.18f);
    
    // 2. Map stops to a normalized input domain for the sigmoid
    // In a real negative, -4 stops = toe, +6 stops = shoulder.
    // Middle grey (0 stops) should sit a bit below the midpoint. 
    float norm = (stops + 4.5f) / 10.5f; 
    
    // Clamp norm to avoid extreme extrapolation in shadows/highlights
    // This prevents color shifts in deep shadows from per-channel toe differences
    norm = saturate(norm);
    
    // 3. Sigmoid with midpoint at 0.5 (mid-grey falls around 0.33)
    float s = 1.0f / (1.0f + exp(-gamma * (norm - 0.5f)));
    
    // 4. Soft clip toe and shoulder
    s = toe + (shoulder - toe) * s;
    // Clamp output to valid density range [0, 1]
    return saturate(s);
}

inline float3 applyHDCurve(float3 lin, HDParams p, float pushPull) {
    float ppGain = 1.0f + pushPull * 0.35f;
    float ppToeShift = pushPull * 0.03f;
    float r = hdCurve(lin.r, p.toeR + ppToeShift, p.shoulderR - ppToeShift, p.gammaR * ppGain);
    float g = hdCurve(lin.g, p.toeG + ppToeShift, p.shoulderG - ppToeShift, p.gammaG * ppGain);
    float b = hdCurve(lin.b, p.toeB + ppToeShift, p.shoulderB - ppToeShift, p.gammaB * ppGain);
    return float3(r, g, b);
}

inline float3 applyCrosstalk(float3 c, CrosstalkMatrix m, float strength) {
    float3 out;
    out.r = m.m[0][0]*c.r + m.m[0][1]*c.g + m.m[0][2]*c.b;
    out.g = m.m[1][0]*c.r + m.m[1][1]*c.g + m.m[1][2]*c.b;
    out.b = m.m[2][0]*c.r + m.m[2][1]*c.g + m.m[2][2]*c.b;
    return mix(c, out, strength);
}

inline float3 applyNeutralBlend(float3 stock, float3 lin, float blend) {
    float avg = (lin.r + lin.g + lin.b) / 3.0f;
    HDParams neutralP = {0.02f, 0.97f, 8.0f, 0.02f, 0.97f, 8.0f, 0.02f, 0.97f, 8.0f};
    float3 neutral = applyHDCurve(float3(avg), neutralP, 0.0f);
    return mix(stock, neutral, blend);
}

// Invert negative density (negative = 1 - density)
inline float3 invertNegative(float3 density) {
    return float3(1.0f - density.r, 1.0f - density.g, 1.0f - density.b);
}

inline float3 applyBleachBypass(float3 c, float strength) {
    if (strength <= 0.0f) return c;
    float luma = 0.2126f*c.r + 0.7152f*c.g + 0.0722f*c.b;
    float silverLuma = luma * (1.0f + 0.5f * strength);
    // Don't clamp — preserve HDR
    float desat = strength * 0.6f;
    float3 result = mix(c, float3(silverLuma), desat);
    float contrastMix = strength * 0.4f;
    result += (silverLuma - luma) * contrastMix;
    return result; // No clamp — let HDR values through
}

// Soft clip for HDR highlights — compresses values > threshold smoothly
// Higher threshold (1.5 = ~+3 stops) to preserve more of the HDR range
inline float softClip(float x, float threshold = 1.5f) {
    if (x <= threshold) return x;
    // Hyperbolic tangent soft shoulder
    return threshold + (1.0f - threshold) * tanh((x - threshold) / (1.0f - threshold));
}

inline float3 applyPrinterPoints(float3 c, float ppR, float ppG, float ppB) {
    // Normalized: 50 = neutral (gain 1.0), range 0-100
    // 0 = -1 stop, 100 = +1 stop
    float rGain = exp2((ppR - 50.0f) * 0.02f);
    float gGain = exp2((ppG - 50.0f) * 0.02f);
    float bGain = exp2((ppB - 50.0f) * 0.02f);
    return float3(c.r * rGain, c.g * gGain, c.b * bGain);
}

inline float3 applyDisplayGamma(float3 c, int displayTarget) {
    // If linear output requested, passthrough
    if (displayTarget == 3) return c;
    
    // For Rec.709/sRGB output, the sigmoid already maps to [0,1] display range
    // No additional gamma needed - sigmoid output is already display-referred
    // Only apply soft clip for any values that escaped the sigmoid
    return float3(
        min(1.0f, softClip(c.r, 0.95f)),
        min(1.0f, softClip(c.g, 0.95f)),
        min(1.0f, softClip(c.b, 0.95f))
    );
}

inline float halationMask(float luma, float threshold, float softness) {
    float knee = luma - threshold;
    if (knee <= 0.0f) return 0.0f;
    if (knee < softness) return (knee * knee) / (2.0f * softness);
    return knee - softness * 0.5f;
}

// ─────────────────────────────────────────────────────────────────────────────
// Kernels
// ─────────────────────────────────────────────────────────────────────────────

kernel void kernel_color_science(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    texture2d<float, access::write> intermediate [[texture(2)]],
    constant ColorParams &params [[buffer(0)]],
    constant HDParams &negHD [[buffer(1)]],
    constant CrosstalkMatrix &ct [[buffer(2)]],
    constant HDParams &printHD [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    
    float4 px = src.read(gid);
    float3 c = px.rgb;
    
    if (!params.textureOnly) {
        c = toLinear(c, params.inputCS);
        if (abs(params.exposure) > 1e-4f)
            c *= exp2(params.exposure);
            
        if (params.enableDev) {
            float3 negOut = applyHDCurve(c, negHD, params.pushPull);
            if (params.neutralNeg > 1e-4f)
                negOut = applyNeutralBlend(negOut, c, params.neutralNeg);
            negOut = applyCrosstalk(negOut, ct, params.interlayer);
            if (params.bleachNeg > 1e-4f)
                negOut = applyBleachBypass(negOut, params.bleachNeg);
            c = negOut;
        }
        
        if (params.enablePrint) {
            c = applyPrinterPoints(c, params.ppR, params.ppG, params.ppB);
            float3 printOut = applyHDCurve(c, printHD, 0.0f);
            if (params.neutralPrint > 1e-4f)
                printOut = applyNeutralBlend(printOut, c, params.neutralPrint);
            if (params.bleachPrint > 1e-4f)
                printOut = applyBleachBypass(printOut, params.bleachPrint);
            c = printOut;
        }
        
        // If no film processing enabled, apply basic tone mapping sigmoid
        if (!params.enableDev && !params.enablePrint) {
            HDParams basicHD = {0.02f, 0.97f, 8.0f, 0.02f, 0.97f, 8.0f, 0.02f, 0.97f, 8.0f};
            c = applyHDCurve(c, basicHD, 0.0f);
        }
        
        c = applyDisplayGamma(c, params.displayTgt);
    }
    
    float4 outPx = float4(c, px.a);
    dst.write(outPx, gid);
    intermediate.write(outPx, gid);
}

kernel void kernel_halation_extract(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> bloom [[texture(1)]],
    constant HalationParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= src.get_width() || gid.y >= src.get_height()) return;
    
    float3 c = src.read(gid).rgb;
    float luma = 0.2126f*c.r + 0.7152f*c.g + 0.0722f*c.b;
    float mask = halationMask(luma, params.threshold, params.softness);
    
    bloom.write(float4(c * mask, 0.0f), gid);
}

kernel void kernel_halation_blur_h(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float *kernel_weights [[buffer(0)]],
    constant int &radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    
    float3 sum = float3(0.0f);
    int ksize = 2 * radius + 1;
    for (int k = 0; k < ksize; ++k) {
        int sx = clamp((int)gid.x + k - radius, 0, (int)w - 1);
        sum += src.read(uint2(sx, gid.y)).rgb * kernel_weights[k];
    }
    dst.write(float4(sum, 0.0f), gid);
}

kernel void kernel_halation_blur_v(
    texture2d<float, access::read> src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant float *kernel_weights [[buffer(0)]],
    constant int &radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint w = src.get_width();
    uint h = src.get_height();
    if (gid.x >= w || gid.y >= h) return;
    
    float3 sum = float3(0.0f);
    int ksize = 2 * radius + 1;
    for (int k = 0; k < ksize; ++k) {
        int sy = clamp((int)gid.y + k - radius, 0, (int)h - 1);
        sum += src.read(uint2(gid.x, sy)).rgb * kernel_weights[k];
    }
    dst.write(float4(sum, 0.0f), gid);
}

kernel void kernel_halation_blend(
    texture2d<float, access::read> base_img [[texture(0)]],
    texture2d<float, access::read> bloom_img [[texture(1)]],
    texture2d<float, access::write> dst [[texture(2)]],
    constant HalationParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= base_img.get_width() || gid.y >= base_img.get_height()) return;
    
    float4 base = base_img.read(gid);
    float3 b = bloom_img.read(gid).rgb;
    
    float bloomLuma = 0.2126f*b.r + 0.7152f*b.g + 0.0722f*b.b;
    float3 tintAdd = bloomLuma * params.tint * params.strength;
    
    dst.write(float4(base.rgb + tintAdd, base.a), gid);
}
