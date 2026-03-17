#include "AetherFilmPlugin.h"
#include <iostream>
#include <vector>

using namespace OFX;

// ─────────────────────────────────────────────────────────────────────────────
// Constructor — fetch all params
// ─────────────────────────────────────────────────────────────────────────────
AetherFilmPlugin::AetherFilmPlugin(OfxImageEffectHandle handle)
    : ImageEffect(handle)
{
    srcClip_ = fetchClip(kOfxImageEffectSimpleSourceClipName);
    dstClip_ = fetchClip(kOfxImageEffectOutputClipName);

    inputCSParam_        = fetchChoiceParam (kParamInputColorSpace);
    textureOnlyParam_    = fetchBooleanParam(kParamTextureOnly);

    negStockParam_       = fetchChoiceParam (kParamNegStock);
    exposureParam_       = fetchDoubleParam (kParamExposure);

    enableDevParam_      = fetchBooleanParam(kParamEnableDev);
    pushPullParam_       = fetchDoubleParam (kParamPushPull);
    interlayerParam_     = fetchDoubleParam (kParamInterlayer);
    bleachNegParam_      = fetchDoubleParam (kParamBleachNeg);
    neutralNegParam_     = fetchDoubleParam (kParamNeutralNeg);

    enablePrintParam_    = fetchBooleanParam(kParamEnablePrint);
    gangPrinterParam_    = fetchBooleanParam(kParamGangPrinter);
    printerRParam_       = fetchDoubleParam (kParamPrinterR);
    printerGParam_       = fetchDoubleParam (kParamPrinterG);
    printerBParam_       = fetchDoubleParam (kParamPrinterB);
    printStockParam_     = fetchChoiceParam (kParamPrintStock);
    bleachPrintParam_    = fetchDoubleParam (kParamBleachPrint);
    neutralPrintParam_   = fetchDoubleParam (kParamNeutralPrint);
    displayTargetParam_  = fetchChoiceParam (kParamDisplayTarget);

    enableHalationParam_ = fetchBooleanParam(kParamEnableHalation);
    halationModeParam_   = fetchChoiceParam (kParamHalationMode);
    halationGaugeParam_  = fetchChoiceParam (kParamHalationGauge);
    halationStrengthParam_= fetchDoubleParam(kParamHalationStrength);
    halationColorParam_  = fetchRGBParam    (kParamHalationColor);
}

// ─────────────────────────────────────────────────────────────────────────────
// getClipPreferences
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmPlugin::getClipPreferences(ClipPreferencesSetter &prefs)
{
    prefs.setClipBitDepth(*dstClip_, eBitDepthFloat);
    prefs.setClipBitDepth(*srcClip_, eBitDepthFloat);
    prefs.setClipComponents(*dstClip_, ePixelComponentRGBA);
}

// ─────────────────────────────────────────────────────────────────────────────
// isIdentity — only pass through if everything is disabled
// ─────────────────────────────────────────────────────────────────────────────
bool AetherFilmPlugin::isIdentity(const IsIdentityArguments &args,
                                   Clip *&identityClip,
                                   double &identityTime)
{
    bool textureOnly, enableDev, enablePrint, enableHal;
    textureOnlyParam_->getValueAtTime(args.time, textureOnly);
    enableDevParam_->getValueAtTime(args.time, enableDev);
    enablePrintParam_->getValueAtTime(args.time, enablePrint);
    enableHalationParam_->getValueAtTime(args.time, enableHal);

    if (!textureOnly && !enableDev && !enablePrint && !enableHal) {
        identityClip = srcClip_;
        identityTime = args.time;
        return true;
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// render
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmPlugin::render(const RenderArguments &args)
{
    std::unique_ptr<Image> src(srcClip_->fetchImage(args.time));
    std::unique_ptr<Image> dst(dstClip_->fetchImage(args.time));
    if (!src || !dst) return;

    if (src->getPixelDepth() != eBitDepthFloat) {
        setPersistentMessage(Message::eMessageError, "",
            "AetherFilm requires 32-bit float. Set your project to 32-bit float processing.");
        throwSuiteStatusException(kOfxStatErrFormat);
        return;
    }

    const OfxRectI &win = args.renderWindow;
    const int W = win.x2 - win.x1;
    const int H = win.y2 - win.y1;
    const int srcNC = src->getPixelComponentCount();
    const int dstNC = dst->getPixelComponentCount();

    // ── Read all params at this time ───────────────────────────────────────
    int    inputCS;      inputCSParam_->getValueAtTime(args.time, inputCS);
    bool   textureOnly;  textureOnlyParam_->getValueAtTime(args.time, textureOnly);
    int    negStock;     negStockParam_->getValueAtTime(args.time, negStock);
    double exposure;     exposureParam_->getValueAtTime(args.time, exposure);
    bool   enableDev;    enableDevParam_->getValueAtTime(args.time, enableDev);
    double pushPull;     pushPullParam_->getValueAtTime(args.time, pushPull);
    double interlayer;   interlayerParam_->getValueAtTime(args.time, interlayer);
    double bleachNeg;    bleachNegParam_->getValueAtTime(args.time, bleachNeg);
    double neutralNeg;   neutralNegParam_->getValueAtTime(args.time, neutralNeg);
    bool   enablePrint;  enablePrintParam_->getValueAtTime(args.time, enablePrint);
    bool   gangPrinter;  gangPrinterParam_->getValueAtTime(args.time, gangPrinter);
    double ppR, ppG, ppB;
    printerRParam_->getValueAtTime(args.time, ppR);
    printerGParam_->getValueAtTime(args.time, ppG);
    printerBParam_->getValueAtTime(args.time, ppB);
    if (gangPrinter) { ppG = ppR; ppB = ppR; }
    int    printStock;   printStockParam_->getValueAtTime(args.time, printStock);
    double bleachPrint;  bleachPrintParam_->getValueAtTime(args.time, bleachPrint);
    double neutralPrint; neutralPrintParam_->getValueAtTime(args.time, neutralPrint);
    int    displayTgt;   displayTargetParam_->getValueAtTime(args.time, displayTgt);
    bool   enableHal;    enableHalationParam_->getValueAtTime(args.time, enableHal);
    int    halMode;      halationModeParam_->getValueAtTime(args.time, halMode);
    int    halGauge;     halationGaugeParam_->getValueAtTime(args.time, halGauge);
    double halStrength;  halationStrengthParam_->getValueAtTime(args.time, halStrength);
    double halR, halG, halB;
    halationColorParam_->getValueAtTime(args.time, halR, halG, halB);

    // ── Load stock params ──────────────────────────────────────────────────
    HDParams negHD, printHD;
    CrosstalkMatrix ct;
    switch (negStock) {
        case kNegKodak250D:
            negHD = getNegParams_Kodak250D();
            ct    = getCrosstalk_Kodak250D();
            break;
        case kNegKodak500T:
            negHD = getNegParams_Kodak500T();
            ct    = getCrosstalk_Kodak500T();
            break;
        case kNegFujiEterna500T:
            negHD = getNegParams_FujiEterna500T();
            ct    = getCrosstalk_FujiEterna500T();
            break;
        case kNegDoubleX:
            negHD = getNegParams_DoubleX();
            ct    = getCrosstalk_DoubleX();
            break;
        default:
            negHD = getNegParams_Kodak250D();
            ct    = getCrosstalk_Kodak250D();
    }
    switch (printStock) {
        case kPrint2383:  printHD = getPrintParams_2383();      break;
        case kPrint2393:  printHD = getPrintParams_2393();      break;
        case kPrintFuji3510: printHD = getPrintParams_Fuji3510(); break;
        default: printHD = getPrintParams_2383();
    }

    // ── Build an intermediate RGBA buffer for halation processing ──────────
    // We need a full-frame contiguous buffer to run the separable blur.
    std::vector<float> buf(W * H * 4, 0.0f);

    // ── Per-pixel color science ────────────────────────────────────────────
    for (int row = 0; row < H; ++row) {
        int y = win.y1 + row;
        const float *sp = static_cast<const float*>(src->getPixelAddress(win.x1, y));
        if (!sp) continue;

        for (int col = 0; col < W; ++col) {
            float3 c(sp[0], sp[1], sp[2]);
            float  a = (srcNC >= 4) ? sp[3] : 1.0f;

            if (!textureOnly) {

                // 1. Input colour space → linear scene
                c = toLinear(c, inputCS);

                // 2. Exposure offset
                if (std::abs((float)exposure) > 1e-4f)
                    c = applyExposure(c, static_cast<float>(exposure));

                if (enableDev) {
                    // 3. Negative H&D curve
                    float3 negOut = applyHDCurve(c, negHD, static_cast<float>(pushPull));

                    // 4. Neutral neg blend
                    if (neutralNeg > 1e-4)
                        negOut = applyNeutralBlend(negOut, c, static_cast<float>(neutralNeg));

                    // 5. Interlayer crosstalk
                    negOut = applyCrosstalk(negOut, ct, static_cast<float>(interlayer));

                    // 6. Bleach bypass (negative)
                    if (bleachNeg > 1e-4)
                        negOut = applyBleachBypass(negOut, static_cast<float>(bleachNeg));

                    c = negOut;
                }

                if (enablePrint) {
                    // 7. Printer points (colour timing)
                    c = applyPrinterPoints(c,
                        static_cast<float>(ppR),
                        static_cast<float>(ppG),
                        static_cast<float>(ppB));

                    // 8. Print H&D curve
                    float3 printOut = applyHDCurve(c, printHD, 0.0f);

                    // 9. Neutral print blend
                    if (neutralPrint > 1e-4)
                        printOut = applyNeutralBlend(printOut, c, static_cast<float>(neutralPrint));

                    // 10. Bleach bypass (print)
                    if (bleachPrint > 1e-4)
                        printOut = applyBleachBypass(printOut, static_cast<float>(bleachPrint));

                    c = printOut;
                }

                // 11. Display gamma
                c = applyDisplayGamma(c, displayTgt);
            }

            // Store into intermediate buffer (halation pass needs the full frame)
            float *bp = buf.data() + (row * W + col) * 4;
            bp[0] = c.r;  bp[1] = c.g;  bp[2] = c.b;  bp[3] = a;

            sp += srcNC;
        }
    }

    // ── Halation ───────────────────────────────────────────────────────────
    if (enableHal && halStrength > 1e-4) {
        float radius = gaugeToRadius(halGauge, W, halMode == kHalPrecision);

        HalationParams hp;
        hp.strength  = static_cast<float>(halStrength);
        hp.radius    = radius;
        hp.tint      = float3(static_cast<float>(halR),
                              static_cast<float>(halG),
                              static_cast<float>(halB));
        hp.threshold = 0.75f;
        hp.softness  = 0.15f;

        std::vector<float> halOut(W * H * 4, 0.0f);
        halationProcessor_.process(halOut.data(), buf.data(), W, H, hp);
        buf.swap(halOut);
    }

    // ── Write output ───────────────────────────────────────────────────────
    for (int row = 0; row < H; ++row) {
        int y = win.y1 + row;
        float *dp = static_cast<float*>(dst->getPixelAddress(win.x1, y));
        if (!dp) continue;
        for (int col = 0; col < W; ++col) {
            const float *bp = buf.data() + (row * W + col) * 4;
            dp[0] = bp[0];  dp[1] = bp[1];  dp[2] = bp[2];
            if (dstNC >= 4) dp[3] = bp[3];
            dp += dstNC;
        }
    }
}
