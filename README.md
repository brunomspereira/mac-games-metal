# Mac Games Metal

A native Swift/AppKit launcher for GTA IV on Apple silicon, using a local Wine
engine and the experimental D9MT Direct3D 9 → Metal driver. The tested setup
combines Metal, MSync, and forced VSync. It reached **65.03 average FPS at
2560×1440 with High graphics** on an Apple M5 Mac; see [TESTING.md](TESTING.md).

This is the separate private source repository for the working Metal setup.
It contains the launcher, icon, shader/GPU preflight, launch configuration,
license notices, and setup documentation. Game files, Wine/D9MT runtime binaries,
Windows environments, saves, personal settings, logs, and built apps are excluded.
It does not implement a Windows compatibility engine from scratch.

## Current local installation

Double-click **Mac Games Metal.app** in **Desktop → Games**, then click **Play**.
The Finder alias opens the existing **Mac Games Metal Test.app** in the original
workspace's `outputs/MetalTrial` directory. Keep the app and its Runtime and
LauncherData folders together. Creating this repository did not move the app
or change its game files or saves.

The original **Mac Games.app** shortcut still opens the OpenGL fallback. Metal
has its own game copy, Windows environment, settings, logs, and saves. Saves
were copied when the trial was created; subsequent progress is separate and
does not synchronize automatically between the two installations.

## Build and configuration

Follow [SETUP.md](SETUP.md) to prepare a local runtime and your own game copy,
then run `zsh source/build-metal.sh`. A fresh clone alone is not a playable game
installation. The build creates `MetalTrial/Mac Games Metal Test.app`, compiles
and signs the native launcher and GPU preflight, and runs its self-checks.

- `config/dxvk.conf`: forces VSync with `d3d9.presentInterval = 1`.
- `config/commandline.txt`: initial windowed 1920×1080 display settings.
- Game and prefix paths are relative to the app's containing folder.
- `--self-test` checks executable validation, literal process arguments,
  launch errors, exit statuses, and the selected graphics environment.
- Before Wine starts, the Metal helper compiles a shader, executes it on the
  GPU, and verifies the readback. Errors go to the installation's `LauncherData/latest.log`.

Other games have not been validated. The launcher currently uses one Windows
environment per installation, and its Metal configuration is targeted at GTA IV.

## Runtime provenance

- [Wine](https://github.com/wine-mirror/wine) and
  [CodeWeavers open sources](https://www.codeweavers.com/crossover/source).
- [Sikarugir engine release](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0):
  Wine 9.0 / SikarugirCX 24.0.7.
- [D9MT](https://github.com/neo773/d9mt), source commit
  `237e2935e58355d1ee41fda097e1af272d5f62f0`, built with `RELEASE=1`.
- [DXMT v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80): winemetal bridge.
- D9MT uses the DXVK front end and SPIRV-Cross. The companion ABI header in
  `source/d9mtmetal.h` is from D9MT; applicable third-party notices are in `LICENSES`.

This is a personal development setup. Long-session stability and save/load have
not been independently tested. Wine runs with the user's permissions and is
not a security sandbox.
