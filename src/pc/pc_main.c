#define USE_NEW_RENDERER 1

#include <stdlib.h>
#include <stdbool.h>
#include <helix/helix.h>
#include <cimgui/cimgui.h>

#include "sm64.h"

#include "game/memory.h"
#include "audio/external.h"

#include "configfile.h"

#include "compat.h"

#define CONFIG_FILE "sm64config.txt"

OSMesg gMainReceivedMesg;
OSMesgQueue gSIEventMesgQueue;

s8 gResetTimer;
s8 gNmiResetBarsTimer;
s8 gDebugLevelSelect;
s8 gShowProfiler;
s8 gShowDebugText;

extern void thread5_game_loop(void *arg);
extern void create_next_audio_buffer(s16 *samples, u32 num_samples);
void game_loop_one_iteration(void);

void dispatch_audio_sptask(UNUSED struct SPTask *spTask) {
}

void set_vblank_handler(UNUSED s32 index, UNUSED struct VblankHandler *handler, UNUSED OSMesgQueue *queue, UNUSED OSMesg *msg) {
}

static uint8_t inited = 0;

#include "game/game_init.h" // for gGlobalTimer
void exec_display_list(struct SPTask *spTask) {
    if (!inited) {
        return;
    }
    
    HLXDisplayProcessDrawLists(spTask->task.t.data_ptr);
}

#define printf

#ifdef VERSION_EU
#define SAMPLES_HIGH 656
#define SAMPLES_LOW 640
#else
#define SAMPLES_HIGH 544
#define SAMPLES_LOW 528
#endif

static bool gui_show_profiler = false;

void draw_menu_bar(void* iu) {
    if (igBeginMenu("File", true)) {
        if (igMenuItem_Bool("Quit", "Ctrl+Q", false, true)) { exit(0); }
        igEndMenu();
    }
    if (igBeginMenu("Debug", true)) {
        if (igMenuItem_BoolPtr("Show Profiler", NULL, &gui_show_profiler, true)) { }
        igEndMenu();
    }
}

void draw_windows(void* ui) {
    HLXShowProfilerWindow(ui, &gui_show_profiler);
}

void produce_one_frame(void) {
    HLXDisplayStartFrame();
    game_loop_one_iteration();

    int samples_left = HLXAudioGetBufferredSampleCount();
    u32 num_audio_samples = samples_left < HLXAudioGetBufferSize() / 4 ? SAMPLES_HIGH : SAMPLES_LOW;
    //printf("Audio samples: %d %u\n", samples_left, num_audio_samples);
    s16 audio_buffer[SAMPLES_HIGH * 2 * 2];
    for (int i = 0; i < 2; i++) {
        /*if (audio_cnt-- == 0) {
            audio_cnt = 2;
        }
        u32 num_audio_samples = audio_cnt < 2 ? 528 : 544;*/
        create_next_audio_buffer(audio_buffer + i * (num_audio_samples * 2), num_audio_samples);
    }
    //printf("Audio samples before submitting: %d\n", audio_api->buffered());
    HLXAudioPlayBuffer((u8 *)audio_buffer, 2 * num_audio_samples * 4);
    
    HLXDisplayEndFrame();
}

static void save_config(void) {
    configfile_save(CONFIG_FILE);
}

static void on_fullscreen_changed(bool is_now_fullscreen) {
    configFullscreen = is_now_fullscreen;
}

void main_func(void) {
    HLXInit();
    main_pool_init();
    gGfxAllocOnlyPool = alloc_only_pool_init();
    gEffectsMemoryPool = mem_pool_init(0x4000, MEMORY_POOL_LEFT);

    configfile_load(CONFIG_FILE);
    atexit(save_config);
    
    HLXDisplaySetup("Nova64 - Super Mario 64", &draw_menu_bar, &draw_windows);
    HLXAudioSetup(32000, 2);

    audio_init();
    sound_init();

    thread5_game_loop(NULL);
    inited = 1;
    while (1) {
        produce_one_frame();
    }
}

#if (defined(_WIN32) || defined(_WIN64)) && ! defined(_MSC_VER)
#include <windows.h>
int WINAPI WinMain(UNUSED HINSTANCE hInstance, UNUSED HINSTANCE hPrevInstance, UNUSED LPSTR pCmdLine, UNUSED int nCmdShow) {
    main_func();
    return 0;
}
#else
int main(UNUSED int argc, UNUSED char *argv[]) {
    main_func();
    return 0;
}
#endif
