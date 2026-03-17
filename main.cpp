#include "AetherFilmPlugin.h"
#include "ofxsImageEffect.h"

mDeclarePluginFactory(AetherFilmPluginFactory, {}, {});

void AetherFilmPluginFactory::describe(OFX::ImageEffectDescriptor &desc)
{
    desc.setLabel("AetherFilm");
    desc.setPluginGrouping("Aether");
    desc.setPluginDescription(
        "Open-source film emulation — negative stock, print stock, "
        "printer points, push/pull, bleach bypass, halation. "
        "github.com/aether/AetherFilmOFX");

    desc.addSupportedContext(OFX::eContextFilter);
    desc.addSupportedContext(OFX::eContextGeneral);
    desc.addSupportedBitDepth(OFX::eBitDepthUByte);
    desc.addSupportedBitDepth(OFX::eBitDepthUShort);
    desc.addSupportedBitDepth(OFX::eBitDepthFloat);
    desc.setSingleInstance(false);
    desc.setHostFrameThreading(false);
    desc.setSupportsMultiResolution(true);
    desc.setSupportsTiles(true);
    desc.setTemporalClipAccess(false);
    desc.setRenderTwiceAlways(false);
    desc.setSupportsMultipleClipDepths(false);
    
    // Advertise Metal render support - must be in describe(), not describeInContext
    desc.setSupportsMetalRender(true);
}

void AetherFilmPluginFactory::describeInContext(OFX::ImageEffectDescriptor &desc,
                                                OFX::ContextEnum /*ctx*/)
{
    // Advertise Metal render support
    desc.setSupportsMetalRender(true);
    
    // ── Clips ──────────────────────────────────────────────────────────────
    OFX::ClipDescriptor *src = desc.defineClip(kOfxImageEffectSimpleSourceClipName);
    src->addSupportedComponent(OFX::ePixelComponentRGBA);
    src->setTemporalClipAccess(false);
    src->setSupportsTiles(true);
    src->setIsMask(false);

    OFX::ClipDescriptor *dst = desc.defineClip(kOfxImageEffectOutputClipName);
    dst->addSupportedComponent(OFX::ePixelComponentRGBA);
    dst->setSupportsTiles(true);

    // ── Input group ────────────────────────────────────────────────────────
    {
        OFX::GroupParamDescriptor *g = desc.defineGroupParam("grpInput");
        g->setLabel("Input"); g->setOpen(true);

        auto *p = desc.defineChoiceParam(kParamInputColorSpace);
        p->setLabel("Input colour space");
        p->appendOption("DaVinci Wide Gamut / Intermediate");
        p->appendOption("REDWideGamut / Log3G10");
        p->appendOption("ARRI LogC3 / AWG");
        p->appendOption("Sony S-Log3 / SGamut3.Cine");
        p->appendOption("Linear / Scene");
        p->setDefault(0); p->setAnimates(false); p->setParent(*g);

        auto *t = desc.defineBooleanParam(kParamTextureOnly);
        t->setLabel("Texture-only mode");
        t->setHint("Bypass colour science, apply halation only.");
        t->setDefault(false); t->setAnimates(false); t->setParent(*g);
    }

    // ── Camera group ───────────────────────────────────────────────────────
    {
        OFX::GroupParamDescriptor *g = desc.defineGroupParam("grpCamera");
        g->setLabel("Camera"); g->setOpen(true);

        auto *ns = desc.defineChoiceParam(kParamNegStock);
        ns->setLabel("Negative stock");
        ns->appendOption("Kodak Vision3 250D 5207");
        ns->appendOption("Kodak Vision3 500T 5219");
        ns->appendOption("Fuji Eterna 500T 8673");
        ns->appendOption("Kodak Double-X 5222");
        ns->setDefault(0); ns->setAnimates(false); ns->setParent(*g);

        auto *ex = desc.defineDoubleParam(kParamExposure);
        ex->setLabel("Exposure");
        ex->setRange(-4.0, 4.0); ex->setDisplayRange(-3.0, 3.0);
        ex->setDefault(0.0); ex->setParent(*g);
    }

    // ── Development group ──────────────────────────────────────────────────
    {
        OFX::GroupParamDescriptor *g = desc.defineGroupParam("grpDev");
        g->setLabel("Development"); g->setOpen(true);

        auto *en = desc.defineBooleanParam(kParamEnableDev);
        en->setLabel("Enable development"); en->setDefault(true);
        en->setAnimates(false); en->setParent(*g);

        auto *pp = desc.defineDoubleParam(kParamPushPull);
        pp->setLabel("Push / Pull");
        pp->setHint("Over/under-development. Modifies contrast and saturation per channel.");
        pp->setRange(-3.0, 3.0); pp->setDisplayRange(-2.0, 2.0);
        pp->setDefault(0.0); pp->setParent(*g);

        auto *il = desc.defineDoubleParam(kParamInterlayer);
        il->setLabel("Interlayer effect");
        il->setRange(0.0, 1.0); il->setDisplayRange(0.0, 1.0);
        il->setDefault(1.0); il->setParent(*g);

        auto *bn = desc.defineDoubleParam(kParamBleachNeg);
        bn->setLabel("Bleach bypass");
        bn->setRange(0.0, 1.0); bn->setDisplayRange(0.0, 1.0);
        bn->setDefault(0.0); bn->setParent(*g);

        auto *nn = desc.defineDoubleParam(kParamNeutralNeg);
        nn->setLabel("Neutral neg curves");
        nn->setHint("0 = real stock curves, 1 = channel-aligned neutral.");
        nn->setRange(0.0, 1.0); nn->setDisplayRange(0.0, 1.0);
        nn->setDefault(0.0); nn->setParent(*g);
    }

    // ── Print group ────────────────────────────────────────────────────────
    {
        OFX::GroupParamDescriptor *g = desc.defineGroupParam("grpPrint");
        g->setLabel("Print"); g->setOpen(true);

        auto *ep = desc.defineBooleanParam(kParamEnablePrint);
        ep->setLabel("Enable printer points"); ep->setDefault(true);
        ep->setAnimates(false); ep->setParent(*g);

        auto *gp = desc.defineBooleanParam(kParamGangPrinter);
        gp->setLabel("Gang printer points");
        gp->setHint("Link R/G/B for exposure-only control.");
        gp->setDefault(false); gp->setAnimates(false); gp->setParent(*g);

        auto mkPP = [&](const char *name, const char *label) {
            auto *p = desc.defineDoubleParam(name);
            p->setLabel(label);
            p->setRange(0.0, 50.0); p->setDisplayRange(0.0, 50.0);
            p->setDefault(25.0); p->setParent(*g);
        };
        mkPP(kParamPrinterR, "Red printer points");
        mkPP(kParamPrinterG, "Green printer points");
        mkPP(kParamPrinterB, "Blue printer points");

        auto *ps = desc.defineChoiceParam(kParamPrintStock);
        ps->setLabel("Print stock");
        ps->appendOption("Kodak Vision Color 2383");
        ps->appendOption("Kodak Vision Color 2393");
        ps->appendOption("Fuji FP 3510");
        ps->setDefault(0); ps->setAnimates(false); ps->setParent(*g);

        auto *bp = desc.defineDoubleParam(kParamBleachPrint);
        bp->setLabel("Print bleach bypass");
        bp->setRange(0.0, 1.0); bp->setDisplayRange(0.0, 1.0);
        bp->setDefault(0.0); bp->setParent(*g);

        auto *np = desc.defineDoubleParam(kParamNeutralPrint);
        np->setLabel("Neutral print curves");
        np->setRange(0.0, 1.0); np->setDisplayRange(0.0, 1.0);
        np->setDefault(0.0); np->setParent(*g);

        auto *dt = desc.defineChoiceParam(kParamDisplayTarget);
        dt->setLabel("Display target");
        dt->appendOption("Rec.709 / Gamma 2.4");
        dt->appendOption("Rec.709 / Gamma 2.2");
        dt->appendOption("P3 D65 / Gamma 2.6");
        dt->appendOption("Linear");
        dt->setDefault(0); dt->setAnimates(false); dt->setParent(*g);
    }

    // ── Halation group ─────────────────────────────────────────────────────
    {
        OFX::GroupParamDescriptor *g = desc.defineGroupParam("grpHalation");
        g->setLabel("Halation"); g->setOpen(false);

        auto *eh = desc.defineBooleanParam(kParamEnableHalation);
        eh->setLabel("Enable halation"); eh->setDefault(true);
        eh->setAnimates(false); eh->setParent(*g);

        auto *hm = desc.defineChoiceParam(kParamHalationMode);
        hm->setLabel("Mode");
        hm->appendOption("Performance");
        hm->appendOption("Precision");
        hm->setDefault(0); hm->setAnimates(false); hm->setParent(*g);

        auto *hg = desc.defineChoiceParam(kParamHalationGauge);
        hg->setLabel("Film gauge");
        hg->appendOption("35mm");
        hg->appendOption("16mm");
        hg->appendOption("Super 8");
        hg->setDefault(0); hg->setAnimates(false); hg->setParent(*g);

        auto *hs = desc.defineDoubleParam(kParamHalationStrength);
        hs->setLabel("Strength");
        hs->setRange(0.0, 2.0); hs->setDisplayRange(0.0, 2.0);
        hs->setDefault(1.0); hs->setParent(*g);

        auto *hc = desc.defineRGBParam(kParamHalationColor);
        hc->setLabel("Tint");
        hc->setHint("Halation bloom colour (typically deep red).");
        hc->setDefault(0.85, 0.15, 0.05); hc->setParent(*g);
    }
}

OFX::ImageEffect *AetherFilmPluginFactory::createInstance(OfxImageEffectHandle h,
                                                           OFX::ContextEnum)
{
    return new AetherFilmPlugin(h);
}

void OFX::Plugin::getPluginIDs(OFX::PluginFactoryArray &ids)
{
    static AetherFilmPluginFactory p("com.maldoror.aetherfilm", 1, 0);
    ids.push_back(&p);
}
