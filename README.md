# AetherFilm

Open-source film emulation plugin for DaVinci Resolve (OpenFX).

## Features

- **Negative stocks**: Kodak Vision3 250D/500T, Fuji Eterna 500T, Kodak Double-X
- **Print stocks**: Kodak 2383/2393, Fuji 3510
- **Printer points**: Traditional color timing
- **Push/Pull development**: Over/under-development simulation
- **Interlayer effect**: Dye cloud crosstalk
- **Bleach bypass**: Silver retention effect
- **Halation**: Red bloom on highlights with film gauge presets (35mm, 16mm, Super 8)

## Requirements

- DaVinci Resolve 17+ (Metal support)
- macOS 10.15+
- CMake 3.15+

## Build

```bash
mkdir build && cd build
cmake ..
make
```

Install the resulting `.ofx.bundle` to `/Library/OFX/Plugins/`.

## Recent Changes

### v1.1 — HDR Highlight Preservation

**Fixed overexposure issue:**
- Removed premature clamping in H&D curves, printer points, and display gamma
- Added soft-clip function for smooth HDR highlight compression before display gamma
- Values > 1.0 are now preserved through the pipeline instead of being clipped

**Performance improvements:**
- CPU fallback now uses persistent buffers instead of per-frame allocation
- Reduces ~132 MB allocation per frame to zero (after first frame)

## License

MIT
