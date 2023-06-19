# Nova64

This is a port of Super Mario 64 to the PC using Rust.
- It supports macOS, Linux, Windows.

This repo does not include all assets necessary for compiling the game.
A prior copy of the game is required to extract the assets.

## Building
We recommend building with [VSCode](https://code.visualstudio.com/) and the [CMake Tools](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cmake-tools) extension.
This will allow you to skip most of the steps below and build the game with a few clicks.

### macOS

1. Install prerequisites: `cmake, ninja, glew, libusb`.
2. Clone the repo: `git clone https://github.com/nova-port/Nova64.git`, which will create a directory `Nova64` and then **enter** it `cd Nova64`.
3. Make sure to clone the submodules: `git submodule update --init --recursive`.
4. Place a Super Mario 64 ROM called `baserom.<VERSION>.z64` into the repository's root directory for asset extraction, where `VERSION` can be `us`, `jp`, or `eu`.
5. Use cmake to build (if not using VSCode with the CMake Tools extension):
```bash
cmake -H. -Bbuild-cmake -GNinja -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --config Debug --target ExtractAssets
cmake --build build-cmake --config Debug
```
6. The executable binary will be located at `build/<VERSION>_pc/sm64.<VERSION>.f3dex2e`.

### Linux

1. Install prerequisites (Ubuntu): `sudo apt install -y git build-essential pkg-config libusb-1.0-0-dev`.
2. Clone the repo: `git clone https://github.com/nova-port/Nova64.git`, which will create a directory `Nova64` and then **enter** it `cd Nova64`.
3. Make sure to clone the submodules: `git submodule update --init --recursive`.
4. Place a Super Mario 64 ROM called `baserom.<VERSION>.z64` into the repository's root directory for asset extraction, where `VERSION` can be `us`, `jp`, or `eu`.
5. Use cmake to build (if not using VSCode with the CMake Tools extension):
```bash
cmake -H. -Bbuild-cmake -GNinja -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --config Debug --target ExtractAssets
cmake --build build-cmake --config Debug
```
6. The executable binary will be located at `build/<VERSION>_pc/sm64.<VERSION>.f3dex2e`.

### Windows
At the moment, the game only builds with mingw-w64. MSVC is not yet supported.

1. Install mingw-w64 via Chocolatey: `choco install mingw` or download it from [here](https://www.mingw-w64.org/downloads/) - make sure its in your PATH.
2. Install ninja build tool for better compilation times: `choco install ninja` or download it from [here](https://github.com/ninja-build/ninja/releases) - make sure its in your PATH.
3. Clone the repo: `git clone https://github.com/nova-port/Nova64.git`, which will create a directory `Nova64` and then **enter** it `cd Nova64`.
4. Place a *Super Mario 64* ROM called `baserom.<VERSION>.z64` into the repository's root directory for asset extraction, where `VERSION` can be `us`, `jp`, or `eu`.
5. Use cmake to build (if not using VSCode with the CMake Tools extension):
```bash
cmake -H. -Bbuild-cmake -GNinja -DCMAKE_BUILD_TYPE=Debug -DCMAKE_TOOLCHAIN_FILE:FILEPATH=cmake\\toolchain-x86_64-w64-mingw32.cmake
cmake --build build-cmake --config Debug --target ExtractAssets
cmake --build build-cmake --config Debug
```
7. The executable binary will be located at `build/<VERSION>_pc/sm64.<VERSION>.f3dex2e.exe` inside the repository.

## Input Mapping

### Keyboard
| N64 | A | B | Z | L | R | Start | Analog stick | C buttons | D-Pad |
| - | - | - | - |---|---|--------| - | - | - |
| Keyboard | X | C | Z | R | Y | Space  | WASD | Arrow keys | TFGH |

### Controller
| N64        | A     | B    | Z   | L   | R   | Start | Analog stick | C-Down | C-Left | C-Up  | C-Right |  D-Pad |
|------------|-------|------|-----|-----|-----|-------|------------|---------|---------|-------|-----|-------|
| Controller | South | West | LT2 | LT1 | RT2 | Start | Left Stick | East | North | RS Up | RT1 | D-Pad |

## Contributing

Pull requests are welcome. For major changes, please open an issue first to
discuss what you would like to change.

