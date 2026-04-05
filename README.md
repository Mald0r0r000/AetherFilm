# AetherFilm

Open-source film emulation plugin for DaVinci Resolve (OpenFX).

## Features

- **Negative stocks**: Kodak Vision3 250D/500T, Fuji Eterna 500T, Kodak Double-X
- **Print stocks**: Kodak 2383/2393, Fuji 3510
- **Printer points**: Traditional color timing (0-100 range, 50 = neutral)
- **Push/Pull development**: Over/under-development simulation
- **Interlayer effect**: Dye cloud crosstalk
- **Bleach bypass**: Silver retention effect
- **GPU acceleration**: Apple Metal support for real-time processing

## Requirements

- DaVinci Resolve 17+ (Metal support)
- macOS 10.15+
- CMake 3.15+
- Xcode Command Line Tools

## Installation

### Option 1: Pre-built Release

1. Download the latest release from [Releases](https://github.com/Mald0r0r000/AetherFilm/releases)
2. Copy `AetherFilmOFX.ofx.bundle` to `/Library/OFX/Plugins/`
3. Restart DaVinci Resolve

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/Mald0r0r000/AetherFilm.git
cd AetherFilm

# Build
mkdir build && cd build
cmake ..
make -j8

# Install (requires sudo)
sudo cp -R ~/Library/OFX/Plugins/AetherFilmOFX.ofx.bundle /Library/OFX/Plugins/
```

## Usage

1. Apply **AetherFilm** from the OFX effects panel in DaVinci Resolve
2. Select your **Input Color Space** (DaVinci Wide Gamut, RED, ARRI, Sony, Linear)
3. Choose a **Negative Stock** (film stock used during capture)
4. Adjust **Development** parameters (Push/Pull, Interlayer, Bleach Bypass)
5. Set **Printer Points** for color timing (R/G/B controls)
6. Choose a **Print Stock** (2383, 2393, Fuji 3510)
7. Select **Display Target** (Rec.709, P3, Linear)

## Parameters

### Input
- **Input Color Space**: Source color space for proper conversion
- **Texture-only mode**: Bypass color science for texture effects only

### Camera
- **Negative Stock**: Film stock simulation (Kodak 250D, 500T, Fuji Eterna, Double-X)
- **Exposure**: Exposure compensation

### Development
- **Push/Pull**: Over/under-development (-3 to +3 stops)
- **Interlayer effect**: Dye cloud crosstalk simulation
- **Bleach bypass**: Silver retention for desaturated look
- **Neutral neg curves**: Channel-aligned neutral curves

### Print
- **Enable printer points**: Traditional color timing
- **Gang printer points**: Link R/G/B for exposure-only control
- **Red/Green/Blue printer points**: Color timing (50 = neutral)
- **Print Stock**: Final print stock (2383, 2393, Fuji 3510)
- **Bleach bypass (print)**: Silver retention on print
- **Neutral print curves**: Channel-aligned neutral curves
- **Display target**: Output color space

## Troubleshooting

**Plugin not appearing in Resolve:**
- Ensure the plugin is installed in `/Library/OFX/Plugins/`
- Restart DaVinci Resolve after installation
- Check that Metal is enabled in Resolve preferences

**Performance issues:**
- The plugin uses GPU Metal acceleration by default
- Falls back to CPU if Metal is unavailable

## Recent Changes

### v1.2 — Stability Improvements
- Removed halation module (caused memory issues and instability)
- Improved GPU buffer management
- Cleaner parameter controls

### v1.1 — HDR Highlight Preservation
- Fixed overexposure issue with soft-clip function
- Values > 1.0 now preserved through pipeline
- Performance improvements with persistent buffers

## License

MIT

## Credits

Based on film stock research and color science from various sources.
