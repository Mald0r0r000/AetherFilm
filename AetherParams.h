#pragma once

// ── Input ──────────────────────────────────────────────────────────────────
#define kParamInputColorSpace   "inputColorSpace"
#define kParamTextureOnly       "textureOnly"

// ── Camera ─────────────────────────────────────────────────────────────────
#define kParamNegStock          "negStock"
#define kParamExposure          "exposure"

// ── Development ────────────────────────────────────────────────────────────
#define kParamEnableDev         "enableDev"
#define kParamPushPull          "pushPull"
#define kParamInterlayer        "interlayer"
#define kParamBleachNeg         "bleachNeg"
#define kParamNeutralNeg        "neutralNeg"

// ── Print ──────────────────────────────────────────────────────────────────
#define kParamEnablePrint       "enablePrint"
#define kParamGangPrinter       "gangPrinter"
#define kParamPrinterR          "printerR"
#define kParamPrinterG          "printerG"
#define kParamPrinterB          "printerB"
#define kParamPrintStock        "printStock"
#define kParamBleachPrint       "bleachPrint"
#define kParamNeutralPrint      "neutralPrint"
#define kParamDisplayTarget     "displayTarget"

// ── Enum values ────────────────────────────────────────────────────────────
enum NegStock {
    kNegKodak250D = 0,
    kNegKodak500T,
    kNegFujiEterna500T,
    kNegDoubleX
};

enum PrintStock {
    kPrint2383 = 0,
    kPrint2393,
    kPrintFuji3510
};

enum InputColorSpace {
    kInputDWG = 0,
    kInputREDWG,
    kInputARRI,
    kInputSony,
    kInputLinear
};

enum DisplayTarget {
    kDisplayRec709_24 = 0,
    kDisplayRec709_22,
    kDisplayP3,
    kDisplayLinear
};
