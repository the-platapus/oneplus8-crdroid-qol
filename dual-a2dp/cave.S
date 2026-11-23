// Dual A2DP for crDroid 16 (com.android.bt 361099999), libbluetooth_jni.so.
//
// Lives in the zero padding after the code segment (vaddr 0xdf1e80). The first instruction of
// btif_av_stream_start_with_latency(bool) (0x61beb0) becomes "b dual_start". This wrapper
// sends BTIF_AV_START_STREAM_REQ_EVT to every *other* peer in the Opened state, so their
// AVDTP streams start too and BTA's bta_av_dup_audio_buf() copies the audio to them. It then
// replays the original first instruction and continues into the untouched original function,
// which starts the active peer exactly as before (with its latency mode).
//
// It is on unless the property debug.bt.dual_a2dp is set to something other than "true"
// (osi_property_get_bool(key, true)): `adb shell setprop debug.bt.dual_a2dp false` turns it off
// until reboot.
//
// The peer loop is the one btif_av_stream_suspend() already uses (inlined
// BtifAvSource::DispatchSuspendStreamEvent): std::map<RawAddress, BtifAvPeer*> peers_ at
// btif_av_source (0xe65248, begin_node), end node at +8, recursive_mutex at +0x50, active_peer_
// (RawAddress) at +0x30. Node: left +0, right +8, parent +0x10, key +0x20, BtifAvPeer* +0x28.
// Peer: state machine's current state at +0x20, state id at state+0x10 (2 = Opened).

        .text
        .global dual_start
        .type   dual_start, %function
dual_start:
        str     x30, [x18], #8                // shadow call stack push
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     w19, w0                       // keep use_latency_mode for the original

        adr     x0, prop_name
        mov     w1, #1                        // default: on
        bl      osi_property_get_bool
        tbz     w0, #0, .Lout                 // turned off: original behaviour only

        adrp    x20, btif_av_source
        add     x20, x20, :lo12:btif_av_source
        add     x0, x20, #0x50
        bl      rmutex_lock

        ldr     w23, [x20, #0x30]             // active_peer_ bytes 0..3
        ldrh    w24, [x20, #0x34]             // active_peer_ bytes 4..5

        ldr     x21, [x20], #8                // x21 = begin node, x20 = &end node
        cmp     x21, x20
        b.eq    .Lunlock

.Lloop:
        ldr     w10, [x21, #0x20]             // skip the active peer: the original starts it
        ldrh    w11, [x21, #0x24]
        cmp     w10, w23
        ccmp    w11, w24, #0, eq
        b.eq    .Lnext
        ldr     x0, [x21, #0x28]              // BtifAvPeer*, its RawAddress is at offset 0
        ldr     x9, [x0, #0x20]               // current state
        cbz     x9, .Lnext
        ldr     w9, [x9, #0x10]               // state id
        cmp     w9, #2                        // kStateOpened
        b.ne    .Lnext
        mov     w1, #0x1c                     // BTIF_AV_START_STREAM_REQ_EVT
        bl      dispatch_sm_event             // btif_av_source_dispatch_sm_event(addr, event)

.Lnext:                                       // in-order successor, as in the original loop
        ldr     x10, [x21, #8]
        cbz     x10, .Lup
.Lleft:
        mov     x9, x10
        ldr     x10, [x10]
        cbnz    x10, .Lleft
        b       .Ladvance
.Lup:
        ldr     x9, [x21, #0x10]
        ldr     x10, [x9]
        cmp     x21, x10
        mov     x21, x9
        b.ne    .Lup
.Ladvance:
        cmp     x9, x20
        mov     x21, x9
        b.ne    .Lloop

.Lunlock:
        add     x0, x20, #0x48                // x20 = &end node = btif_av_source + 8
        bl      rmutex_unlock

.Lout:
        mov     w0, w19
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ldr     x30, [x18, #-8]!              // shadow call stack pop: x30 = caller's LR
        str     x30, [x18], #8                // replay the original first instruction
        b       orig_continue                 // 0x61beb4

prop_name:
        .asciz  "debug.bt.dual_a2dp"
        .size   dual_start, . - dual_start
