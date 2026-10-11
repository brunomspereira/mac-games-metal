# Verification — 11 October 2026

GTA IV starts and renders through the D9MT Metal backend on the user's Apple M5.
The user reported that the final Metal + MSync + VSync setup looks all good and
much better than the original OpenGL setup.

| Backend | Resolution | Graphics | Average FPS |
| --- | --- | --- | --- |
| OpenGL + MSync | 1920×1080 | Low; Night Shadows off | 47.59 |
| OpenGL + MSync | 1024×576 | Low; Night Shadows off | 48.61 |
| D9MT + MSync | 2560×1440 | Low; Night Shadows off | 64.96 |
| D9MT + MSync | 2560×1440 | High; Night Shadows Medium | 65.03 |

All reports use anisotropic x4, View Distance 25, and Detail Distance 31.
These average-FPS results were recorded before forcing VSync. Different
resolutions and settings prevent treating them as a controlled driver-only
performance comparison. The game's negative CPU-usage readings are invalid
telemetry; its reported GPU identity is a compatibility-layer identity.

Passed checks:

- D9MT release driver and 32/64-bit builtin companion DLL compilation.
- Native arm64 Swift/AppKit launcher compilation, signing, and self-checks.
- PE validation, literal subprocess arguments, launch errors, and exit statuses.
- Metal-versus-OpenGL environment selection, MSync/ESync configuration.
- 216 native dependency resolutions and Wine/wineserver version startup.
- In a normal Mac session: D9MT companion loads under Rosetta, compiles a shader,
  executes it on Apple M5, and reads back the expected result.
- Game log confirms `d9mt: DxvkInstance (Metal backend), game: GTAIV.exe`.
- VSync config loaded: `Found config file: dxvk.conf` and `d3d9.presentInterval = 1`.

The user had reported stationary horizontal bands that remained with Definition
On and Shadow Quality Off. After the forced-VSync test, the user reported good
visuals. This confirms the observed outcome but does not establish the precise
cause of the bands. No shader or renderer DLL was patched for that issue.

The automated command sandbox exposes no Metal device and prevents Wine's Mach
server registration; gameplay validation was performed by the user in their
normal Mac session. No FPS after forcing VSync, minimum FPS, frame-time spikes,
long-session stability, save/load, audio, input, or other-game compatibility have
been independently measured.
