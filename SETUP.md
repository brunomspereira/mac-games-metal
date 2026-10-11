# Prepare a separate Metal installation

Use an Apple silicon Mac with Rosetta, Apple's command-line developer tools,
Python 3, and your own legally obtained GTA IV game files. The working local
setup is on an M5 Mac with macOS 27.0.1. If Rosetta is missing, open
`Install Rosetta.command` and accept Apple's license.

This source repository excludes the runtime and game binaries. Its build script
expects the following directories beneath the repository root:

```text
MetalTrial/
  Runtime/
    WineCX/bin/wine
    WineCX/bin/wineserver
    WineCX/lib/wine/...
    Frameworks/...
  LauncherData/
    Game/GTAIV/GTAIV.exe
    Game/GTAIV/d3d9.dll
```

The currently working installation already exists in the original workspace's
`outputs/MetalTrial` folder. The Desktop/Games Finder alias points there. This
repository is a source snapshot; rebuilding here creates a different local app
and does not update the original installation automatically.

## Base runtime

Download and verify these matching assets:

| Asset | Source | SHA-256 |
| --- | --- | --- |
| `WS12WineCX24.0.7_7.tar.xz` | [Engines v1.0](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0) | `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c` |
| `Template-1.0.21.tar.xz` | [Template v1.0](https://github.com/Sikarugir-App/Template/releases/tag/v1.0) | `bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d` |
| `dxmt-v0.80-builtin.tar.gz` | [DXMT v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80) | `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d` |

Extract the engine and copy the contents of `wswine.bundle` into
`MetalTrial/Runtime/WineCX`. From the template's `Contents/Frameworks`, copy all
top-level files and symlinks plus the complete `GStreamer.framework` directory
into `MetalTrial/Runtime/Frameworks`. Preserve symlinks. Other template GUI,
renderer, and framework directories are not needed.

## D9MT driver and bridge

Use [D9MT](https://github.com/neo773/d9mt) at commit
`237e2935e58355d1ee41fda097e1af272d5f62f0`. Its build requires mingw-w64 and
glslang; the local build used versions 14.0.0_3 and 16.6.0 respectively. Follow
the upstream release-build instructions, using the verified DXMT v0.80
winemetal binaries to generate the 32-bit import library.

The upstream companion build script normally deploys directly into CrossOver
and a bottle. For this isolated setup, perform only its compilation steps and
copy the resulting files to these locations:

| Artifact | Destination |
| --- | --- |
| Release `d3d9fe.dll` | `MetalTrial/LauncherData/Game/GTAIV/d3d9.dll` |
| DXMT 32-bit `winemetal.dll` | `WineCX/lib/wine/i386-windows/winemetal.dll` |
| DXMT 64-bit `winemetal.dll` | `WineCX/lib/wine/x86_64-windows/winemetal.dll` |
| Built 32-bit `d9mtmetal.dll` | `WineCX/lib/wine/i386-windows/d9mtmetal.dll` |
| Built 64-bit `d9mtmetal.dll` | `WineCX/lib/wine/x86_64-windows/d9mtmetal.dll` |
| `winemetal.so` and built `d9mtmetal.so` | Each of `WineCX/lib/wine/x86_64-unix`, `i386-windows`, and `x86_64-windows` |

In that table, `WineCX` is under `MetalTrial/Runtime`. Retain the upstream
license notices alongside the deployed runtime. The native companions are
x86_64 Mach-O libraries because Wine's native side runs under Rosetta. This
D9MT revision compiles shaders through the system Metal compiler service; the
local setup did not install full Xcode or the separate Metal command-line toolchain.
No x87 sidecar or macOS developer/security-setting change is required for this setup.

## Game, configuration, and launch

1. Copy your complete GTA IV game directory into `MetalTrial/LauncherData/Game/GTAIV`.
   Retain its required data files. The Metal driver occupies `d3d9.dll` in that
   copy; preserve any existing driver DLL before replacing it.
2. Apply `config/dxvk.conf` and `config/commandline.txt` to the same game folder.
   Review and merge existing configuration rather than overwriting it.
3. Before first launch, create local Documents, Desktop, Downloads, Music,
   Pictures, and Videos directories under
   `MetalTrial/LauncherData/Windows-Metal/drive_c/users/crossover` and the current
   Mac username's corresponding Windows user folder. This prevents the test's
   default user folders from pointing to the Mac's folders.
4. Run `zsh source/build-metal.sh`, then open the built app in your normal Mac session.
   The app initializes its Windows environment and installs the matching builtin
   bridge DLLs before writing the successful-initialization marker.
5. Click Play. The first run may take extra time for setup and shader compilation.
   Use Show Log for actual startup or GPU-preflight failures.

The launcher sets MSync on, ESync off, native D3D9, builtin winemetal/d9mtmetal,
and the GTA IV-specific atiadlxx override. Forced VSync is supplied by dxvk.conf.
Copy saves only while the game is fully closed, and preserve the source saves;
separate installations do not synchronize progress automatically.
