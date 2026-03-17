#pragma once
#include "ofxsImageEffect.h"
#include "ofxsMultiThread.h"
#include "AetherParams.h"
#include "ColorScience.h"
#include "Halation.h"
#include <mutex>

class AetherFilmPlugin : public OFX::ImageEffect
{
public:
    explicit AetherFilmPlugin(OfxImageEffectHandle handle);

    void render         (const OFX::RenderArguments         &args) override;
    bool isIdentity     (const OFX::IsIdentityArguments     &args,
                         OFX::Clip *&identityClip,
                         double     &identityTime)                 override;
    void getClipPreferences(OFX::ClipPreferencesSetter      &prefs) override;

private:
    // ── Clips ──────────────────────────────────────────────────────────────
    OFX::Clip *srcClip_;
    OFX::Clip *dstClip_;

    // ── Input params ───────────────────────────────────────────────────────
    OFX::ChoiceParam  *inputCSParam_;
    OFX::BooleanParam *textureOnlyParam_;

    // ── Camera params ──────────────────────────────────────────────────────
    OFX::ChoiceParam  *negStockParam_;
    OFX::DoubleParam  *exposureParam_;

    // ── Development params ─────────────────────────────────────────────────
    OFX::BooleanParam *enableDevParam_;
    OFX::DoubleParam  *pushPullParam_;
    OFX::DoubleParam  *interlayerParam_;
    OFX::DoubleParam  *bleachNegParam_;
    OFX::DoubleParam  *neutralNegParam_;

    // ── Print params ───────────────────────────────────────────────────────
    OFX::BooleanParam *enablePrintParam_;
    OFX::BooleanParam *gangPrinterParam_;
    OFX::DoubleParam  *printerRParam_;
    OFX::DoubleParam  *printerGParam_;
    OFX::DoubleParam  *printerBParam_;
    OFX::ChoiceParam  *printStockParam_;
    OFX::DoubleParam  *bleachPrintParam_;
    OFX::DoubleParam  *neutralPrintParam_;
    OFX::ChoiceParam  *displayTargetParam_;

    // ── Halation params ────────────────────────────────────────────────────
    OFX::BooleanParam *enableHalationParam_;
    OFX::ChoiceParam  *halationModeParam_;
    OFX::ChoiceParam  *halationGaugeParam_;
    OFX::DoubleParam  *halationStrengthParam_;
    OFX::RGBParam     *halationColorParam_;

    // ── Internal ───────────────────────────────────────────────────────────
    HalationProcessor halationProcessor_;

    void processPixel(float3 &pix, double time) const;
};
