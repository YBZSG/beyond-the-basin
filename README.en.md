# Beyond the Basin

**语言 / Language**　[简体中文 / Simplified Chinese](README.md) · [English](README.en.md)

Beyond the Basin, also called PoolCore, is a pool-space exploration game in development. Walk through empty baths, galleries and service rooms. Listen to footsteps, moving water and distant echoes. Disturb the water, carry floating objects, explore freely or restore facilities through a six-chapter campaign. Relaxed mode removes timed erosion.

The main branch contains the Godot project. The earlier browser version remains on the legacy branch. [Legacy Web source](https://github.com/YBZSG/beyond-the-basin/tree/legacy/web-20261026)

## Download and play

| Platform | Download | Version |
| --- | --- | --- |
| Windows x64 | [Portable ZIP](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.14-pc-20261116/PoolCore-Windows-0.6.14.zip) · [Release notes](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.14-pc-20261116) | 0.6.14 |
| Android ARM64 | [APK](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.4-android/PoolCore-Mobile-8400-AvatarFix.apk) · [Installation guide](https://github.com/YBZSG/beyond-the-basin/releases/tag/v0.6.4-android) | 0.6.4 preview |
| Source | [Main branch ZIP](https://github.com/YBZSG/beyond-the-basin/archive/refs/heads/main.zip) | In development |

Windows 0.6.14 includes the homepage, 15 independent Dreamcore maps, Chinese and English interfaces, and the 20 delivered updates collected on October 31. Extract the entire ZIP and run `Launch-PoolCore.cmd`. Use `Launch-Connected-Halls.cmd` for the continuous Hanging Hand → Maintenance Link → Aquarium Atrium preview. The Windows build is also available on itch.io. [itch.io download](https://ybzsg.itch.io/beyond-the-basin)

Choose English from **语言 / Language** at the top right of the homepage. The language preference saves automatically. Settings and saves are stored in the `profile` folder beside the game.

Windows 10/11 x64 and a Vulkan-capable GPU are required. The first launch prepares shaders and scene resources.

The Android preview provides touch controls, defaults to High quality and caps the frame rate at 30 FPS. Its settings can be adjusted in the menu. It retains water ripples, refraction, caustics and reflections while omitting volumetric splashes. Development testing used a Dimensity 8400 phone with 12 GB of RAM and an RTX 5070 Laptop PC. The `8400` in the APK filename comes from its earlier naming.

The Windows and Android packages follow separate release schedules. To play directly, download the Windows ZIP or Android APK. The source ZIP opens in the editor.

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

Valves, switches and some facilities can be operated. Floating objects, ballpit balls and cushions can be moved, picked up or thrown. Open Settings on the homepage to choose a character and adjust graphics and water.

Camera filters include halation, colour fringing and a timestamp. Large waves have an independent toggle. Footstep and wading ripples remain active when large waves are off. The viewfinder's REC label is decorative.

Path tracing, DLSS, Frame Generation and Neural Rendering are optional experimental features requiring compatible hardware, drivers and the custom engine. Path tracing, Frame Generation and NR start disabled. NR and Frame Generation are mutually exclusive. Water uses raster reflection and refraction. Frame Generation can still produce visible distortion.

## Run the source

Use the existing `PoolCoreEditor.exe`, or obtain it from the 0.6.13 Windows installer. This release retains the same custom Godot 4.8-dev engine. [Editor-containing installer](https://github.com/YBZSG/beyond-the-basin/releases/download/v0.6.13-pc-20261026/PoolCore-PC-0.6.13-Setup.exe)

1. Clone or extract this repository.

   ```powershell
   git clone https://github.com/YBZSG/beyond-the-basin.git PoolCoreSource
   cd PoolCoreSource
   ```

2. Open `Open-Editor.cmd`. For a custom engine location, drag `PoolCoreEditor.exe` onto that CMD file.
3. Wait for resource imports, then press F5.
4. Use `Run-Source.cmd` for later runs.

Keep the engine's DLL files alongside its executable. Use `PoolCoreEditor.exe` to edit source, since `PoolCore.exe` loads its adjacent game PCK. Let the editor import resources on a new machine. The project entry is [`project.godot`](project.godot) and the main scene is [`scenes/main.tscn`](scenes/main.tscn). Before updating with `git pull --ff-only`, commit or back up your own changes.

The enabled export plugin includes the original Glasswell coat images required by its runtime material loader. The project's native path tracing, DLSS and NR interfaces are provided by its custom engine. [Engine build guide](docs/BUILDING-WINDOWS.md)

The public source and Windows package provide the original explorer. Optional ithappy model files remain local to the development machine. [Character source record](source_provenance/ithappy/README.md)

## Saves and troubleshooting

The portable Windows build stores saves and settings in `profile` beside the game. The older installer also uses `profile` under its installation directory, normally `%LOCALAPPDATA%\Programs\PoolCore`. Source runs through the supplied CMD scripts use `%LOCALAPPDATA%\PoolCore\SourceProfile`. To migrate an older portable save, close the game, back it up and copy its `profile` folder.

- **The CMD launcher cannot find the editor**. Obtain `PoolCoreEditor.exe` from the installer linked above, or drag an existing copy onto the CMD launcher.
- **Path tracing or DLSS is unavailable**. Check the explanation in the graphics menu, then verify the custom engine, drivers and adjacent DLL files. Feature availability varies by GPU.
- **A world switch produces a black screen, incorrect colours or a crash**. World transitions are still being improved. Exit and reopen through the relevant scene launcher. When reporting the issue, include the version, scene, GPU, graphics settings and `profile/PoolCore.log`.

This remains a development release. Full-map playthroughs and cross-device compatibility testing remain pending. Existing engine shutdown resource warnings and individual fix records are documented under `docs/`.

## Development resources

| Directory | Contents |
| --- | --- |
| `scripts/`, `scenes/`, `shaders/` | Gameplay, scenes, materials and post-processing |
| `assets/` | Models, textures, audio and runtime resources |
| `native/source_water/` | Water helper library and source |
| `tools/blender/` | Blender authoring, generation and export tools |
| `tools/dlss/` | Custom engine patches, dependency records and checks |
| `docs/`, `source_provenance/` | Feature guides, development records and asset sources |

Translation messages are in `assets/translations/en.po`. Terrain cache files under `assets/cache/source_terrain/` are intentional runtime inputs. Update their corresponding data when changing pool floors, collisions or water depth. Blender is used when editing models or regenerating geometry.

[Campaign guide](docs/campaign/README.md) · [Water port](docs/SOURCE_LIQUID_PORT.md) · [Water sparkle fixes](docs/RASTER-WATER-RT-NOISE.md) · [Android development notes](docs/ANDROID-8400-20261023.md)

## Sources and licences

The game continues development from the earlier Web version. The Godot project retains records of the original water algorithm port. Assets and third-party code retain their own licences, recorded in the credits and accompanying NOTICE files. Check those licences before extracting or redistributing individual assets. [Credits](CREDITS.md) · [Water licences](docs/SOURCE_LIQUID_LICENSES.md)
