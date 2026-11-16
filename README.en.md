# Beyond the Basin

[简体中文](README.md)

Beyond the Basin, also called PoolCore, is a pool-space exploration game in development. Walk through empty baths, galleries and service rooms. Listen to footsteps, moving water and distant echoes. Disturb the water, carry floating objects, explore freely or restore facilities through a six-chapter campaign. Relaxed mode removes timed erosion.

The main branch contains the Godot project. The earlier browser version remains on the legacy branch. [Legacy Web source](https://github.com/YBZSG/beyond-the-basin/tree/legacy/web-20261026)

## Download and play

Windows 0.6.14 includes the homepage, 15 independent Dreamcore maps, Chinese and English interfaces, and the 20 delivered updates collected on October 31. Extract the entire ZIP and run `Launch-PoolCore.cmd`. Use `Launch-Connected-Halls.cmd` for the continuous Hanging Hand → Maintenance Link → Aquarium Atrium preview. [Windows download](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.14-pc-20261116/PoolCore-Windows-0.6.14.zip) · [itch.io](https://ybzsg.itch.io/beyond-the-basin)

Choose English from **语言 / Language** at the top right of the homepage. The language preference saves automatically. Settings and saves are stored in the `profile` folder beside the game.

Windows 10/11 x64 and a Vulkan-capable GPU are required. The first launch prepares shaders and scene resources.

The Android ARM64 preview remains at its existing release version. [Android download](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.4-android)

## Controls

| Action | Input |
| --- | --- |
| Move / Look | WASD / Mouse |
| Run / Jump | Shift / Space |
| Operate equipment / Read campaign plate | E / Q |
| Grab / Charge throw / Adjust distance | Left mouse / Right mouse / Wheel |
| Flashlight / Change lens | L / F |
| Show hints | Hold Tab |
| Hide HUD / Fullscreen / Pause | H / F11 / Esc |

The homepage offers the original pools, main pool hall, expanded maps, Poolrooms wing, reference wing and 15 Dreamcore maps. The Dreamcore maps use separate progress. Current spaces focus on shallow-water exploration. Grass gradually recovers after being trampled.

Camera filters include halation, colour fringing and a timestamp. Large waves have an independent toggle. Footstep and wading ripples remain active when large waves are off. The viewfinder's REC label is decorative.

Path tracing, DLSS, Frame Generation and Neural Rendering are optional experimental features requiring compatible hardware, drivers and the custom engine. Path tracing, Frame Generation and NR start disabled. NR and Frame Generation are mutually exclusive. Water uses raster reflection and refraction. Frame Generation can still produce visible distortion.

## Run the source

Use the existing `PoolCoreEditor.exe`, or obtain it from the 0.6.13 Windows installer. This release retains the same custom Godot 4.8-dev engine. [Editor-containing installer](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.13-pc-20261026/PoolCore-PC-0.6.13-Setup.exe)

1. Clone or extract this repository.
2. Open `Open-Editor.cmd`. For a custom engine location, drag `PoolCoreEditor.exe` onto that CMD file.
3. Wait for resource imports, then press F5.
4. Use `Run-Source.cmd` for later runs.

Keep the engine's DLL files alongside its executable. Let the editor import resources on a new machine. The project entry is `project.godot` and the main scene is `scenes/main.tscn`. The enabled export plugin includes the original Glasswell coat images required by its runtime material loader. [Engine build guide](docs/BUILDING-WINDOWS.md)

The public source and Windows package provide the original explorer. Optional ithappy model files remain local to the development machine. [Character source record](source_provenance/ithappy/README.md)

## Development and credits

Game code lives in `scripts/`, scenes in `scenes/`, shaders in `shaders/` and assets in `assets/`. Translation messages are in `assets/translations/en.po`. The custom engine patches are in `tools/dlss/`.

Terrain cache files under `assets/cache/source_terrain/` are intentional runtime inputs. Geometry and water-depth changes must use matching terrain data.

This remains a development release. Complete campaign playthroughs and cross-device compatibility testing remain pending. Asset and third-party code licences are recorded with their sources. [Credits](CREDITS.md) · [Water licences](docs/SOURCE_LIQUID_LICENSES.md)
