#include "AetherFilmPlugin.h"
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
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
// render (Dispatcher)
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmPlugin::render(const RenderArguments &args)
{
    if (args.isEnabledMetalRender && args.pMetalCmdQ != nullptr) {
        renderMetal(args);
    } else {
        renderCPU(args);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// renderCPU
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmPlugin::renderCPU(const RenderArguments &args)
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

// ─────────────────────────────────────────────────────────────────────────────
// renderMetal
// ─────────────────────────────────────────────────────────────────────────────
struct MetalColorParams {
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

struct MetalHDParams {
    float toeR, shoulderR, gammaR;
    float toeG, shoulderG, gammaG;
    float toeB, shoulderB, gammaB;
};

void AetherFilmPlugin::renderMetal(const RenderArguments &args)
{
    std::unique_ptr<Image> src(srcClip_->fetchImage(args.time));
    std::unique_ptr<Image> dst(dstClip_->fetchImage(args.time));
    if (!src || !dst) return;

    id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)args.pMetalCmdQ;
    if (!commandQueue) return;
    id<MTLDevice> device = commandQueue.device;

    // Load pipeline states if not loaded yet
    static id<MTLLibrary> library = nil;
    static id<MTLComputePipelineState> psoColorScience = nil;
    static id<MTLComputePipelineState> psoHalExtract = nil;
    static id<MTLComputePipelineState> psoHalBlurH = nil;
    static id<MTLComputePipelineState> psoHalBlurV = nil;
    static id<MTLComputePipelineState> psoHalBlend = nil;

    if (!library) {
        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.maldoror.aetherfilm"];
        if (bundle) {
            NSURL *url = [bundle URLForResource:@"AetherFilm" withExtension:@"metallib"];
            NSError *error = nil;
            library = [device newLibraryWithURL:url error:&error];
            if (error) {
                std::cerr << "Failed to load Metallib: " << error.localizedDescription.UTF8String << std::endl;
                return;
            }
        } else {
            std::cerr << "AetherFilmOFX bundle not found!" << std::endl;
            return;
        }

        NSError *err = nil;
        id<MTLFunction> funcCol = [library newFunctionWithName:@"kernel_color_science"];
        psoColorScience = [device newComputePipelineStateWithFunction:funcCol error:&err];
        
        id<MTLFunction> funcHExtract = [library newFunctionWithName:@"kernel_halation_extract"];
        psoHalExtract = [device newComputePipelineStateWithFunction:funcHExtract error:&err];

        id<MTLFunction> funcHBlurH = [library newFunctionWithName:@"kernel_halation_blur_h"];
        psoHalBlurH = [device newComputePipelineStateWithFunction:funcHBlurH error:&err];

        id<MTLFunction> funcHBlurV = [library newFunctionWithName:@"kernel_halation_blur_v"];
        psoHalBlurV = [device newComputePipelineStateWithFunction:funcHBlurV error:&err];

        id<MTLFunction> funcHBlend = [library newFunctionWithName:@"kernel_halation_blend"];
        psoHalBlend = [device newComputePipelineStateWithFunction:funcHBlend error:&err];
    }

    // Wrap OFX pointers in MTLTexture
    id<MTLTexture> srcTex = (__bridge id<MTLTexture>)src->getPixelData();
    id<MTLTexture> dstTex = (__bridge id<MTLTexture>)dst->getPixelData();
    if (!srcTex || !dstTex) return;

    int w = (int)srcTex.width;
    int h = (int)srcTex.height;

    // Fetch params
    MetalColorParams cp;
    inputCSParam_->getValueAtTime(args.time, cp.inputCS);
    textureOnlyParam_->getValueAtTime(args.time, cp.textureOnly);
    negStockParam_->getValueAtTime(args.time, cp.negStock);
    double e; exposureParam_->getValueAtTime(args.time, e); cp.exposure = (float)e;
    enableDevParam_->getValueAtTime(args.time, cp.enableDev);
    double pp; pushPullParam_->getValueAtTime(args.time, pp); cp.pushPull = (float)pp;
    double il; interlayerParam_->getValueAtTime(args.time, il); cp.interlayer = (float)il;
    double bn; bleachNegParam_->getValueAtTime(args.time, bn); cp.bleachNeg = (float)bn;
    double nn; neutralNegParam_->getValueAtTime(args.time, nn); cp.neutralNeg = (float)nn;
    enablePrintParam_->getValueAtTime(args.time, cp.enablePrint);
    gangPrinterParam_->getValueAtTime(args.time, cp.gangPrinter);
    double ppr, ppg, ppb;
    printerRParam_->getValueAtTime(args.time, ppr); cp.ppR = (float)ppr;
    printerGParam_->getValueAtTime(args.time, ppg); cp.ppG = (float)ppg;
    printerBParam_->getValueAtTime(args.time, ppb); cp.ppB = (float)ppb;
    if (cp.gangPrinter) { cp.ppG = cp.ppR; cp.ppB = cp.ppR; }
    printStockParam_->getValueAtTime(args.time, cp.printStock);
    double bp; bleachPrintParam_->getValueAtTime(args.time, bp); cp.bleachPrint = (float)bp;
    double np; neutralPrintParam_->getValueAtTime(args.time, np); cp.neutralPrint = (float)np;
    displayTargetParam_->getValueAtTime(args.time, cp.displayTgt);

    bool enableHal; enableHalationParam_->getValueAtTime(args.time, enableHal);
    int halMode; halationModeParam_->getValueAtTime(args.time, halMode);
    int halGauge; halationGaugeParam_->getValueAtTime(args.time, halGauge);
    double hStr; halationStrengthParam_->getValueAtTime(args.time, hStr);
    double hr, hg, hb; halationColorParam_->getValueAtTime(args.time, hr, hg, hb);

    // Get Stock Params
    HDParams negHD_c, printHD_c; CrosstalkMatrix ct;
    switch (cp.negStock) {
        case kNegKodak250D: negHD_c = getNegParams_Kodak250D(); ct = getCrosstalk_Kodak250D(); break;
        case kNegKodak500T: negHD_c = getNegParams_Kodak500T(); ct = getCrosstalk_Kodak500T(); break;
        case kNegFujiEterna500T: negHD_c = getNegParams_FujiEterna500T(); ct = getCrosstalk_FujiEterna500T(); break;
        case kNegDoubleX: negHD_c = getNegParams_DoubleX(); ct = getCrosstalk_DoubleX(); break;
        default: negHD_c = getNegParams_Kodak250D(); ct = getCrosstalk_Kodak250D();
    }
    switch (cp.printStock) {
        case kPrint2383: printHD_c = getPrintParams_2383(); break;
        case kPrint2393: printHD_c = getPrintParams_2393(); break;
        case kPrintFuji3510: printHD_c = getPrintParams_Fuji3510(); break;
        default: printHD_c = getPrintParams_2383();
    }
    MetalHDParams negHD = {negHD_c.toeR, negHD_c.shoulderR, negHD_c.gammaR, negHD_c.toeG, negHD_c.shoulderG, negHD_c.gammaG, negHD_c.toeB, negHD_c.shoulderB, negHD_c.gammaB};
    MetalHDParams printHD = {printHD_c.toeR, printHD_c.shoulderR, printHD_c.gammaR, printHD_c.toeG, printHD_c.shoulderG, printHD_c.gammaG, printHD_c.toeB, printHD_c.shoulderB, printHD_c.gammaB};

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [commandBuffer computeCommandEncoder];

    // Create intermediate texture if halation is enabled
    id<MTLTexture> intermediateTex = nil;
    if (enableHal && hStr > 1e-4) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:w height:h mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        td.storageMode = MTLStorageModePrivate;
        intermediateTex = [device newTextureWithDescriptor:td];
    } else {
        intermediateTex = dstTex; // No halation needed, just write directly to dst
    }

    MTLSize threadsPerGrid = MTLSizeMake(w, h, 1);
    MTLSize threadsPerGroup = MTLSizeMake(16, 16, 1);

    // Pass 1: Color Science
    [enc setComputePipelineState:psoColorScience];
    [enc setTexture:srcTex atIndex:0];
    [enc setTexture:dstTex atIndex:1];
    [enc setTexture:intermediateTex atIndex:2];
    [enc setBytes:&cp length:sizeof(cp) atIndex:0];
    [enc setBytes:&negHD length:sizeof(negHD) atIndex:1];
    [enc setBytes:&ct length:sizeof(ct) atIndex:2];
    [enc setBytes:&printHD length:sizeof(printHD) atIndex:3];
    [enc dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerGroup];

    // Halation passes
    if (enableHal && hStr > 1e-4) {
        struct HalationParams { float str; float rad; float tint[3]; float thres; float soft; } hp;
        hp.str = (float)hStr;
        hp.rad = gaugeToRadius(halGauge, w, halMode == kHalPrecision);
        hp.tint[0] = (float)hr; hp.tint[1] = (float)hg; hp.tint[2] = (float)hb;
        hp.thres = 0.75f; hp.soft = 0.15f;

        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:w height:h mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        td.storageMode = MTLStorageModePrivate;
        id<MTLTexture> bloomTex = [device newTextureWithDescriptor:td];
        id<MTLTexture> blurHTex = [device newTextureWithDescriptor:td];
        id<MTLTexture> blurVTex = [device newTextureWithDescriptor:td];

        // Ensure reasonable radius to avoid killing the GPU (O(R) compute)
        int iradius = std::max(1, std::min((int)hp.rad, 128));
        std::vector<float> kernel_weights = makeGaussianKernel(iradius);

        // Extract
        [enc setComputePipelineState:psoHalExtract];
        [enc setTexture:intermediateTex atIndex:0];
        [enc setTexture:bloomTex atIndex:1];
        [enc setBytes:&hp length:sizeof(hp) atIndex:0];
        [enc dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerGroup];

        // Blur H
        [enc setComputePipelineState:psoHalBlurH];
        [enc setTexture:bloomTex atIndex:0];
        [enc setTexture:blurHTex atIndex:1];
        [enc setBytes:kernel_weights.data() length:kernel_weights.size()*sizeof(float) atIndex:0];
        [enc setBytes:&iradius length:sizeof(int) atIndex:1];
        [enc dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerGroup];

        // Blur V
        [enc setComputePipelineState:psoHalBlurV];
        [enc setTexture:blurHTex atIndex:0];
        [enc setTexture:blurVTex atIndex:1];
        [enc setBytes:kernel_weights.data() length:kernel_weights.size()*sizeof(float) atIndex:0];
        [enc setBytes:&iradius length:sizeof(int) atIndex:1];
        [enc dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerGroup];

        // Blend
        [enc setComputePipelineState:psoHalBlend];
        [enc setTexture:intermediateTex atIndex:0];
        [enc setTexture:blurVTex atIndex:1];
        [enc setTexture:dstTex atIndex:2];
        [enc setBytes:&hp length:sizeof(hp) atIndex:0];
        [enc dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerGroup];
    }

    [enc endEncoding];
    [commandBuffer commit];
}
