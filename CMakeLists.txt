cmake_minimum_required(VERSION 3.16.0 FATAL_ERROR)

# SM64 (US) on the helix runtime — built straight from n64decomp/sm64.
# Additive: game code + data stay pristine decomp. This file + helix are the glue.
project(sm64-helix VERSION 0.1.0 LANGUAGES C CXX ASM)

if(APPLE)
  enable_language(OBJCXX)
endif()

set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum OS X deployment version")
set(CMAKE_CXX_STANDARD 20 CACHE STRING "The C++ standard to use")
set(CMAKE_C_STANDARD 11 CACHE STRING "The C standard to use")
add_compile_options($<$<CXX_COMPILER_ID:MSVC>:/MP>)
add_compile_options($<$<CXX_COMPILER_ID:MSVC>:/MT>)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake/modules/")

if (WIN32)
  include(cmake/automate-vcpkg.cmake)
  if(MSVC)
    set(VCPKG_TRIPLET x64-windows-static)
    set(VCPKG_TARGET_TRIPLET x64-windows-static)
  else()
    set(VCPKG_TRIPLET x64-mingw-static)
    set(VCPKG_TARGET_TRIPLET x64-mingw-static)
  endif()
  if(MSVC)
    vcpkg_bootstrap()
    vcpkg_install_packages(zlib bzip2 libpng getopt dirent libusb pthread)
  else()
    vcpkg_bootstrap()
    vcpkg_install_packages(fontconfig)
  endif()
endif()

# C preprocessor used for charmap / level headers / text (mirrors decomp CPP).
if (MSVC)
  set(CPP "${CMAKE_C_COMPILER}" "/EP")
else()
  set(CPP "${CMAKE_C_COMPILER}" "-E" "-P" "-Wno-trigraphs" "-x" "c")
endif()

set(VERSION us)

find_package(Python3 COMPONENTS Interpreter REQUIRED)

#==============================================================================#
# Decomp asset tools (built via decomp's own Makefiles — kept pristine)         #
#==============================================================================#
set(TOOLS_DIR   ${CMAKE_SOURCE_DIR}/tools)
set(N64GRAPHICS ${TOOLS_DIR}/sm64tools/n64graphics)
set(SKYCONV     ${TOOLS_DIR}/skyconv)
set(TEXTCONV    ${TOOLS_DIR}/textconv)
set(AIFF_EXTRACT_CODEBOOK ${TOOLS_DIR}/aiff_extract_codebook)
set(VADPCM_ENC  ${TOOLS_DIR}/vadpcm_enc)

add_custom_target(BuildTools
  COMMAND ${CMAKE_COMMAND} -E env make -s -C ${TOOLS_DIR}/sm64tools n64graphics n64graphics_ci mio0
  COMMAND ${CMAKE_COMMAND} -E env make -s -C ${TOOLS_DIR} skyconv textconv vadpcm_enc aiff_extract_codebook aifc_decode
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  COMMENT "Building decomp asset tools"
)

add_custom_target(ExtractAssets
  COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/extract_assets.py ${VERSION}
  WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
  COMMENT "Extracting assets from baserom (decomp pipeline)"
)

#==============================================================================#
# Compile definitions + host portability flags                                 #
#==============================================================================#
add_compile_definitions(
    VERSION_US=1
    F3D_OLD=1          # decomp's native US microcode (fast3d f3d_old support: renderer side)
    _LANGUAGE_C
    NON_MATCHING=1
    AVOID_UB=1
    _USE_MATH_DEFINES
    # decomp-native flatten: identity segments, no ROM-DMA, data compiled-in as native
    # pointers. Removes all _<name>SegmentRom* linker symbols (helix has no guest ROM).
    NO_SEGMENTED_MEMORY=1
    # decomp's os_libc.h declares bcopy/bzero; macOS <strings.h> macro-izes them under
    # _FORTIFY_SOURCE, causing a clash. Disabling fortify keeps the decomp header pristine.
    _FORTIFY_SOURCE=0
    # Skip the redundant monolithic <PR/os.h> (its only 3 includers get the correct 64-bit PI/DMA
    # decls from the modular os_pi.h/os_misc.h via ultra64.h), so that umbrella header stays pristine.
    _OS_H_=1
)

# Host portability flags (decomp's non-N64/gcc build relies on these).
if (NOT MSVC)
  add_compile_options($<$<COMPILE_LANGUAGE:C>:-fsigned-char>)
  add_compile_options($<$<COMPILE_LANGUAGE:C>:-fno-strict-aliasing>)
  add_compile_options($<$<COMPILE_LANGUAGE:C>:-fwrapv>)
endif()

if (UNIX AND NOT APPLE)
  find_package(OpenGL REQUIRED)
endif()

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_BINARY_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}/include
)

#==============================================================================#
# Game sources (pristine decomp; helix provides libultra, so exclude lib os*)   #
#==============================================================================#
file(GLOB_RECURSE ALL_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
    "actors/*.h"      "actors/*.c"
    "bin/*.c"
    "data/*.c"
    "levels/*.h"      "levels/*.c"
    "sound/*.c"
    "src/audio/*.h"   "src/audio/*.c"
    "src/buffers/*.h" "src/buffers/*.c"
    "src/engine/*.h"  "src/engine/*.c"
    "src/game/*.h"    "src/game/*.c"
    "src/goddard/*.h" "src/goddard/*.c"
    "src/menu/*.h"    "src/menu/*.c"
    "text/*.c"
    "textures/*.h"    "textures/*.c"
)

# From lib/src, take only the gu-math helpers + audio bank loader; helix owns os*.
set(LIB_SRC_FILES
    lib/src/alBnkfNew.c
    lib/src/guLookAtRef.c
    lib/src/guMtxF2L.c
    lib/src/guNormalize.c
    lib/src/guOrthoF.c
    lib/src/guPerspectiveF.c
    lib/src/guRotateF.c
    lib/src/guScaleF.c
    lib/src/guTranslateF.c
)
list(APPEND ALL_FILES ${LIB_SRC_FILES})

list(FILTER ALL_FILES EXCLUDE REGEX ".*\\.inc\\.c")
list(FILTER ALL_FILES EXCLUDE REGEX "bin/eu/.*\\.c")

#==============================================================================#
# Generated: level headers, mario anims, demo data                             #
#==============================================================================#
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/include/level_headers.h
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/include
    COMMAND ${CPP} -I${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/levels/level_headers.h.in
            | sed -E "s|(.+)|#include \"\\1\"|" > ${CMAKE_CURRENT_BINARY_DIR}/include/level_headers.h
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND ALL_FILES ${CMAKE_CURRENT_BINARY_DIR}/include/level_headers.h)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/assets/mario_anim_data.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/assets
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/mario_anims_converter.py > ${CMAKE_CURRENT_BINARY_DIR}/assets/mario_anim_data.c
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND ALL_FILES ${CMAKE_CURRENT_BINARY_DIR}/assets/mario_anim_data.c)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/assets/demo_data.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/assets
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/demo_data_converter.py ${CMAKE_CURRENT_SOURCE_DIR}/assets/demo_data.json -DVERSION_US > ${CMAKE_CURRENT_BINARY_DIR}/assets/demo_data.c
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND ALL_FILES ${CMAKE_CURRENT_BINARY_DIR}/assets/demo_data.c)

#==============================================================================#
# Generated: in-game text (decomp charmap is preprocessed, then textconv)       #
#==============================================================================#
set(BCHARMAP ${CMAKE_CURRENT_BINARY_DIR}/charmap.txt)
add_custom_command(
    OUTPUT ${BCHARMAP}
    COMMAND ${CPP} -Wno-trigraphs -D_LANGUAGE_ASSEMBLY -I${CMAKE_CURRENT_SOURCE_DIR}/include -I${CMAKE_CURRENT_SOURCE_DIR}
            -DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/charmap.txt > ${BCHARMAP}
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/charmap.txt
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/include/text_strings.h
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/include
    COMMAND ${TEXTCONV} ${BCHARMAP} ${CMAKE_CURRENT_SOURCE_DIR}/include/text_strings.h.in ${CMAKE_CURRENT_BINARY_DIR}/include/text_strings.h
    DEPENDS BuildTools ${BCHARMAP}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND ALL_FILES ${CMAKE_CURRENT_BINARY_DIR}/include/text_strings.h)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/include/text_menu_strings.h
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/include
    COMMAND ${TEXTCONV} ${CMAKE_CURRENT_SOURCE_DIR}/charmap_menu.txt ${CMAKE_CURRENT_SOURCE_DIR}/include/text_menu_strings.h.in ${CMAKE_CURRENT_BINARY_DIR}/include/text_menu_strings.h
    DEPENDS BuildTools
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND ALL_FILES ${CMAKE_CURRENT_BINARY_DIR}/include/text_menu_strings.h)

add_executable(sm64-${VERSION} ${ALL_FILES})
add_dependencies(sm64-${VERSION} BuildTools)

################################################################################
# MSVC runtime library
################################################################################
if (MSVC AND CMAKE_SYSTEM_NAME STREQUAL "Windows")
  set_target_properties(sm64-${VERSION} PROPERTIES
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

#==============================================================================#
# Helix Integration                                                            #
#==============================================================================#
add_subdirectory(./corrosion)

file(GLOB_RECURSE HELIX_CPP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/helix/cpp/*.c")
list(FILTER HELIX_CPP_SOURCES EXCLUDE REGEX "helix/cpp/audio/tests/.*")
list(FILTER HELIX_CPP_SOURCES EXCLUDE REGEX "helix/cpp/libultra/tests/.*")
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/helix/cpp)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/helix/include)
add_library(helixcpp STATIC ${HELIX_CPP_SOURCES})
target_include_directories(helixcpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(sm64-${VERSION} PRIVATE helixcpp)

corrosion_import_crate(MANIFEST_PATH ${CMAKE_CURRENT_SOURCE_DIR}/helix/Cargo.toml)
target_link_libraries(sm64-${VERSION} PRIVATE helix)

if(APPLE)
    target_link_libraries(helix INTERFACE "-framework Carbon" "-framework Foundation")
    target_link_libraries(helix INTERFACE "-framework CoreFoundation -framework AVFoundation -framework CoreAudio -framework AudioToolbox")
    target_link_libraries(helix INTERFACE "-framework Metal -framework QuartzCore")
    target_link_libraries(helix INTERFACE "-framework IOKit" "-framework ApplicationServices" "-framework AppKit")
    target_link_libraries(helix INTERFACE "-lc++")
elseif(WIN32)
    target_link_libraries(helix INTERFACE OpenGL32 D3DCompiler imm32 winmm uxtheme dwmapi)
    if(MINGW)
      target_link_libraries(helix INTERFACE "-lstdc++")
    endif()
else()
    find_package(X11 REQUIRED)
    find_package(libUsb REQUIRED)
    find_package(ALSA REQUIRED)
    find_package(Freetype REQUIRED)
    find_package(udev REQUIRED)
    target_link_libraries(helix INTERFACE ${ALSA_LIBRARY} ${OPENGL_glx_LIBRARY} ${OPENGL_opengl_LIBRARY})
    target_link_libraries(helix INTERFACE ${X11_LIBRARIES} ${UDEV_LIBRARY} ${FREETYPE_LIBRARIES})
    target_link_libraries(helix INTERFACE Fontconfig::Fontconfig libUsb::libUsb)
    target_link_libraries(helix INTERFACE "-lstdc++ -lm -ldl")
endif()

#==============================================================================#
# Texture generation (PNG -> .inc.c via decomp n64graphics)                     #
#==============================================================================#
set(TEXTURE_ENCODING u8)
set(INC_C_FILES "")

file(GLOB_RECURSE ORGFILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "actors/*.png" "levels/*.png" "textures/*.png")
list(REMOVE_ITEM ORGFILES "levels/ending/cake.png")
list(FILTER ORGFILES EXCLUDE REGEX "textures/ipl3_raw/.*\\.png")
list(FILTER ORGFILES EXCLUDE REGEX "textures/skyboxes/.*\\.png")
foreach(orgfile ${ORGFILES})
  get_filename_component(OUTPUT_FILE_WLE ${orgfile} NAME_WLE)
  get_filename_component(OUTPUT_DIR ${orgfile} DIRECTORY)
  set(OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT_DIR}/${OUTPUT_FILE_WLE}.inc.c)
  string(REPLACE "." ";" FORMAT ${OUTPUT_FILE_WLE})
  list(POP_BACK FORMAT FORMAT2)
  # crash screen textures use u32
  set(THIS_ENC ${TEXTURE_ENCODING})
  if(orgfile MATCHES "crash_screen")
    set(THIS_ENC u32)
  endif()
  add_custom_command(
    OUTPUT ${OUTPUT_FILE}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT_DIR}
    COMMAND ${N64GRAPHICS} -s ${THIS_ENC} -i ${OUTPUT_FILE} -g ${CMAKE_CURRENT_SOURCE_DIR}/${orgfile} -f ${FORMAT2}
    DEPENDS BuildTools ${CMAKE_CURRENT_SOURCE_DIR}/${orgfile}
    VERBATIM
  )
  list(APPEND INC_C_FILES ${OUTPUT_FILE})
endforeach(orgfile)

# Skyboxes + cake ending (skyconv)
file(GLOB_RECURSE SKYBOXES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "textures/skyboxes/*.png")
foreach(skybox ${SKYBOXES})
  get_filename_component(OUTPUT_FILE_WLE ${skybox} NAME_WLE)
  set(OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/bin/${OUTPUT_FILE_WLE}_skybox.c)
  add_custom_command(
    OUTPUT ${OUTPUT_FILE}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/bin
    COMMAND ${SKYCONV} --type sky --split ${CMAKE_CURRENT_SOURCE_DIR}/${skybox} ${CMAKE_CURRENT_BINARY_DIR}/bin
    DEPENDS BuildTools
    VERBATIM
  )
  # _skybox.c is a full translation unit (defines <name>_skybox_ptrlist) — it must be
  # COMPILED into the executable, not just #included like the .inc.c files.
  list(APPEND SKYBOX_C_FILES ${OUTPUT_FILE})
endforeach(skybox)
target_sources(sm64-${VERSION} PRIVATE ${SKYBOX_C_FILES})

# helix integration shim: dummy RSP microcode symbols (helix is the RSP; ucode unused).
target_sources(sm64-${VERSION} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/helix_shims/rsp_ucode_stubs.c)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/levels/ending/cake.inc.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/levels/ending
    COMMAND ${SKYCONV} --type cake --split ${CMAKE_CURRENT_SOURCE_DIR}/levels/ending/cake.png ${CMAKE_CURRENT_BINARY_DIR}/levels/ending
    DEPENDS BuildTools
    VERBATIM
)
list(APPEND INC_C_FILES ${CMAKE_CURRENT_BINARY_DIR}/levels/ending/cake.inc.c)

#==============================================================================#
# define_text.inc.c (cpp | textconv, US)                                        #
#==============================================================================#
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/text/us/define_text.inc.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/text/us
    COMMAND ${CPP} -I${CMAKE_CURRENT_SOURCE_DIR}/text/us ${CMAKE_CURRENT_SOURCE_DIR}/text/define_text.inc.c
            | ${TEXTCONV} ${BCHARMAP} - ${CMAKE_CURRENT_BINARY_DIR}/text/us/define_text.inc.c
    DEPENDS BuildTools ${BCHARMAP}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND INC_C_FILES ${CMAKE_CURRENT_BINARY_DIR}/text/us/define_text.inc.c)

# define_courses.inc.c (consumed by levels/menu/leveldata.c)
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/text/us/define_courses.inc.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/text/us
    COMMAND ${CPP} -I${CMAKE_CURRENT_SOURCE_DIR}/text/us ${CMAKE_CURRENT_SOURCE_DIR}/text/define_courses.inc.c
            | ${TEXTCONV} ${BCHARMAP} - ${CMAKE_CURRENT_BINARY_DIR}/text/us/define_courses.inc.c
    DEPENDS BuildTools ${BCHARMAP}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND INC_C_FILES ${CMAKE_CURRENT_BINARY_DIR}/text/us/define_courses.inc.c)

# debug charmap + debug_text.raw.inc.c (consumed by bin/segment2.c)
set(BCHARMAP_DEBUG ${CMAKE_CURRENT_BINARY_DIR}/charmap.debug.txt)
add_custom_command(
    OUTPUT ${BCHARMAP_DEBUG}
    COMMAND ${CPP} -Wno-trigraphs -D_LANGUAGE_ASSEMBLY -DCHARMAP_DEBUG -I${CMAKE_CURRENT_SOURCE_DIR}/include -I${CMAKE_CURRENT_SOURCE_DIR}
            -DBUILD_DIR=${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/charmap.txt > ${BCHARMAP_DEBUG}
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/charmap.txt
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/text/debug_text.raw.inc.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/text
    COMMAND ${CPP} ${CMAKE_CURRENT_SOURCE_DIR}/text/debug_text.inc.c
            | ${TEXTCONV} ${BCHARMAP_DEBUG} - ${CMAKE_CURRENT_BINARY_DIR}/text/debug_text.raw.inc.c
    DEPENDS BuildTools ${BCHARMAP_DEBUG}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND INC_C_FILES ${CMAKE_CURRENT_BINARY_DIR}/text/debug_text.raw.inc.c)

#==============================================================================#
# Sound generation (aiff -> table -> aifc -> assemble_sound)                     #
#==============================================================================#
execute_process(
    OUTPUT_VARIABLE endian_and_bitwidth
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/determine-endian-bitwidth.py
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)
string(STRIP "${endian_and_bitwidth}" endian_and_bitwidth)
string(REPLACE " " ";" endian_and_bitwidth "${endian_and_bitwidth}")

set(TABLE_FILES "")
set(AIFC_FILES "")
file(GLOB_RECURSE AIFF_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS "sound/samples/*.aiff")
foreach(aifffile ${AIFF_FILES})
  get_filename_component(OUTPUT_FILE_WLE ${aifffile} NAME_WLE)
  get_filename_component(OUTPUT_DIR ${aifffile} DIRECTORY)
  set(TABLE_FILE ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT_DIR}/${OUTPUT_FILE_WLE}.table)
  set(AIFC_FILE  ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT_DIR}/${OUTPUT_FILE_WLE}.aifc)
  add_custom_command(
    OUTPUT ${TABLE_FILE}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/${OUTPUT_DIR}
    COMMAND ${AIFF_EXTRACT_CODEBOOK} ${CMAKE_CURRENT_SOURCE_DIR}/${aifffile} > ${TABLE_FILE}
    DEPENDS BuildTools ${CMAKE_CURRENT_SOURCE_DIR}/${aifffile}
    VERBATIM
  )
  add_custom_command(
    OUTPUT ${AIFC_FILE}
    COMMAND ${VADPCM_ENC} -c ${TABLE_FILE} ${CMAKE_CURRENT_SOURCE_DIR}/${aifffile} ${AIFC_FILE}
    DEPENDS BuildTools ${TABLE_FILE} ${CMAKE_CURRENT_SOURCE_DIR}/${aifffile}
    VERBATIM
  )
  list(APPEND TABLE_FILES ${TABLE_FILE})
  list(APPEND AIFC_FILES ${AIFC_FILE})
endforeach(aifffile)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.ctl.inc.c ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.tbl.inc.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/sound
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/assemble_sound.py ${CMAKE_CURRENT_BINARY_DIR}/sound/samples/ ${CMAKE_CURRENT_SOURCE_DIR}/sound/sound_banks ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.ctl ${CMAKE_CURRENT_BINARY_DIR}/sound/ctl_header ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.tbl ${CMAKE_CURRENT_BINARY_DIR}/sound/tbl_header -DVERSION_US ${endian_and_bitwidth}
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/conv2hex.py ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.ctl > ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.ctl.inc.c
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/conv2hex.py ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.tbl > ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.tbl.inc.c
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    DEPENDS ${TABLE_FILES} ${AIFC_FILES}
    VERBATIM
)
list(APPEND INC_C_FILES ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.ctl.inc.c ${CMAKE_CURRENT_BINARY_DIR}/sound/sound_data.tbl.inc.c)

file(GLOB SEQ_M64_FILES ${CMAKE_CURRENT_SOURCE_DIR}/sound/sequences/us/*.m64)

# Assemble .s sequences (e.g. 00_sound_player.s) into .m64 (rodata blob).
# macOS clang 'as' can't emit the ELF layout objcopy needs, so use the mingw cross tools
# (provided by devenv) on Darwin, like the reference port; plain as/objcopy elsewhere.
if(APPLE)
  set(SEQ_AS i686-w64-mingw32-as)
  set(SEQ_OBJCOPY i686-w64-mingw32-objcopy)
else()
  set(SEQ_AS as)
  set(SEQ_OBJCOPY objcopy)
endif()
file(GLOB SEQ_S_FILES ${CMAKE_CURRENT_SOURCE_DIR}/sound/sequences/*.s)
foreach(seq_s ${SEQ_S_FILES})
  get_filename_component(SEQ_WLE ${seq_s} NAME_WLE)
  set(SEQ_M64_OUT ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences/${SEQ_WLE}.m64)
  add_custom_command(
    OUTPUT ${SEQ_M64_OUT}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences
    COMMAND ${CPP} ${seq_s} -I${CMAKE_CURRENT_SOURCE_DIR}/include -DVERSION_US | ${SEQ_AS} -o ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences/${SEQ_WLE}.o
    COMMAND ${SEQ_OBJCOPY} -j .rodata ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences/${SEQ_WLE}.o -O binary ${SEQ_M64_OUT}
    DEPENDS ${seq_s}
    VERBATIM
  )
  list(APPEND SEQ_M64_FILES ${SEQ_M64_OUT})
endforeach()

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences.bin.inc.c ${CMAKE_CURRENT_BINARY_DIR}/sound/bank_sets.inc.c
    COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_CURRENT_BINARY_DIR}/sound
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/assemble_sound.py --sequences ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences.bin ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences_header ${CMAKE_CURRENT_BINARY_DIR}/sound/bank_sets ${CMAKE_CURRENT_SOURCE_DIR}/sound/sound_banks ${CMAKE_CURRENT_SOURCE_DIR}/sound/sequences.json ${SEQ_M64_FILES} -DVERSION_US ${endian_and_bitwidth}
    DEPENDS ${SEQ_M64_FILES}
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/conv2hex.py ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences.bin > ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences.bin.inc.c
    COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/conv2hex.py ${CMAKE_CURRENT_BINARY_DIR}/sound/bank_sets > ${CMAKE_CURRENT_BINARY_DIR}/sound/bank_sets.inc.c
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)
list(APPEND INC_C_FILES ${CMAKE_CURRENT_BINARY_DIR}/sound/sequences.bin.inc.c ${CMAKE_CURRENT_BINARY_DIR}/sound/bank_sets.inc.c)

add_custom_target(ConvertIncCFiles DEPENDS ${INC_C_FILES})
add_dependencies(sm64-${VERSION} ConvertIncCFiles)
