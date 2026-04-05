#include "Processor.h"
#include "AetherFilmPlugin.h"
#include <cstdio>
#include <vector>
#include <cmath>
#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <mutex>
#include "ofxsImageEffect.h"

using namespace OFX;

// ─────────────────────────────────────────────────────────────────────────────
// Constructor
// ─────────────────────────────────────────────────────────────────────────────
AetherFilmProcessor::AetherFilmProcessor(ImageEffect *instance, const RenderArguments &args)
    : ImageProcessor(*instance)
{
    // Set GPU render args - this is crucial for Metal activation
    setGPURenderArgs(args);
    setRenderWindow(args.renderWindow);
}

// ─────────────────────────────────────────────────────────────────────────────
// Set parameters
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmProcessor::setParams(int inputCS, bool textureOnly, int negStock, float exposure,
                                      bool enableDev, float pushPull, float interlayer, float bleachNeg, float neutralNeg,
                                      bool enablePrint, float ppR, float ppG, float ppB, int printStock,
                                      float bleachPrint, float neutralPrint, int displayTgt)
{
    inputCS_ = inputCS;
    textureOnly_ = textureOnly;
    negStock_ = negStock;
    exposure_ = exposure;
    enableDev_ = enableDev;
    pushPull_ = pushPull;
    interlayer_ = interlayer;
    bleachNeg_ = bleachNeg;
    neutralNeg_ = neutralNeg;
    enablePrint_ = enablePrint;
    ppR_ = ppR; ppG_ = ppG; ppB_ = ppB;
    printStock_ = printStock;
    bleachPrint_ = bleachPrint;
    neutralPrint_ = neutralPrint;
    displayTgt_ = displayTgt;
    
    // Load stock params
    switch (negStock_) {
        case kNegKodak250D:
            negHD_ = getNegParams_Kodak250D();
            ct_ = getCrosstalk_Kodak250D();
            break;
        case kNegKodak500T:
            negHD_ = getNegParams_Kodak500T();
            ct_ = getCrosstalk_Kodak500T();
            break;
        case kNegFujiEterna500T:
            negHD_ = getNegParams_FujiEterna500T();
            ct_ = getCrosstalk_FujiEterna500T();
            break;
        case kNegDoubleX:
            negHD_ = getNegParams_DoubleX();
            ct_ = getCrosstalk_DoubleX();
            break;
        default:
            negHD_ = getNegParams_Kodak250D();
            ct_ = getCrosstalk_Kodak250D();
    }
    switch (printStock_) {
        case kPrint2383:  printHD_ = getPrintParams_2383(); break;
        case kPrint2393:  printHD_ = getPrintParams_2393(); break;
        case kPrintFuji3510: printHD_ = getPrintParams_Fuji3510(); break;
        default: printHD_ = getPrintParams_2383();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CPU Processing
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmProcessor::multiThreadProcessImages(OfxRectI window)
{
    const int W = window.x2 - window.x1;
    const int H = window.y2 - window.y1;
    
    if (!_srcImg || !_dstImg) return;
    
    const int srcNC = _srcImg->getPixelComponentCount();
    const int dstNC = _dstImg->getPixelComponentCount();
    
    for (int row = window.y1; row < window.y2; ++row) {
        const float *sp = static_cast<const float*>(_srcImg->getPixelAddress(window.x1, row));
        float *dp = static_cast<float*>(_dstImg->getPixelAddress(window.x1, row));
        if (!sp || !dp) continue;
        
        for (int col = window.x1; col < window.x2; ++col) {
            float3 c(sp[0], sp[1], sp[2]);
            float a = (srcNC >= 4) ? sp[3] : 1.0f;
            
            if (!textureOnly_) {
                // 1. Input colour space → linear scene
                c = toLinear(c, inputCS_);
                
                // 2. Exposure offset
                if (std::abs(exposure_) > 1e-4f)
                    c = applyExposure(c, exposure_);
                
                if (enableDev_) {
                    // 3. Negative H&D curve (linear → density)
                    float3 negOut = applyHDCurve(c, negHD_, pushPull_);
                    
                    // 4. Neutral neg blend
                    if (neutralNeg_ > 1e-4)
                        negOut = applyNeutralBlend(negOut, c, neutralNeg_);
                    
                    // 5. Interlayer crosstalk
                    negOut = applyCrosstalk(negOut, ct_, interlayer_);
                    
                    // 6. Bleach bypass (negative)
                    if (bleachNeg_ > 1e-4)
                        negOut = applyBleachBypass(negOut, bleachNeg_);
                    
                    c = negOut;
                }
                
                if (enablePrint_) {
                    // 7. Printer points (colour timing)
                    c = applyPrinterPoints(c, ppR_, ppG_, ppB_);
                    
                    // 8. Print H&D curve
                    float3 printOut = applyHDCurve(c, printHD_, 0.0f);
                    
                    // 9. Neutral print blend
                    if (neutralPrint_ > 1e-4)
                        printOut = applyNeutralBlend(printOut, c, neutralPrint_);
                    
                    // 10. Bleach bypass (print)
                    if (bleachPrint_ > 1e-4)
                        printOut = applyBleachBypass(printOut, bleachPrint_);
                    
                    c = printOut;
                }
                
                // 11. If no film processing enabled, apply basic tone mapping sigmoid
                if (!enableDev_ && !enablePrint_) {
                    HDParams basicHD = {0.02f, 0.97f, 8.0f, 0.02f, 0.97f, 8.0f, 0.02f, 0.97f, 8.0f};
                    c = applyHDCurve(c, basicHD, 0.0f);
                }
                
                // 12. Display gamma
                c = applyDisplayGamma(c, displayTgt_);
            }
            
            dp[0] = c.r;
            dp[1] = c.g;
            dp[2] = c.b;
            dp[3] = a;
            
            sp += srcNC;
            dp += dstNC;
        }
    }
}

// Global Metal states
static id<MTLLibrary> gLibrary = nil;
static id<MTLComputePipelineState> gPsoColorScience = nil;
static std::mutex gInitMutex;

// ─────────────────────────────────────────────────────────────────────────────
// GPU Metal Processing
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmProcessor::processImagesMetal()
{
    FILE* logFile = fopen("/tmp/aetherfilm_render.log", "a");
    if (logFile) {
        fprintf(logFile, "[AetherFilm] processImagesMetal entry, _isEnabledMetalRender=%d\n", _isEnabledMetalRender);
    }
    
    @autoreleasepool {
        if (!_srcImg || !_dstImg) {
            if (logFile) { fprintf(logFile, "[AetherFilm] src or dst NULL\n"); }
            if (logFile) fclose(logFile);
            return;
        }
        
        if (!_pMetalCmdQ) {
            if (logFile) { fprintf(logFile, "[AetherFilm] _pMetalCmdQ is NULL\n"); }
            if (logFile) fclose(logFile);
            return;
        }

        id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)_pMetalCmdQ;
        if (![commandQueue conformsToProtocol:@protocol(MTLCommandQueue)]) {
             NSLog(@"[AetherFilm] _pMetalCmdQ does not conform to MTLCommandQueue!");
             // Fallback to direct cast if bridge check is too strict
             commandQueue = (id<MTLCommandQueue>)_pMetalCmdQ;
        }

        id<MTLDevice> device = commandQueue.device;
        if (!device) {
            NSLog(@"[AetherFilm] device is NULL");
            return;
        }
        NSLog(@"[AetherFilm] Device: %@", device.name);

        {
            NSLog(@"[AetherFilm] Taking init lock...");
            std::lock_guard<std::mutex> lock(gInitMutex);
            if (!gLibrary) {
                NSLog(@"[AetherFilm] Initializing library...");

                Dl_info info;
                if (dladdr((const void *)&OFX::Plugin::getPluginIDs, &info)) {
                    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
                    NSString *contentsDir = [[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
                    NSString *libPath = [[contentsDir stringByAppendingPathComponent:@"Resources"] stringByAppendingPathComponent:@"AetherFilm.metallib"];
                    
                    NSLog(@"[AetherFilm] dladdr success: %@", libPath);

                    NSURL *url = [NSURL fileURLWithPath:libPath];
                    NSError *error = nil;
                    gLibrary = [device newLibraryWithURL:url error:&error];
                    if (error || !gLibrary) {
                        NSLog(@"[AetherFilm] newLibraryWithURL FAILED: %@", error ? error.localizedDescription : @"null");
                        return;
                    }
                    NSLog(@"[AetherFilm] Library loaded successfully");
                } else {
                    NSLog(@"[AetherFilm] dladdr FAILED");
                    return;
                }
                
                NSError *err = nil;
                id<MTLFunction> funcCol = [gLibrary newFunctionWithName:@"kernel_color_science"];
                if (funcCol) gPsoColorScience = [device newComputePipelineStateWithFunction:funcCol error:&err];
                
                if (!gPsoColorScience || err) {
                    NSLog(@"[AetherFilm] PSO FAILED: %@", err ? err.localizedDescription : @"null");
                    gLibrary = nil;
                    return;
                }
                NSLog(@"[AetherFilm] PSO created successfully");
            }
        }
        
        // Get buffers from OFX images (standard OFX Metal format)
        id<MTLBuffer> srcBuffer = reinterpret_cast<id<MTLBuffer>>(_srcImg->getPixelData());
        id<MTLBuffer> dstBuffer = reinterpret_cast<id<MTLBuffer>>(_dstImg->getPixelData());
        if (!srcBuffer || !dstBuffer) {
            NSLog(@"[AetherFilm] buffer cast FAILED: src=%p dst=%p", srcBuffer, dstBuffer);
            return;
        }
        
        const OfxRectI& bounds = _srcImg->getBounds();
        int w = bounds.x2 - bounds.x1;
        int h = bounds.y2 - bounds.y1;
        
        NSLog(@"[AetherFilm] Buffers OK: %dx%d", w, h);
    
    // Build params struct
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
        float ppR, ppG, ppB;
        int printStock;
        float bleachPrint;
        float neutralPrint;
        int displayTgt;
    };
    
    MetalColorParams cp;
    cp.inputCS = inputCS_;
    cp.textureOnly = textureOnly_;
    cp.negStock = negStock_;
    cp.exposure = exposure_;
    cp.enableDev = enableDev_;
    cp.pushPull = pushPull_;
    cp.interlayer = interlayer_;
    cp.bleachNeg = bleachNeg_;
    cp.neutralNeg = neutralNeg_;
    cp.enablePrint = enablePrint_;
    cp.ppR = ppR_; cp.ppG = ppG_; cp.ppB = ppB_;
    cp.printStock = printStock_;
    cp.bleachPrint = bleachPrint_;
    cp.neutralPrint = neutralPrint_;
    cp.displayTgt = displayTgt_;
    
    // Encode compute command using buffers (OFX standard)
    id<MTLCommandBuffer> cmdBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmdBuffer computeCommandEncoder];
    
    // Set buffers (OFX standard: input=buffer(0), output=buffer(8), width=buffer(11), height=buffer(12))
    [encoder setBuffer:srcBuffer offset:0 atIndex:0];
    [encoder setBuffer:dstBuffer offset:0 atIndex:8];
    [encoder setBytes:&w length:sizeof(w) atIndex:11];
    [encoder setBytes:&h length:sizeof(h) atIndex:12];
    
    // Set params (buffer 1-4)
    [encoder setBytes:&cp length:sizeof(cp) atIndex:1];
    
    // Set HD params (buffer 2-4)
    struct MetalHDParams {
        float toeR, shoulderR, gammaR;
        float toeG, shoulderG, gammaG;
        float toeB, shoulderB, gammaB;
    };
    
    MetalHDParams mNegHD = {negHD_.toeR, negHD_.shoulderR, negHD_.gammaR,
                            negHD_.toeG, negHD_.shoulderG, negHD_.gammaG,
                            negHD_.toeB, negHD_.shoulderB, negHD_.gammaB};
    MetalHDParams mPrintHD = {printHD_.toeR, printHD_.shoulderR, printHD_.gammaR,
                              printHD_.toeG, printHD_.shoulderG, printHD_.gammaG,
                              printHD_.toeB, printHD_.shoulderB, printHD_.gammaB};
    MetalHDParams mCt = {ct_.m[0][0], ct_.m[0][1], ct_.m[0][2],
                         ct_.m[1][0], ct_.m[1][1], ct_.m[1][2],
                         ct_.m[2][0], ct_.m[2][1], ct_.m[2][2]};
    
    [encoder setBytes:&mNegHD length:sizeof(mNegHD) atIndex:2];
    [encoder setBytes:&mCt length:sizeof(mCt) atIndex:3];
    [encoder setBytes:&mPrintHD length:sizeof(mPrintHD) atIndex:4];
    
    [encoder setComputePipelineState:gPsoColorScience];
    
    MTLSize threadGroups = MTLSizeMake((w + 15) / 16, (h + 15) / 16, 1);
    MTLSize threadGroupSize = MTLSizeMake(16, 16, 1);
    [encoder dispatchThreadgroups:threadGroups threadsPerThreadgroup:threadGroupSize];
    
    [encoder endEncoding];
    
    [cmdBuffer commit];
    [cmdBuffer waitUntilCompleted];
    
    if (logFile) { fprintf(logFile, "[AetherFilm] Metal render completed!\n"); fclose(logFile); }
    }
}
