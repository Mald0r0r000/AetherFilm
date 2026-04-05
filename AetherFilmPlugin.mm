#include "AetherFilmPlugin.h"
#include "Processor.h"
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
    bool textureOnly, enableDev, enablePrint;
    textureOnlyParam_->getValueAtTime(args.time, textureOnly);
    enableDevParam_->getValueAtTime(args.time, enableDev);
    enablePrintParam_->getValueAtTime(args.time, enablePrint);

    if (!textureOnly && !enableDev && !enablePrint) {
        identityClip = srcClip_;
        identityTime = args.time;
        return true;
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// render (uses OFX::ImageProcessor for proper GPU activation)
// ─────────────────────────────────────────────────────────────────────────────
void AetherFilmPlugin::render(const RenderArguments &args)
{
    // Log to file for debugging
    FILE* logFile = fopen("/tmp/aetherfilm_render.log", "a");
    if (logFile) {
        fprintf(logFile, "[AetherFilm] render called, isEnabledMetalRender=%d, pMetalCmdQ=%p\n", 
                args.isEnabledMetalRender, args.pMetalCmdQ);
        fclose(logFile);
    }
    
    // Create processor - this handles both CPU and GPU automatically
    AetherFilmProcessor processor(this, args);
    
    // Fetch all params
    int inputCS;      inputCSParam_->getValueAtTime(args.time, inputCS);
    bool textureOnly; textureOnlyParam_->getValueAtTime(args.time, textureOnly);
    int negStock;      negStockParam_->getValueAtTime(args.time, negStock);
    double exposure;   exposureParam_->getValueAtTime(args.time, exposure);
    
    bool enableDev;    enableDevParam_->getValueAtTime(args.time, enableDev);
    double pushPull;   pushPullParam_->getValueAtTime(args.time, pushPull);
    double interlayer; interlayerParam_->getValueAtTime(args.time, interlayer);
    double bleachNeg;  bleachNegParam_->getValueAtTime(args.time, bleachNeg);
    double neutralNeg; neutralNegParam_->getValueAtTime(args.time, neutralNeg);
    
    bool enablePrint;  enablePrintParam_->getValueAtTime(args.time, enablePrint);
    bool gangPrinter;  gangPrinterParam_->getValueAtTime(args.time, gangPrinter);
    double ppR, ppG, ppB;
    printerRParam_->getValueAtTime(args.time, ppR);
    printerGParam_->getValueAtTime(args.time, ppG);
    printerBParam_->getValueAtTime(args.time, ppB);
    if (gangPrinter) { ppG = ppR; ppB = ppR; }
    int printStock;    printStockParam_->getValueAtTime(args.time, printStock);
    double bleachPrint;  bleachPrintParam_->getValueAtTime(args.time, bleachPrint);
    double neutralPrint; neutralPrintParam_->getValueAtTime(args.time, neutralPrint);
    int displayTgt;    displayTargetParam_->getValueAtTime(args.time, displayTgt);
    
    // Set params on processor
    processor.setParams(inputCS, textureOnly, negStock, (float)exposure,
                        enableDev, (float)pushPull, (float)interlayer, (float)bleachNeg, (float)neutralNeg,
                        enablePrint, (float)ppR, (float)ppG, (float)ppB, printStock,
                        (float)bleachPrint, (float)neutralPrint, displayTgt);
    
    // Set source and destination images
    std::unique_ptr<Image> src(srcClip_->fetchImage(args.time));
    std::unique_ptr<Image> dst(dstClip_->fetchImage(args.time));
    if (!src || !dst) return;
    
    processor.setSrcImg(src.get());
    processor.setDstImg(dst.get());
    
    // Process - this automatically calls processImagesMetal() or multiThreadProcessImages()
    processor.process();
}
