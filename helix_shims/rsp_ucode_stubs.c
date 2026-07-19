/*
 * helix integration shim — dummy RSP microcode symbols (declared extern in PR/ucode.h).
 *
 * The game assigns these to OSTask.t.ucode/ucode_boot/ucode_data, but helix routes tasks by
 * task.t.type and interprets the DL/Acmd list itself — it never reads the blob content. So the
 * symbols only need to EXIST for the game to link; their content and size are irrelevant.
 */
#include <ultra64.h>

u64 rspF3DBootStart[1], rspF3DBootEnd[1];
u64 rspF3DStart[1], rspF3DEnd[1];
u64 rspF3DDataStart[1], rspF3DDataEnd[1];
u64 rspAspMainStart[1], rspAspMainEnd[1];
u64 rspAspMainDataStart[1], rspAspMainDataEnd[1];
