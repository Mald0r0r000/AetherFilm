#pragma once
#include "ofxsProcessing.h"
#include "ofxsImageEffect.h"
#include "ColorScience.h"
#include <vector>

class AetherFilmProcessor : public OFX::ImageProcessor
{
public:
    AetherFilmProcessor(OFX::ImageEffect *instance, const OFX::RenderArguments &args);
    
    void setParams(int inputCS, bool textureOnly, int negStock, float exposure,
                   bool enableDev, float pushPull, float interlayer, float bleachNeg, float neutralNeg,
                   bool enablePrint, float ppR, float ppG, float ppB, int printStock,
                   float bleachPrint, float neutralPrint, int displayTgt);
    
    void setHalation(bool enable, int mode, int gauge, float strength, float3 color);
    
    // Set source image
    void setSrcImg(OFX::Image *img) { _srcImg = img; }
    
    // CPU processing
    void multiThreadProcessImages(OfxRectI window) override;
    
    // GPU Metal processing
    void processImagesMetal() override;
    
private:
    // Parameters
    int inputCS_;
    bool textureOnly_;
    int negStock_;
    float exposure_;
    bool enableDev_;
    float pushPull_, interlayer_, bleachNeg_, neutralNeg_;
    bool enablePrint_;
    float ppR_, ppG_, ppB_;
    int printStock_;
    float bleachPrint_, neutralPrint_;
    int displayTgt_;
    
    // Halation
    bool enableHal_;
    int halMode_, halGauge_;
    float halStrength_;
    float3 halColor_;
    
    // Stock params
    HDParams negHD_, printHD_;
    CrosstalkMatrix ct_;
    
    // Source image (dst is _dstImg from base class)
    OFX::Image *_srcImg;
    
    // Intermediate buffers for halation
    std::vector<float> processBuffer_;
    std::vector<float> halationBuffer_;
    int width_, height_;
};
