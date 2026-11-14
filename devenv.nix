{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  overlays = [ (import inputs.rust-overlay) ];
  system = pkgs.stdenv.system;
  rustPkgs = import inputs.nixpkgs { inherit system overlays; };
  # Use stable Rust toolchain
  rust-toolchain = rustPkgs.rust-bin.stable.latest.default.override {
    extensions = [ "rust-src" "rust-analyzer" "clippy" ];
  };
in
{
  packages =
    with pkgs;
    [
      # Build tools
      cmake
      ninja
      pkg-config
      git

      # USB support for libusb
      libusb1

      # Development tools
      lldb

      # Font rendering dependencies
      expat

      # Rust toolchain
      rust-toolchain

      # Cross-compilation toolchain for asset building
      pkgsCross.mingw32.stdenv.cc
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      # macOS-specific packages
      fontconfig
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      # Linux-specific packages
      gcc
      clang
      clang-tools
      glew
      libGL
      libxkbcommon
      wayland
      wayland-protocols
      xorg.libX11
      xorg.libXrandr
      xorg.libXi
      freetype
      fontconfig
      alsa-lib
      pulseaudio
      openssl
      udev
    ];

  env = {
    CMAKE_BUILD_TYPE = "Debug";
  };

  scripts = {
    configure.exec =
      if pkgs.stdenv.isDarwin then ''
        echo "Configuring SM64 build with CMake..."
        cmake -H. -Bbuild-cmake -GNinja -DCMAKE_BUILD_TYPE=Debug \
          -DRust_COMPILER="$(which rustc)" \
          -DRust_CARGO="$(which cargo)" \
          -DCMAKE_C_COMPILER="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" \
          -DCMAKE_CXX_COMPILER="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
      '' else ''
        echo "Configuring SM64 build with CMake..."
        cmake -H. -Bbuild-cmake -GNinja -DCMAKE_BUILD_TYPE=Debug \
          -DRust_COMPILER="$(which rustc)" \
          -DRust_CARGO="$(which cargo)"
      '';

    extract.exec = ''
      echo "Extracting assets from ROM..."
      cmake --build build-cmake --config Debug --target ExtractAssets
    '';

    build.exec = ''
      echo "Building SM64..."
      cmake --build build-cmake --config Debug -j$(nproc 2>/dev/null || sysctl -n hw.ncpu)
    '';

    clean.exec = ''
      echo "Cleaning build artifacts and extracted assets..."

      # Remove build directories
      rm -rf build-cmake build

      echo "Clean complete!"
    '';

    run.exec = ''
      echo "Running SM64..."
      # Auto-detect ROM version (us, jp, or eu) in build-cmake directory
      if [ -f "build-cmake/sm64-us" ]; then
        ./build-cmake/sm64-us
      elif [ -f "build-cmake/sm64-jp" ]; then
        ./build-cmake/sm64-jp
      elif [ -f "build-cmake/sm64-eu" ]; then
        ./build-cmake/sm64-eu
      else
        echo "Error: No SM64 executable found. Did you run 'build'?"
        exit 1
      fi
    '';
  };

  # On macOS we use Xcode's clang via enterShell PATH override
  languages = lib.optionalAttrs pkgs.stdenv.isLinux {
    c.enable = true;
    cplusplus.enable = true;
  };

  # On macOS, use Xcode toolchain for main compilation
  # LLVM from Nix is still available for other tools if needed
  enterShell = lib.optionalString pkgs.stdenv.isDarwin ''
    # Get Xcode path via symlink (bypasses Nix's DEVELOPER_DIR override)
    export DEVELOPER_DIR="$(/usr/bin/readlink /var/db/xcode_select_link)"
    export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

    if [ ! -d "$DEVELOPER_DIR" ]; then
      echo "Warning: Xcode not found at $DEVELOPER_DIR"
      echo "Please install Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    fi

    # Use Xcode's clang for main compilation (required for macOS frameworks)
    export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$DEVELOPER_DIR/usr/bin:$PATH"

    # Use system xcrun (avoids potential issues with Nix wrappers)
    export PATH="${pkgs.runCommand "xcrun-wrapper" {} "mkdir -p $out/bin && ln -s /usr/bin/xcrun $out/bin/xcrun"}/bin:$PATH"
  '' + ''
    echo "=== SM64 Build Environment ==="
    echo "Available commands:"
    echo "  configure  - Run CMake configuration"
    echo "  extract    - Extract assets from ROM"
    echo "  build      - Build SM64"
    echo "  run        - Run SM64 executable"
    echo "  clean      - Clean build artifacts"
    echo ""
    echo "Quick start:"
    echo "  1. Place baserom.<VERSION>.z64 in the repo root"
    echo "  2. Run 'configure' to set up CMake"
    echo "  3. Run 'extract' to extract assets from ROM"
    echo "  4. Run 'build' to compile"
    echo "  5. Run 'run' to play!"
    echo "=============================="
  '';
}
