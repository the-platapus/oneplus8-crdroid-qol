// Runs the real patched bytes of libbluetooth_jni.so (entry branch + dual_start wrapper) on an
// AArch64 CPU (qemu-aarch64 or the phone), with the functions the wrapper calls replaced by
// recording stubs and btif_av_source's peer map rebuilt by hand in each scenario.
//   harness <libbluetooth_jni.so.patched>
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define ENTRY          0x61beb0UL   // btif_av_stream_start_with_latency, now "b dual_start"
#define ORIG_CONTINUE  0x61beb4UL
#define PROP_GET_BOOL  0xd97370UL
#define RMUTEX_LOCK    0x2e9408UL
#define RMUTEX_UNLOCK  0x2e9434UL
#define DISPATCH       0x60f560UL
#define BTIF_AV_SOURCE 0xe65248UL
#define START_EVT      0x1c

static int failures, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { failures++; printf("    FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

// ---- stubs -----------------------------------------------------------------------------------
static int prop_value = 1, prop_calls, lock_calls, unlock_calls, dispatch_calls;
static uintptr_t lock_arg, unlock_arg, locked_depth;
static char prop_key[64];
static uintptr_t dispatched[16]; static int dispatched_evt[16];

static int stub_prop(const char* key, int def) {
  prop_calls++; snprintf(prop_key, sizeof prop_key, "%s", key);
  return prop_value < 0 ? def : prop_value;
}
static void stub_lock(void* m) { lock_calls++; lock_arg = (uintptr_t)m; locked_depth++; }
static void stub_unlock(void* m) { unlock_calls++; unlock_arg = (uintptr_t)m; locked_depth--; }
static void stub_dispatch(const void* addr, int evt) {
  CHECK(locked_depth == 1, "dispatch called without the peers lock held");
  if (dispatch_calls < 16) { dispatched[dispatch_calls] = (uintptr_t)addr; dispatched_evt[dispatch_calls] = evt; }
  dispatch_calls++;
  // Clobber every caller-saved register a real callee may clobber.
  __asm__ volatile("mov x9, #0xdead\n mov x10, #0xdead\n mov x11, #0xdead\n mov x12, #0xdead\n"
                   "mov x13, #0xdead\n mov x14, #0xdead\n mov x15, #0xdead\n"
                   ::: "x9", "x10", "x11", "x12", "x13", "x14", "x15");
}

// Reached when the wrapper jumps back into the original function (0x61beb4). Records the
// machine state, then returns to the original caller the way the original epilogue would:
// pop the shadow call stack entry the wrapper replayed, then ret.
uint64_t cont_regs[16]; int cont_reached;
__asm__(
  ".text\n.global stub_continue\nstub_continue:\n"
  "  adrp x16, cont_regs\n  add x16, x16, :lo12:cont_regs\n"
  "  stp x0, x18, [x16, #0]\n  stp x19, x20, [x16, #16]\n  stp x21, x22, [x16, #32]\n"
  "  stp x23, x24, [x16, #48]\n  stp x29, x30, [x16, #64]\n  mov x17, sp\n  str x17, [x16, #80]\n"
  "  ldr x17, [x18, #-8]\n  str x17, [x16, #88]\n"
  "  adrp x16, cont_reached\n  add x16, x16, :lo12:cont_reached\n  mov w17, #1\n  str w17, [x16]\n"
  "  ldr x30, [x18, #-8]!\n  ret\n");
void stub_continue(void);

// Calls ENTRY like the audio HAL would: x18 = shadow call stack, known callee-saved values.
uint64_t call_regs[16];
__asm__(
  ".text\n.global call_entry\ncall_entry:\n"           // x0 = arg, x1 = scs
  "  stp x29, x30, [sp, #-96]!\n  mov x29, sp\n"
  "  stp x19, x20, [sp, #16]\n  stp x21, x22, [sp, #32]\n  stp x23, x24, [sp, #48]\n"
  "  stp x25, x26, [sp, #64]\n  str x18, [sp, #80]\n"
  "  mov x18, x1\n"
  "  mov x19, #0x1919\n  mov x20, #0x2020\n  mov x21, #0x2121\n  mov x22, #0x2222\n"
  "  mov x23, #0x2323\n  mov x24, #0x2424\n  mov x25, #0x2525\n  mov x26, #0x2626\n"
  "  mov x9, sp\n  movz x16, #0xbeb0\n  movk x16, #0x61, lsl #16\n  blr x16\n"
  "  adrp x16, call_regs\n  add x16, x16, :lo12:call_regs\n"
  "  stp x18, x19, [x16, #0]\n  stp x20, x21, [x16, #16]\n  stp x22, x23, [x16, #32]\n"
  "  stp x24, x25, [x16, #48]\n  stp x26, x29, [x16, #64]\n  mov x17, sp\n  str x17, [x16, #80]\n"
  "  ldr x18, [sp, #80]\n  ldp x25, x26, [sp, #64]\n  ldp x23, x24, [sp, #48]\n"
  "  ldp x21, x22, [sp, #32]\n  ldp x19, x20, [sp, #16]\n  ldp x29, x30, [sp], #96\n  ret\n");
void call_entry(uint64_t arg, uint64_t* scs);

// ---- the patched library's pages, at their real addresses ------------------------------------
static void map_page_from(int fd, uintptr_t va) {
  uintptr_t page = va & ~0xfffUL;
  void* p = mmap((void*)page, 0x1000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_FIXED_NOREPLACE, fd, page);
  if (p != (void*)page) { perror("mmap code"); exit(2); }
}
static void put_trampoline(uintptr_t at, void* target) {
  uint32_t code[2] = {0x58000050, 0xd61f0200};   // ldr x16, #8 ; br x16
  memcpy((void*)at, code, 8); memcpy((void*)(at + 8), &target, 8);
}
static void finish_code(uintptr_t va) {
  uintptr_t page = va & ~0xfffUL;
  mprotect((void*)page, 0x1000, PROT_READ | PROT_EXEC);
  __builtin___clear_cache((char*)page, (char*)page + 0x1000);
}

// ---- fake btif_av_source ---------------------------------------------------------------------
struct node { struct node *left, *right, *parent; uint64_t black; uint8_t key[8]; void* peer; };
struct state { uint8_t pad[0x10]; uint32_t id; };
struct peer { uint8_t addr[8]; uint8_t pad[0x18]; struct state* st; };
#define SRC ((uint8_t*)BTIF_AV_SOURCE)
static struct node* END_NODE(void) { return (struct node*)(SRC + 8); }

static struct node nodes[8]; static struct peer peers[8]; static struct state states[8];
static void reset_world(void) {
  memset(SRC - 0x248, 0, 0x1000);
  memset(nodes, 0, sizeof nodes); memset(peers, 0, sizeof peers); memset(states, 0, sizeof states);
  prop_value = 1; prop_calls = lock_calls = unlock_calls = dispatch_calls = 0; locked_depth = 0;
  lock_arg = unlock_arg = 0; memset(dispatched, 0, sizeof dispatched); cont_reached = 0;
  *(struct node**)SRC = END_NODE();                  // empty map: begin == end
}
static void mk_peer(int i, uint8_t last, int state_id) {   // state_id < 0: no current state
  uint8_t a[6] = {0xaa, 0xbb, 0xcc, 0xdd, 0xee, last};
  memcpy(nodes[i].key, a, 6); memcpy(peers[i].addr, a, 6);
  states[i].id = state_id; peers[i].st = state_id < 0 ? NULL : &states[i];
  nodes[i].peer = &peers[i];
}
static void set_active(int i) { memcpy(SRC + 0x30, nodes[i].key, 6); }
static void set_active_none(void) { memset(SRC + 0x30, 0, 6); }
// Wire nodes into a tree: link(child, parent, is_left). root's parent = end node.
static void link_(int c, int p, int left) {
  nodes[c].parent = &nodes[p]; if (left) nodes[p].left = &nodes[c]; else nodes[p].right = &nodes[c];
}
static void set_root(int r, int leftmost) {
  END_NODE()->left = &nodes[r]; nodes[r].parent = END_NODE(); *(struct node**)SRC = &nodes[leftmost];
}

static uint64_t scs[64];
static void run(uint64_t arg, const char* name) {
  memset(scs, 0, sizeof scs);
  call_entry(arg, scs);
  CHECK(cont_reached, "%s: never reached the original function", name);
  CHECK(cont_regs[0] == arg, "%s: w0 into the original = %llu, expected %llu", name,
        (unsigned long long)cont_regs[0], (unsigned long long)arg);
  CHECK(cont_regs[1] == (uint64_t)&scs[1], "%s: shadow stack at continue off by %lld", name,
        (long long)(cont_regs[1] - (uint64_t)&scs[1]));
  CHECK(cont_regs[11] == cont_regs[9], "%s: replayed SCS entry != LR", name);
  CHECK(call_regs[0] == (uint64_t)scs, "%s: shadow stack not balanced on return", name);
  uint64_t want[] = {0x1919, 0x2020, 0x2121, 0x2222, 0x2323, 0x2424, 0x2525, 0x2626};
  for (int i = 0; i < 8; i++)
    CHECK(call_regs[1 + i] == want[i], "%s: callee-saved x%d clobbered (0x%llx)", name, 19 + i,
          (unsigned long long)call_regs[1 + i]);
  CHECK(lock_calls == unlock_calls, "%s: lock %d / unlock %d", name, lock_calls, unlock_calls);
  if (lock_calls) {
    CHECK(lock_arg == BTIF_AV_SOURCE + 0x50 && unlock_arg == BTIF_AV_SOURCE + 0x50,
          "%s: wrong mutex 0x%lx / 0x%lx", name, (unsigned long)lock_arg, (unsigned long)unlock_arg);
  }
  CHECK(prop_calls == 1 && strcmp(prop_key, "debug.bt.dual_a2dp") == 0, "%s: property '%s' x%d",
        name, prop_key, prop_calls);
}
static void expect_dispatch(const char* name, int n, const int* idx) {
  CHECK(dispatch_calls == n, "%s: %d start requests, expected %d", name, dispatch_calls, n);
  for (int i = 0; i < n && i < dispatch_calls; i++) {
    CHECK(dispatched[i] == (uintptr_t)&peers[idx[i]] && dispatched_evt[i] == START_EVT,
          "%s: request %d went to %p evt %d, expected peer %d", name, i, (void*)dispatched[i],
          dispatched_evt[i], idx[i]);
  }
}

int main(int argc, char** argv) {
  if (argc < 2) { fprintf(stderr, "usage: %s libbluetooth_jni.so.patched\n", argv[0]); return 2; }
  int fd = open(argv[1], O_RDONLY); if (fd < 0) { perror(argv[1]); return 2; }
  uintptr_t code_pages[] = {RMUTEX_LOCK, DISPATCH, ENTRY, PROP_GET_BOOL, 0xdf1e80UL};
  for (unsigned i = 0; i < 5; i++) map_page_from(fd, code_pages[i]);
  if (mmap((void*)(BTIF_AV_SOURCE & ~0xfffUL), 0x1000, PROT_READ | PROT_WRITE,
           MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0) == MAP_FAILED) { perror("mmap data"); return 2; }
  put_trampoline(RMUTEX_LOCK, stub_lock); put_trampoline(RMUTEX_UNLOCK, stub_unlock);
  put_trampoline(DISPATCH, stub_dispatch); put_trampoline(PROP_GET_BOOL, stub_prop);
  put_trampoline(ORIG_CONTINUE, stub_continue);
  for (unsigned i = 0; i < 5; i++) finish_code(code_pages[i]);

  // 1. Turned off: nothing but the original.
  reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, 2); link_(1, 0, 0); set_root(0, 0); set_active(0);
  prop_value = 0; run(1, "off");
  CHECK(lock_calls == 0, "off: took the lock"); expect_dispatch("off", 0, NULL);

  // 2. Property unset -> default on (stub returns the default).
  reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, 2); link_(1, 0, 0); set_root(0, 0); set_active(0);
  prop_value = -1; run(0, "default-on");
  { int e[] = {1}; expect_dispatch("default-on", 1, e); }

  // 3. No peers at all.
  reset_world(); set_active_none(); run(1, "empty"); expect_dispatch("empty", 0, NULL);

  // 4. One headset, the active one: unchanged behaviour.
  reset_world(); mk_peer(0, 1, 2); set_root(0, 0); set_active(0); run(1, "single");
  expect_dispatch("single", 0, NULL);

  // 5. Two headsets, both Opened: start the non-active one (either order in the map).
  reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, 2); link_(1, 0, 0); set_root(0, 0); set_active(0);
  run(0, "two/active-first"); { int e[] = {1}; expect_dispatch("two/active-first", 1, e); }
  reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, 2); link_(0, 1, 1); set_root(1, 0); set_active(1);
  run(1, "two/active-second"); { int e[] = {0}; expect_dispatch("two/active-second", 1, e); }

  // 6. Other headset already Started, Opening, Idle, Closing, or without a state: no request.
  int others[] = {3, 1, 0, 4, -1};
  for (int k = 0; k < 5; k++) {
    reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, others[k]); link_(1, 0, 0); set_root(0, 0); set_active(0);
    char name[32]; snprintf(name, sizeof name, "other-state-%d", others[k]); run(0, name);
    expect_dispatch(name, 0, NULL);
  }

  // 7. Five peers in a tree that exercises both successor paths (left descent, multi-level climb):
  //        3
  //      /   \
  //     1     5          in order: 0 1 2 3 4 5 ... keys 1..6, active = node 3
  //    / \   /
  //   0   2 4
  reset_world();
  int st[6] = {2, 3, 2, 2, -1, 2};          // node 1 Started, node 4 no state
  for (int i = 0; i < 6; i++) mk_peer(i, (uint8_t)(i + 1), st[i]);
  link_(1, 3, 1); link_(5, 3, 0); link_(0, 1, 1); link_(2, 1, 0); link_(4, 5, 1);
  set_root(3, 0); set_active(3); run(1, "tree");
  { int e[] = {0, 2, 5}; expect_dispatch("tree", 3, e); }

  // 8. Left-leaning chain (deep climb) and right-leaning chain (no climb).
  reset_world(); for (int i = 0; i < 4; i++) mk_peer(i, (uint8_t)(i + 1), 2);
  link_(2, 3, 1); link_(1, 2, 1); link_(0, 1, 1); set_root(3, 0); set_active(0); run(0, "left-chain");
  { int e[] = {1, 2, 3}; expect_dispatch("left-chain", 3, e); }
  reset_world(); for (int i = 0; i < 4; i++) mk_peer(i, (uint8_t)(i + 1), 2);
  link_(1, 0, 0); link_(2, 1, 0); link_(3, 2, 0); set_root(0, 0); set_active(3); run(1, "right-chain");
  { int e[] = {0, 1, 2}; expect_dispatch("right-chain", 3, e); }

  // 9. Active peer differs only in the last two address bytes / only in the first four.
  reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, 2); link_(1, 0, 0); set_root(0, 0);
  memcpy(SRC + 0x30, nodes[0].key, 6); ((uint8_t*)SRC)[0x30 + 5] ^= 0x40;   // matches neither
  run(0, "active-unknown"); { int e[] = {0, 1}; expect_dispatch("active-unknown", 2, e); }
  reset_world(); mk_peer(0, 1, 2); mk_peer(1, 2, 2); link_(1, 0, 0); set_root(0, 0);
  memcpy(SRC + 0x30, nodes[1].key, 6); ((uint8_t*)SRC)[0x30] ^= 0x01;
  run(0, "active-first-bytes-differ"); { int e[] = {0, 1}; expect_dispatch("active-first-bytes-differ", 2, e); }

  printf("%d checks, %d failed\n", checks, failures);
  return failures != 0;
}
