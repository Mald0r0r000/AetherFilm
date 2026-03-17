#pragma once
#include "ColorScience.h"
#include <vector>
#include <cmath>

// ─────────────────────────────────────────────────────────────────────────────
// Halation
//
// Real halation = high-luminance light scatters back through the film base,
// re-exposing primarily the red-sensitive layer.
//
// Algorithm:
//   1. Extract high-luminance regions (soft threshold)
//   2. Apply separable Gaussian blur (radius scales with gauge)
//   3. Tint the bloom (red/orange)
//   4. Additive blend back onto the image
//
// CPU implementation — for GPU/Metal port this becomes two compute passes
// (horizontal + vertical separable blur).
// ─────────────────────────────────────────────────────────────────────────────

struct HalationParams {
    float  strength;    // 0..2
    float  radius;      // blur radius in pixels
    float3 tint;        // bloom colour (r, g, b)
    float  threshold;   // luminance threshold to start blooming
    float  softness;    // softness of threshold knee
};

// Gauge → base radius multiplier (relative to 2048px width)
inline float gaugeToRadius(int gauge, int imageWidth, bool precision)
{
    float baseRadius;
    switch (gauge) {
        case 0:  baseRadius = 0.008f; break; // 35mm — tighter
        case 1:  baseRadius = 0.018f; break; // 16mm — wider spread
        case 2:  baseRadius = 0.030f; break; // Super 8 — very wide
        default: baseRadius = 0.008f;
    }
    float r = baseRadius * static_cast<float>(imageWidth);
    return precision ? r : r * 0.6f; // Performance mode = smaller kernel
}

// 1D Gaussian kernel
inline std::vector<float> makeGaussianKernel(int radius)
{
    int size = 2 * radius + 1;
    std::vector<float> k(size);
    float sigma = radius / 2.5f;
    float sum = 0.0f;
    for (int i = 0; i < size; ++i) {
        float x = static_cast<float>(i - radius);
        k[i] = std::exp(-0.5f * x * x / (sigma * sigma));
        sum += k[i];
    }
    for (auto &v : k) v /= sum;
    return k;
}

// Soft threshold — luminance above threshold bleeds into halation
inline float halationMask(float luma, float threshold, float softness)
{
    float knee = luma - threshold;
    if (knee <= 0.0f) return 0.0f;
    // Soft quadratic knee
    if (knee < softness) return (knee * knee) / (2.0f * softness);
    return knee - softness * 0.5f;
}

// ─────────────────────────────────────────────────────────────────────────────
// CPU halation processor
// Operates on a flat RGBA float buffer (row-major, 4 floats/pixel)
// ─────────────────────────────────────────────────────────────────────────────
class HalationProcessor {
public:
    void process(float       *dst,
                 const float *src,
                 int          width,
                 int          height,
                 const HalationParams &p)
    {
        int radius = static_cast<int>(p.radius);
        radius = std::max(1, std::min(radius, 128)); // safety clamp

        auto kernel = makeGaussianKernel(radius);
        int ksize = static_cast<int>(kernel.size());

        // ── Step 1: Extract halation source (high-luma bloom) ──────────────
        std::vector<float> bloom(width * height * 3, 0.0f);

        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                const float *px = src + (y * width + x) * 4;
                float r = px[0], g = px[1], b = px[2];
                float luma = 0.2126f*r + 0.7152f*g + 0.0722f*b;
                float mask = halationMask(luma, p.threshold, p.softness);

                bloom[(y * width + x) * 3 + 0] = r * mask;
                bloom[(y * width + x) * 3 + 1] = g * mask;
                bloom[(y * width + x) * 3 + 2] = b * mask;
            }
        }

        // ── Step 2: Horizontal pass ────────────────────────────────────────
        std::vector<float> blurH(width * height * 3, 0.0f);

        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                float sr = 0, sg = 0, sb = 0;
                for (int k = 0; k < ksize; ++k) {
                    int sx = std::max(0, std::min(width-1, x + k - radius));
                    int idx = (y * width + sx) * 3;
                    sr += bloom[idx+0] * kernel[k];
                    sg += bloom[idx+1] * kernel[k];
                    sb += bloom[idx+2] * kernel[k];
                }
                int oi = (y * width + x) * 3;
                blurH[oi+0] = sr; blurH[oi+1] = sg; blurH[oi+2] = sb;
            }
        }

        // ── Step 3: Vertical pass ──────────────────────────────────────────
        std::vector<float> blurV(width * height * 3, 0.0f);

        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                float sr = 0, sg = 0, sb = 0;
                for (int k = 0; k < ksize; ++k) {
                    int sy = std::max(0, std::min(height-1, y + k - radius));
                    int idx = (sy * width + x) * 3;
                    sr += blurH[idx+0] * kernel[k];
                    sg += blurH[idx+1] * kernel[k];
                    sb += blurH[idx+2] * kernel[k];
                }
                int oi = (y * width + x) * 3;
                blurV[oi+0] = sr; blurV[oi+1] = sg; blurV[oi+2] = sb;
            }
        }

        // ── Step 4: Tint + additive blend ─────────────────────────────────
        for (int y = 0; y < height; ++y) {
            for (int x = 0; x < width; ++x) {
                const float *sp = src + (y * width + x) * 4;
                float       *dp = dst + (y * width + x) * 4;
                int bi = (y * width + x) * 3;

                // Tint the bloom towards the halation colour
                float bloomLuma = 0.2126f*blurV[bi] + 0.7152f*blurV[bi+1] + 0.0722f*blurV[bi+2];
                float br = bloomLuma * p.tint.r * p.strength;
                float bg = bloomLuma * p.tint.g * p.strength;
                float bb = bloomLuma * p.tint.b * p.strength;

                dp[0] = sp[0] + br;
                dp[1] = sp[1] + bg;
                dp[2] = sp[2] + bb;
                dp[3] = sp[3]; // alpha passthrough
            }
        }
    }
};
