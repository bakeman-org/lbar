// src/backends.c
//
// Windowing backend for lbar: Wayland (zwlr-layer-shell + wl_shm) or
// X11 (EWMH dock + override-redirect popups), behind one opaque handle.
#define _GNU_SOURCE
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

/* ---------- X11 ---------- */
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>

/* ---------- Wayland ---------- */
#include <wayland-client.h>

/* ===================================================================
   Logging
   =================================================================== */
static void lbar_log(const char *level, const char *fmt, ...) {
  va_list ap;
  fprintf(stderr, "[%s] lbar: ", level);
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
}
#define LOG_INFO(...) lbar_log("INFO", __VA_ARGS__)
#define LOG_WARN(...) lbar_log("WARN", __VA_ARGS__)
#define LOG_ERROR(...) lbar_log("ERROR", __VA_ARGS__)

/* ===================================================================
   zwlr-layer-shell-unstable-v1 — hand-written protocol descriptors
   =================================================================== */
struct zwlr_layer_shell_v1;
struct zwlr_layer_surface_v1;

#define ZWLR_LAYER_SHELL_V1_GET_LAYER_SURFACE 0

#define ZWLR_LAYER_SURFACE_V1_SET_SIZE 0
#define ZWLR_LAYER_SURFACE_V1_SET_ANCHOR 1
#define ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_ZONE 2
#define ZWLR_LAYER_SURFACE_V1_SET_MARGIN 3
#define ZWLR_LAYER_SURFACE_V1_SET_KEYBOARD_INTERACTIVITY 4
#define ZWLR_LAYER_SURFACE_V1_ACK_CONFIGURE 6
#define ZWLR_LAYER_SURFACE_V1_DESTROY 7

#define ZWLR_LAYER_SHELL_V1_LAYER_TOP 2
#define ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY 3

#define ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP 1
#define ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM 2
#define ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT 4
#define ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT 8

#define ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE 0

struct zwlr_layer_surface_v1_listener {
  void (*configure)(void *data, struct zwlr_layer_surface_v1 *surface,
                    uint32_t serial, uint32_t width, uint32_t height);
  void (*closed)(void *data, struct zwlr_layer_surface_v1 *surface);
};

static const struct wl_interface zwlr_layer_surface_v1_interface;
static const struct wl_interface zwlr_layer_shell_v1_interface;

static const struct wl_interface *zwlr_layer_shell_types[] = {
    &zwlr_layer_surface_v1_interface,
    &wl_surface_interface,
    &wl_output_interface,
    NULL,
    NULL,
};
static const struct wl_message zwlr_layer_shell_requests[] = {
    {"get_layer_surface", "no?ous", zwlr_layer_shell_types},
};
static const struct wl_interface zwlr_layer_shell_v1_interface = {
    "zwlr_layer_shell_v1", 5, 1, zwlr_layer_shell_requests, 0, NULL,
};

static const struct wl_message zwlr_layer_surface_requests[] = {
    {"set_size", "uu", NULL},
    {"set_anchor", "u", NULL},
    {"set_exclusive_zone", "i", NULL},
    {"set_margin", "iiii", NULL},
    {"set_keyboard_interactivity", "u", NULL},
    {"get_popup", "o", NULL},
    {"ack_configure", "u", NULL},
    {"destroy", "", NULL},
};
static const struct wl_message zwlr_layer_surface_events[] = {
    {"configure", "uuu", NULL},
    {"closed", "", NULL},
};
static const struct wl_interface zwlr_layer_surface_v1_interface = {
    "zwlr_layer_surface_v1",     5, 8,
    zwlr_layer_surface_requests, 2, zwlr_layer_surface_events,
};

static inline int zwlr_layer_surface_v1_add_listener(
    struct zwlr_layer_surface_v1 *ls,
    const struct zwlr_layer_surface_v1_listener *listener, void *data) {
  return wl_proxy_add_listener((struct wl_proxy *)ls, (void (**)(void))listener,
                               data);
}

static struct zwlr_layer_surface_v1 *
zwlr_ls_get_layer_surface(struct zwlr_layer_shell_v1 *sh,
                          struct wl_surface *surf, struct wl_output *out,
                          uint32_t layer, const char *ns) {
  return (struct zwlr_layer_surface_v1 *)wl_proxy_marshal_flags(
      (struct wl_proxy *)sh, ZWLR_LAYER_SHELL_V1_GET_LAYER_SURFACE,
      &zwlr_layer_surface_v1_interface,
      wl_proxy_get_version((struct wl_proxy *)sh), 0, NULL, surf, out, layer,
      ns);
}

static void zwlr_ls_set_size(struct zwlr_layer_surface_v1 *ls, uint32_t w,
                             uint32_t h) {
  wl_proxy_marshal_flags((struct wl_proxy *)ls, ZWLR_LAYER_SURFACE_V1_SET_SIZE,
                         NULL, wl_proxy_get_version((struct wl_proxy *)ls), 0,
                         w, h);
}
static void zwlr_ls_set_anchor(struct zwlr_layer_surface_v1 *ls, uint32_t a) {
  wl_proxy_marshal_flags((struct wl_proxy *)ls,
                         ZWLR_LAYER_SURFACE_V1_SET_ANCHOR, NULL,
                         wl_proxy_get_version((struct wl_proxy *)ls), 0, a);
}
static void zwlr_ls_set_exclusive_zone(struct zwlr_layer_surface_v1 *ls,
                                       int32_t z) {
  wl_proxy_marshal_flags((struct wl_proxy *)ls,
                         ZWLR_LAYER_SURFACE_V1_SET_EXCLUSIVE_ZONE, NULL,
                         wl_proxy_get_version((struct wl_proxy *)ls), 0, z);
}
static void zwlr_ls_set_margin(struct zwlr_layer_surface_v1 *ls, int32_t t,
                               int32_t r, int32_t b, int32_t l) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)ls, ZWLR_LAYER_SURFACE_V1_SET_MARGIN, NULL,
      wl_proxy_get_version((struct wl_proxy *)ls), 0, t, r, b, l);
}
static void zwlr_ls_set_kb(struct zwlr_layer_surface_v1 *ls, uint32_t mode) {
  wl_proxy_marshal_flags((struct wl_proxy *)ls,
                         ZWLR_LAYER_SURFACE_V1_SET_KEYBOARD_INTERACTIVITY, NULL,
                         wl_proxy_get_version((struct wl_proxy *)ls), 0, mode);
}
static void zwlr_ls_ack_configure(struct zwlr_layer_surface_v1 *ls,
                                  uint32_t serial) {
  wl_proxy_marshal_flags(
      (struct wl_proxy *)ls, ZWLR_LAYER_SURFACE_V1_ACK_CONFIGURE, NULL,
      wl_proxy_get_version((struct wl_proxy *)ls), 0, serial);
}
static void zwlr_ls_destroy(struct zwlr_layer_surface_v1 *ls) {
  wl_proxy_marshal_flags((struct wl_proxy *)ls, ZWLR_LAYER_SURFACE_V1_DESTROY,
                         NULL, wl_proxy_get_version((struct wl_proxy *)ls),
                         WL_MARSHAL_FLAG_DESTROY);
}

/* ===================================================================
   Context
   =================================================================== */
#define LBAR_EV_MAX 64

typedef struct {
  int type; /* 1=motion 2=press 3=release 4=expose / popup-hidden */
  int x, y;
  int root_x, root_y;
  int button;
  int target; /* 0=bar 1=popup */
} lbar_ev_t;

typedef struct lbar_ctx {
  int is_wayland;
  int screen_w, screen_h;

  lbar_ev_t events[LBAR_EV_MAX];
  int ev_head, ev_tail;

  /* X11 */
  Display *x_dpy;
  int x_screen;
  Window x_root;
  int x_depth;
  Window x_bar_win;
  GC x_bar_gc;
  int x_bar_w, x_bar_h;

  Window x_popup_win;
  GC x_popup_gc;
  Pixmap x_popup_mask;
  int x_popup_w, x_popup_h, x_popup_r;
  int x_popup_visible;

  /* Wayland */
  struct wl_display *wl_dpy;
  struct wl_registry *wl_reg;
  struct wl_compositor *wl_comp;
  struct wl_shm *wl_shm;
  struct wl_seat *wl_seat;
  struct wl_pointer *wl_ptr;
  struct wl_output *wl_out;
  struct zwlr_layer_shell_v1 *wl_shell;

  struct wl_surface *bar_surf;
  struct zwlr_layer_surface_v1 *bar_layer;
  struct wl_shm_pool *bar_pool;
  struct wl_buffer *bar_buf;
  uint32_t *bar_pix;
  int bar_w, bar_h;
  int bar_map_w, bar_map_h;
  int bar_pos;
  int bar_configured;
  int bar_busy;

  struct wl_surface *pop_surf;
  struct zwlr_layer_surface_v1 *pop_layer;
  struct wl_shm_pool *pop_pool;
  struct wl_buffer *pop_buf;
  uint32_t *pop_pix;
  int pop_w, pop_h;
  int pop_map_w, pop_map_h;
  int pop_x, pop_y;
  int pop_visible;
  int pop_configured;
  int pop_busy;

  int have_comp, have_shm, have_seat, have_out, have_shell;

  int ptr_target;   /* 0=elsewhere 1=bar 2=popup */
  int ptr_x, ptr_y; /* last known pointer pos */
  uint32_t ptr_leave_ms;
} lbar_ctx;

/* ===================================================================
   Helpers
   =================================================================== */
static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)((uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void ev_push(lbar_ctx *c, int type, int x, int y, int rx, int ry,
                    int btn, int target) {
  int next = (c->ev_tail + 1) % LBAR_EV_MAX;
  if (next == c->ev_head)
    return;
  lbar_ev_t *e = &c->events[c->ev_tail];
  e->type = type;
  e->x = x;
  e->y = y;
  e->root_x = rx;
  e->root_y = ry;
  e->button = btn;
  e->target = target;
  c->ev_tail = next;
}

static int shm_fd_create(size_t size) {
  int fd = memfd_create("lbar-shm", MFD_CLOEXEC);
  if (fd < 0) {
    char name[64];
    snprintf(name, sizeof(name), "/lbar-%d-%u", (int)getpid(), now_ms());
    fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (fd >= 0)
      shm_unlink(name);
  }
  if (fd < 0)
    return -1;
  if (ftruncate(fd, (off_t)size) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}

/* ===================================================================
   Wayland listeners
   =================================================================== */
static void wl_registry_global(void *data, struct wl_registry *reg,
                               uint32_t name, const char *iface, uint32_t ver) {
  lbar_ctx *c = data;
  if (!strcmp(iface, "wl_compositor")) {
    c->wl_comp = wl_registry_bind(reg, name, &wl_compositor_interface,
                                  ver > 4 ? 4 : ver);
    c->have_comp = 1;
    LOG_INFO("wl_compositor v%u", ver);
  } else if (!strcmp(iface, "wl_shm")) {
    c->wl_shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    c->have_shm = 1;
    LOG_INFO("wl_shm v%u", ver);
  } else if (!strcmp(iface, "wl_seat")) {
    c->wl_seat =
        wl_registry_bind(reg, name, &wl_seat_interface, ver > 5 ? 5 : ver);
    c->have_seat = 1;
    LOG_INFO("wl_seat v%u", ver);
  } else if (!strcmp(iface, "wl_output")) {
    if (!c->wl_out) {
      c->wl_out =
          wl_registry_bind(reg, name, &wl_output_interface, ver > 4 ? 4 : ver);
      c->have_out = 1;
      LOG_INFO("wl_output v%u", ver);
    }
  } else if (!strcmp(iface, "zwlr_layer_shell_v1")) {
    c->wl_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface,
                                   ver > 1 ? 1 : ver);
    c->have_shell = 1;
    LOG_INFO("zwlr_layer_shell_v1 v%u", ver);
  }
}
static void wl_registry_remove(void *d, struct wl_registry *r, uint32_t n) {
  (void)d;
  (void)r;
  (void)n;
}

static const struct wl_registry_listener registry_listener = {
    wl_registry_global, wl_registry_remove};

/* --- Pointer --- */
static void ptr_enter(void *data, struct wl_pointer *p, uint32_t serial,
                      struct wl_surface *surf, wl_fixed_t sx, wl_fixed_t sy) {
  lbar_ctx *c = data;
  (void)p;
  (void)serial;
  if (surf == c->bar_surf)
    c->ptr_target = 1;
  else if (surf == c->pop_surf)
    c->ptr_target = 2;
  else
    c->ptr_target = 0;
  c->ptr_x = wl_fixed_to_int(sx);
  c->ptr_y = wl_fixed_to_int(sy);
  ev_push(c, 1, c->ptr_x, c->ptr_y, 0, 0, 0, c->ptr_target == 2 ? 1 : 0);
}
static void ptr_leave(void *data, struct wl_pointer *p, uint32_t serial,
                      struct wl_surface *surf) {
  lbar_ctx *c = data;
  (void)p;
  (void)serial;
  (void)surf;
  c->ptr_target = 0;
  c->ptr_leave_ms = now_ms();
}
static void ptr_motion(void *data, struct wl_pointer *p, uint32_t t,
                       wl_fixed_t sx, wl_fixed_t sy) {
  lbar_ctx *c = data;
  (void)p;
  (void)t;
  if (c->ptr_target == 0)
    return;
  c->ptr_x = wl_fixed_to_int(sx);
  c->ptr_y = wl_fixed_to_int(sy);
  ev_push(c, 1, c->ptr_x, c->ptr_y, 0, 0, 0, c->ptr_target == 2 ? 1 : 0);
}
static void ptr_button(void *data, struct wl_pointer *p, uint32_t serial,
                       uint32_t t, uint32_t btn, uint32_t state) {
  lbar_ctx *c = data;
  (void)p;
  (void)serial;
  (void)t;
  if (c->ptr_target == 0)
    return;
  int type = (state == WL_POINTER_BUTTON_STATE_PRESSED) ? 2 : 3;
  /* Use the last known pointer position — Wayland button events carry no
     coordinates, unlike X11. Without this, the Lua layer receives (0,0). */
  ev_push(c, type, c->ptr_x, c->ptr_y, 0, 0, (int)btn,
          c->ptr_target == 2 ? 1 : 0);
}
static void ptr_axis(void *data, struct wl_pointer *p, uint32_t t,
                     uint32_t axis, wl_fixed_t value) {
  lbar_ctx *c = data;
  (void)p;
  (void)t;
  if (axis != WL_POINTER_AXIS_VERTICAL_SCROLL)
    return;
  if (c->ptr_target == 0)
    return;
  int btn = (value < 0) ? 4 : 5;
  ev_push(c, 2, c->ptr_x, c->ptr_y, 0, 0, btn, c->ptr_target == 2 ? 1 : 0);
}
static void ptr_frame(void *d, struct wl_pointer *p) {
  (void)d;
  (void)p;
}
static void ptr_axis_source(void *d, struct wl_pointer *p, uint32_t s) {
  (void)d;
  (void)p;
  (void)s;
}
static void ptr_axis_stop(void *d, struct wl_pointer *p, uint32_t t,
                          uint32_t a) {
  (void)d;
  (void)p;
  (void)t;
  (void)a;
}
static void ptr_axis_discrete(void *d, struct wl_pointer *p, uint32_t a,
                              int32_t v) {
  (void)d;
  (void)p;
  (void)a;
  (void)v;
}
static void ptr_axis_value120(void *d, struct wl_pointer *p, uint32_t a,
                              int32_t v) {
  (void)d;
  (void)p;
  (void)a;
  (void)v;
}
static void ptr_axis_rel_dir(void *d, struct wl_pointer *p, uint32_t a,
                             uint32_t v) {
  (void)d;
  (void)p;
  (void)a;
  (void)v;
}

static const struct wl_pointer_listener pointer_listener = {
    .enter = ptr_enter,
    .leave = ptr_leave,
    .motion = ptr_motion,
    .button = ptr_button,
    .axis = ptr_axis,
    .frame = ptr_frame,
    .axis_source = ptr_axis_source,
    .axis_stop = ptr_axis_stop,
    .axis_discrete = ptr_axis_discrete,
    .axis_value120 = ptr_axis_value120,
    .axis_relative_direction = ptr_axis_rel_dir,
};

/* --- Layer surface --- */
static void bar_configure(void *data, struct zwlr_layer_surface_v1 *ls,
                          uint32_t serial, uint32_t w, uint32_t h);
static void pop_configure(void *data, struct zwlr_layer_surface_v1 *ls,
                          uint32_t serial, uint32_t w, uint32_t h);
static void bar_closed(void *data, struct zwlr_layer_surface_v1 *ls);
static void pop_closed(void *data, struct zwlr_layer_surface_v1 *ls);

static const struct zwlr_layer_surface_v1_listener bar_layer_listener = {
    .configure = bar_configure,
    .closed = bar_closed,
};
static const struct zwlr_layer_surface_v1_listener pop_layer_listener = {
    .configure = pop_configure,
    .closed = pop_closed,
};

static void bar_buf_release(void *data, struct wl_buffer *b) {
  lbar_ctx *c = data;
  (void)b;
  c->bar_busy = 0;
}
static const struct wl_buffer_listener bar_buf_listener = {
    .release = bar_buf_release,
};
static void pop_buf_release(void *data, struct wl_buffer *b) {
  lbar_ctx *c = data;
  (void)b;
  c->pop_busy = 0;
}
static const struct wl_buffer_listener pop_buf_listener = {
    .release = pop_buf_release,
};

/* ===================================================================
   Wayland create / destroy helpers
   =================================================================== */
static int wl_make_buffer(struct wl_shm *shm, int w, int h,
                          struct wl_shm_pool **pool_out,
                          struct wl_buffer **buf_out, uint32_t **pixels_out) {
  int stride = w * 4;
  size_t sz = (size_t)stride * h;
  int fd = shm_fd_create(sz);
  if (fd < 0)
    return -1;
  void *pix = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (pix == MAP_FAILED) {
    close(fd);
    return -1;
  }
  struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, (int32_t)sz);
  close(fd);
  if (!pool) {
    munmap(pix, sz);
    return -1;
  }
  struct wl_buffer *buf =
      wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
  if (!buf) {
    wl_shm_pool_destroy(pool);
    munmap(pix, sz);
    return -1;
  }
  *pool_out = pool;
  *buf_out = buf;
  *pixels_out = pix;
  return 0;
}

static int recreate_bar_buffer(lbar_ctx *c) {
  if (c->bar_buf) {
    wl_buffer_destroy(c->bar_buf);
    c->bar_buf = NULL;
  }
  if (c->bar_pool) {
    wl_shm_pool_destroy(c->bar_pool);
    c->bar_pool = NULL;
  }
  if (c->bar_pix) {
    munmap(c->bar_pix, (size_t)c->bar_map_w * c->bar_map_h * 4);
    c->bar_pix = NULL;
  }
  c->bar_map_w = c->bar_w;
  c->bar_map_h = c->bar_h;
  if (wl_make_buffer(c->wl_shm, c->bar_w, c->bar_h, &c->bar_pool, &c->bar_buf,
                     &c->bar_pix) < 0) {
    LOG_ERROR("recreate_bar_buffer failed (%dx%d)", c->bar_w, c->bar_h);
    return -1;
  }
  wl_buffer_add_listener(c->bar_buf, &bar_buf_listener, c);
  c->bar_busy = 0;
  LOG_INFO("bar buffer %dx%d", c->bar_w, c->bar_h);
  return 0;
}

static int recreate_pop_buffer(lbar_ctx *c) {
  if (c->pop_buf) {
    wl_buffer_destroy(c->pop_buf);
    c->pop_buf = NULL;
  }
  if (c->pop_pool) {
    wl_shm_pool_destroy(c->pop_pool);
    c->pop_pool = NULL;
  }
  if (c->pop_pix) {
    munmap(c->pop_pix, (size_t)c->pop_map_w * c->pop_map_h * 4);
    c->pop_pix = NULL;
  }
  c->pop_map_w = c->pop_w;
  c->pop_map_h = c->pop_h;
  if (wl_make_buffer(c->wl_shm, c->pop_w, c->pop_h, &c->pop_pool, &c->pop_buf,
                     &c->pop_pix) < 0) {
    LOG_ERROR("recreate_pop_buffer failed (%dx%d)", c->pop_w, c->pop_h);
    return -1;
  }
  wl_buffer_add_listener(c->pop_buf, &pop_buf_listener, c);
  c->pop_busy = 0;
  LOG_INFO("popup buffer %dx%d", c->pop_w, c->pop_h);
  return 0;
}

static void bar_configure(void *data, struct zwlr_layer_surface_v1 *ls,
                          uint32_t serial, uint32_t w, uint32_t h) {
  lbar_ctx *c = data;
  zwlr_ls_ack_configure(ls, serial);
  if ((int)w != c->bar_w || (int)h != c->bar_h) {
    LOG_INFO("bar configure -> %ux%u", w, h);
    c->bar_w = (int)w;
    c->bar_h = (int)h;
    recreate_bar_buffer(c);
  }
  c->bar_configured = 1;
}
static void bar_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
  (void)data;
  (void)ls;
  LOG_WARN("bar layer closed");
}
static void pop_configure(void *data, struct zwlr_layer_surface_v1 *ls,
                          uint32_t serial, uint32_t w, uint32_t h) {
  lbar_ctx *c = data;
  zwlr_ls_ack_configure(ls, serial);
  int nw = (int)w, nh = (int)h;
  if (nw <= 0)
    nw = c->pop_w;
  if (nh <= 0)
    nh = c->pop_h;
  if (nw != c->pop_w || nh != c->pop_h) {
    LOG_INFO("popup configure -> %dx%d", nw, nh);
    c->pop_w = nw;
    c->pop_h = nh;
    recreate_pop_buffer(c);
  }
  c->pop_configured = 1;
}
static void pop_closed(void *data, struct zwlr_layer_surface_v1 *ls) {
  (void)data;
  (void)ls;
  LOG_WARN("popup layer closed");
}

static int wl_open(lbar_ctx *c) {
  c->wl_dpy = wl_display_connect(NULL);
  if (!c->wl_dpy) {
    LOG_ERROR("wl_display_connect failed");
    return -1;
  }
  c->wl_reg = wl_display_get_registry(c->wl_dpy);
  wl_registry_add_listener(c->wl_reg, &registry_listener, c);
  wl_display_roundtrip(c->wl_dpy);

  if (!c->have_comp || !c->have_shm || !c->have_out || !c->have_shell) {
    LOG_ERROR("missing globals: comp=%d shm=%d out=%d shell=%d", c->have_comp,
              c->have_shm, c->have_out, c->have_shell);
    return -2;
  }

  if (c->have_seat) {
    c->wl_ptr = wl_seat_get_pointer(c->wl_seat);
    if (c->wl_ptr)
      wl_pointer_add_listener(c->wl_ptr, &pointer_listener, c);
  }
  wl_display_roundtrip(c->wl_dpy);
  LOG_INFO("wayland connected");
  return 0;
}

static int wl_create_bar(lbar_ctx *c, int h, int pos) {
  c->bar_pos = pos;
  c->bar_w = c->screen_w;
  c->bar_h = h;

  c->bar_surf = wl_compositor_create_surface(c->wl_comp);
  uint32_t anchor = (pos == 0) ? (ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                  ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
                                  ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT)
                               : (ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                  ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
                                  ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);

  c->bar_layer =
      zwlr_ls_get_layer_surface(c->wl_shell, c->bar_surf, c->wl_out,
                                ZWLR_LAYER_SHELL_V1_LAYER_TOP, "lbar");
  zwlr_ls_set_size(c->bar_layer, c->bar_w, c->bar_h);
  zwlr_ls_set_anchor(c->bar_layer, anchor);
  zwlr_ls_set_exclusive_zone(c->bar_layer, c->bar_h);
  zwlr_ls_set_kb(c->bar_layer,
                 ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
  zwlr_layer_surface_v1_add_listener(c->bar_layer, &bar_layer_listener, c);

  c->bar_map_w = c->bar_w;
  c->bar_map_h = c->bar_h;
  if (wl_make_buffer(c->wl_shm, c->bar_w, c->bar_h, &c->bar_pool, &c->bar_buf,
                     &c->bar_pix) < 0)
    return -1;
  wl_buffer_add_listener(c->bar_buf, &bar_buf_listener, c);

  wl_surface_commit(c->bar_surf);
  wl_display_roundtrip(c->wl_dpy);
  LOG_INFO("bar created: %dx%d pos=%s", c->bar_w, c->bar_h,
           pos == 0 ? "top" : "bottom");
  return 0;
}

static int wl_create_popup(lbar_ctx *c, int w, int h, int r) {
  (void)r;
  c->pop_w = w;
  c->pop_h = h;

  c->pop_surf = wl_compositor_create_surface(c->wl_comp);
  c->pop_layer = zwlr_ls_get_layer_surface(c->wl_shell, c->pop_surf, c->wl_out,
                                           ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
                                           "lbar-popup");
  zwlr_ls_set_size(c->pop_layer, w, h);
  zwlr_ls_set_anchor(c->pop_layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
  zwlr_ls_set_exclusive_zone(c->pop_layer, 0);
  zwlr_ls_set_kb(c->pop_layer,
                 ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
  zwlr_layer_surface_v1_add_listener(c->pop_layer, &pop_layer_listener, c);

  c->pop_map_w = w;
  c->pop_map_h = h;
  if (wl_make_buffer(c->wl_shm, w, h, &c->pop_pool, &c->pop_buf, &c->pop_pix) <
      0)
    return -1;
  wl_buffer_add_listener(c->pop_buf, &pop_buf_listener, c);

  wl_surface_commit(c->pop_surf);
  wl_display_roundtrip(c->wl_dpy);
  LOG_INFO("popup created: %dx%d r=%d", w, h, r);
  return 0;
}

static void wl_popup_set_position(lbar_ctx *c, int x, int y) {
  c->pop_x = x;
  c->pop_y = y;
  if (!c->pop_layer)
    return;
  zwlr_ls_set_margin(c->pop_layer, y, 0, 0, x);
  wl_surface_commit(c->pop_surf);
}
static void wl_popup_show(lbar_ctx *c) {
  c->pop_visible = 1;
  /* 允许重新 attach buffer；否则 hide 之后 buffer 永远刷不上去 */
  c->pop_busy = 0;
  if (c->pop_surf)
    wl_surface_commit(c->pop_surf);
  wl_display_flush(c->wl_dpy);
  LOG_INFO("popup show at (%d,%d)", c->pop_x, c->pop_y);
}

static void wl_popup_hide(lbar_ctx *c) {
  c->pop_visible = 0;
  if (c->pop_surf) {
    wl_surface_attach(c->pop_surf, NULL, 0, 0);
    wl_surface_commit(c->pop_surf);
  }
  c->pop_busy = 0; /* 关键：让下次 flush 能重新 attach */
  wl_display_flush(c->wl_dpy);
  LOG_INFO("popup hide");
}
/* ===================================================================
   X11
   =================================================================== */
static int x_error_handler(Display *d, XErrorEvent *e) {
  LOG_WARN("X error: code=%d req=%d.%d resource=0x%lx", e->error_code,
           e->request_code, e->minor_code, e->resourceid);
  (void)d;
  return 0;
}

static int x_open(lbar_ctx *c) {
  c->x_dpy = XOpenDisplay(NULL);
  if (!c->x_dpy) {
    LOG_ERROR("XOpenDisplay failed");
    return -1;
  }
  XSetErrorHandler(x_error_handler);
  c->x_screen = DefaultScreen(c->x_dpy);
  c->x_root = RootWindow(c->x_dpy, c->x_screen);
  c->x_depth = DefaultDepth(c->x_dpy, c->x_screen);
  c->screen_w = DisplayWidth(c->x_dpy, c->x_screen);
  c->screen_h = DisplayHeight(c->x_dpy, c->x_screen);
  LOG_INFO("x11 connected: %dx%d depth=%d", c->screen_w, c->screen_h,
           c->x_depth);
  return 0;
}

static int x_create_bar(lbar_ctx *c, int h, int pos) {
  int y = (pos == 0) ? 0 : (c->screen_h - h);
  XSetWindowAttributes a;
  memset(&a, 0, sizeof(a));
  /* 不再使用 override_redirect：必须让 WM 接管，strut 才会被处理 */
  a.override_redirect = 0;
  a.background_pixel = 0x1c1c1e;
  a.border_pixel = 0x1c1c1e;
  unsigned long mask = CWBackPixel | CWBorderPixel;

  c->x_bar_win =
      XCreateWindow(c->x_dpy, c->x_root, 0, y, c->screen_w, h, 0, c->x_depth,
                    InputOutput, CopyFromParent, mask, &a);

  long evmask = ExposureMask | ButtonPressMask | ButtonReleaseMask |
                PointerMotionMask | EnterWindowMask | LeaveWindowMask;
  XSelectInput(c->x_dpy, c->x_bar_win, evmask);
  c->x_bar_gc = XCreateGC(c->x_dpy, c->x_bar_win, 0, NULL);

  /* 告诉 WM 我们想要的位置和尺寸，避免它重新摆放 */
  XSizeHints hints;
  memset(&hints, 0, sizeof(hints));
  hints.flags = PPosition | PSize;
  hints.x = 0;
  hints.y = y;
  hints.width = c->screen_w;
  hints.height = h;
  XSetWMNormalHints(c->x_dpy, c->x_bar_win, &hints);

  /* ---- EWMH 属性：必须在 XMapWindow 之前设置 ---- */
  Atom type = XInternAtom(c->x_dpy, "_NET_WM_WINDOW_TYPE", 0);
  Atom dock = XInternAtom(c->x_dpy, "_NET_WM_WINDOW_TYPE_DOCK", 0);
  XChangeProperty(c->x_dpy, c->x_bar_win, type, XA_ATOM, 32, PropModeReplace,
                  (unsigned char *)&dock, 1);

  Atom desktop = XInternAtom(c->x_dpy, "_NET_WM_DESKTOP", 0);
  unsigned long all = 0xFFFFFFFF;
  XChangeProperty(c->x_dpy, c->x_bar_win, desktop, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)&all, 1);

  Atom state = XInternAtom(c->x_dpy, "_NET_WM_STATE", 0);
  Atom above = XInternAtom(c->x_dpy, "_NET_WM_STATE_ABOVE", 0);
  Atom sticky = XInternAtom(c->x_dpy, "_NET_WM_STATE_STICKY", 0);
  Atom skip_taskbar = XInternAtom(c->x_dpy, "_NET_WM_STATE_SKIP_TASKBAR", 0);
  Atom skip_pager = XInternAtom(c->x_dpy, "_NET_WM_STATE_SKIP_PAGER", 0);
  Atom states[4] = {above, sticky, skip_taskbar, skip_pager};
  XChangeProperty(c->x_dpy, c->x_bar_win, state, XA_ATOM, 32, PropModeReplace,
                  (unsigned char *)states, 4);

  /* ---- strut：保留原有逻辑 ---- */
  Atom strut = XInternAtom(c->x_dpy, "_NET_WM_STRUT_PARTIAL", 0);
  unsigned long s[12] = {0};
  if (pos == 0) {
    s[2] = h;
    s[8] = 0;
    s[9] = c->screen_w;
  } else {
    s[3] = h;
    s[10] = 0;
    s[11] = c->screen_w;
  }
  XChangeProperty(c->x_dpy, c->x_bar_win, strut, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)s, 12);

  Atom strut4 = XInternAtom(c->x_dpy, "_NET_WM_STRUT", 0);
  unsigned long s4[4] = {0};
  if (pos == 0)
    s4[2] = h;
  else
    s4[3] = h;
  XChangeProperty(c->x_dpy, c->x_bar_win, strut4, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)s4, 4);

  XMapWindow(c->x_dpy, c->x_bar_win);
  XFlush(c->x_dpy);

  c->bar_w = c->screen_w;
  c->bar_h = h;
  LOG_INFO("bar created: %dx%d pos=%s", c->bar_w, c->bar_h,
           pos == 0 ? "top" : "bottom");
  return 0;
}

static int x_create_popup(lbar_ctx *c, int w, int h, int r) {
  c->x_popup_w = w;
  c->x_popup_h = h;
  c->x_popup_r = r;
  XSetWindowAttributes a;
  memset(&a, 0, sizeof(a));
  a.override_redirect = 1;
  a.background_pixel = 0x1c1c1e;
  a.border_pixel = 0x1c1c1e;
  unsigned long mask = CWOverrideRedirect | CWBackPixel | CWBorderPixel;

  c->x_popup_win = XCreateWindow(c->x_dpy, c->x_root, 0, 0, w, h, 0, c->x_depth,
                                 InputOutput, CopyFromParent, mask, &a);
  long evmask =
      ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask;
  XSelectInput(c->x_dpy, c->x_popup_win, evmask);
  c->x_popup_gc = XCreateGC(c->x_dpy, c->x_popup_win, 0, NULL);

  c->x_popup_mask = XCreatePixmap(c->x_dpy, c->x_popup_win, w, h, 1);
  GC gc = XCreateGC(c->x_dpy, c->x_popup_mask, 0, NULL);
  XSetForeground(c->x_dpy, gc, 0);
  XFillRectangle(c->x_dpy, c->x_popup_mask, gc, 0, 0, w, h);
  XSetForeground(c->x_dpy, gc, 1);
  if (r <= 0 || r * 2 >= w || r * 2 >= h) {
    XFillRectangle(c->x_dpy, c->x_popup_mask, gc, 0, 0, w, h);
  } else {
    XFillRectangle(c->x_dpy, c->x_popup_mask, gc, r, 0, w - 2 * r, h);
    XFillRectangle(c->x_dpy, c->x_popup_mask, gc, 0, r, r, h - 2 * r);
    XFillRectangle(c->x_dpy, c->x_popup_mask, gc, w - r, r, r, h - 2 * r);
    int D = 64;
    XFillArc(c->x_dpy, c->x_popup_mask, gc, 0, 0, 2 * r, 2 * r, 90 * D, 90 * D);
    XFillArc(c->x_dpy, c->x_popup_mask, gc, w - 2 * r, 0, 2 * r, 2 * r, 0,
             90 * D);
    XFillArc(c->x_dpy, c->x_popup_mask, gc, 0, h - 2 * r, 2 * r, 2 * r, 180 * D,
             90 * D);
    XFillArc(c->x_dpy, c->x_popup_mask, gc, w - 2 * r, h - 2 * r, 2 * r, 2 * r,
             270 * D, 90 * D);
  }
  XFreeGC(c->x_dpy, gc);
  XShapeCombineMask(c->x_dpy, c->x_popup_win, ShapeBounding, 0, 0,
                    c->x_popup_mask, ShapeSet);
  LOG_INFO("popup created: %dx%d r=%d", w, h, r);
  return 0;
}

static void x_popup_move(lbar_ctx *c, int x, int y) {
  if (c->x_popup_win)
    XMoveWindow(c->x_dpy, c->x_popup_win, x, y);
}
static void x_popup_show(lbar_ctx *c) {
  if (c->x_popup_win) {
    XMapWindow(c->x_dpy, c->x_popup_win);
    XRaiseWindow(c->x_dpy, c->x_popup_win);
    XFlush(c->x_dpy);
    c->x_popup_visible = 1;
    /* 不再 XGrabPointer：抓取会让整个 X 会话失去响应 */
    LOG_INFO("popup show");
  }
}

static void x_popup_hide(lbar_ctx *c) {
  if (!c->x_popup_visible)
    return;
  c->x_popup_visible = 0;
  XUnmapWindow(c->x_dpy, c->x_popup_win);
  XFlush(c->x_dpy);
  LOG_INFO("popup hide");
}

/* ===================================================================
   Public API
   =================================================================== */
lbar_ctx *lbar_open(void) {
  lbar_ctx *c = calloc(1, sizeof(*c));
  if (!c)
    return NULL;

  if (getenv("WAYLAND_DISPLAY") && getenv("WAYLAND_DISPLAY")[0]) {
    c->is_wayland = 1;
    if (wl_open(c) == 0) {
      /* Wayland doesn't give us the output size without a listener;
         use X11 as a side-channel to measure. */
      Display *tmp = XOpenDisplay(NULL);
      if (tmp) {
        c->screen_w = DisplayWidth(tmp, DefaultScreen(tmp));
        c->screen_h = DisplayHeight(tmp, DefaultScreen(tmp));
        XCloseDisplay(tmp);
        LOG_INFO("screen: %dx%d (from X11)", c->screen_w, c->screen_h);
      } else {
        c->screen_w = 1920;
        c->screen_h = 1080;
        LOG_WARN("cannot measure screen, assuming %dx%d", c->screen_w,
                 c->screen_h);
      }
      return c;
    }
    LOG_WARN("wayland backend failed, falling back to X11");
    if (c->wl_dpy) {
      wl_display_disconnect(c->wl_dpy);
      c->wl_dpy = NULL;
    }
    c->is_wayland = 0;
  }
  if (x_open(c) != 0) {
    free(c);
    return NULL;
  }
  return c;
}

const char *lbar_backend(lbar_ctx *c) {
  return c->is_wayland ? "wayland" : "x11";
}
int lbar_screen_w(lbar_ctx *c) { return c->screen_w; }
int lbar_screen_h(lbar_ctx *c) { return c->screen_h; }
int lbar_bar_width(lbar_ctx *c) { return c->bar_w; }
int lbar_bar_height(lbar_ctx *c) { return c->bar_h; }

int lbar_bar_create(lbar_ctx *c, int h, int pos) {
  return c->is_wayland ? wl_create_bar(c, h, pos) : x_create_bar(c, h, pos);
}

void lbar_bar_flush(lbar_ctx *c, const uint32_t *pixels) {
  if (c->is_wayland) {
    if (c->bar_map_w != c->bar_w || c->bar_map_h != c->bar_h) {
      if (recreate_bar_buffer(c) < 0)
        return;
    }
    if (c->bar_busy || !c->bar_buf)
      return;
    memcpy(c->bar_pix, pixels, (size_t)c->bar_w * c->bar_h * 4);
    wl_surface_attach(c->bar_surf, c->bar_buf, 0, 0);
    wl_surface_damage(c->bar_surf, 0, 0, c->bar_w, c->bar_h);
    wl_surface_commit(c->bar_surf);
    wl_display_flush(c->wl_dpy);
    c->bar_busy = 1;
  } else {
    XImage *img = XCreateImage(c->x_dpy, DefaultVisual(c->x_dpy, c->x_screen),
                               (unsigned int)c->x_depth, ZPixmap, 0,
                               (char *)pixels, c->bar_w, c->bar_h, 32, 0);
    if (!img)
      return;
    XPutImage(c->x_dpy, c->x_bar_win, c->x_bar_gc, img, 0, 0, 0, 0, c->bar_w,
              c->bar_h);
    XFlush(c->x_dpy);
    img->data = NULL;
    XDestroyImage(img);
  }
}

int lbar_popup_create(lbar_ctx *c, int w, int h, int r) {
  return c->is_wayland ? wl_create_popup(c, w, h, r)
                       : x_create_popup(c, w, h, r);
}
void lbar_popup_move(lbar_ctx *c, int x, int y) {
  if (c->is_wayland)
    wl_popup_set_position(c, x, y);
  else
    x_popup_move(c, x, y);
}
void lbar_popup_show(lbar_ctx *c) {
  if (c->is_wayland)
    wl_popup_show(c);
  else
    x_popup_show(c);
}
void lbar_popup_hide(lbar_ctx *c) {
  if (c->is_wayland)
    wl_popup_hide(c);
  else
    x_popup_hide(c);
}
int lbar_popup_visible(lbar_ctx *c) {
  return c->is_wayland ? c->pop_visible : c->x_popup_visible;
}

void lbar_popup_flush(lbar_ctx *c, const uint32_t *pixels) {
  if (c->is_wayland) {
    if (c->pop_map_w != c->pop_w || c->pop_map_h != c->pop_h) {
      if (recreate_pop_buffer(c) < 0)
        return;
    }
    if (c->pop_busy || !c->pop_buf)
      return;
    memcpy(c->pop_pix, pixels, (size_t)c->pop_w * c->pop_h * 4);
    wl_surface_attach(c->pop_surf, c->pop_buf, 0, 0);
    wl_surface_damage(c->pop_surf, 0, 0, c->pop_w, c->pop_h);
    wl_surface_commit(c->pop_surf);
    wl_display_flush(c->wl_dpy);
    c->pop_busy = 1;
  } else {
    XImage *img =
        XCreateImage(c->x_dpy, DefaultVisual(c->x_dpy, c->x_screen),
                     (unsigned int)c->x_depth, ZPixmap, 0, (char *)pixels,
                     c->x_popup_w, c->x_popup_h, 32, 0);
    if (!img)
      return;
    XPutImage(c->x_dpy, c->x_popup_win, c->x_popup_gc, img, 0, 0, 0, 0,
              c->x_popup_w, c->x_popup_h);
    XFlush(c->x_dpy);
    img->data = NULL;
    XDestroyImage(img);
  }
}

/* ---- Events ---- */
static void drain_x11_events(lbar_ctx *c) {
  while (XPending(c->x_dpy) > 0) {
    XEvent e;
    XNextEvent(c->x_dpy, &e);
    if (e.type == Expose) {
      if (e.xexpose.window == c->x_bar_win)
        ev_push(c, 4, 0, 0, 0, 0, 0, 0);
      else if (e.xexpose.window == c->x_popup_win)
        ev_push(c, 4, 0, 0, 0, 0, 0, 1);
    } else if (e.type == MotionNotify) {
      int tgt = (e.xmotion.window == c->x_popup_win) ? 1 : 0;
      ev_push(c, 1, e.xmotion.x, e.xmotion.y, e.xmotion.x_root,
              e.xmotion.y_root, 0, tgt);
    } else if (e.type == ButtonPress) {
      int tgt = (e.xbutton.window == c->x_popup_win) ? 1 : 0;
      ev_push(c, 2, e.xbutton.x, e.xbutton.y, e.xbutton.x_root,
              e.xbutton.y_root, e.xbutton.button, tgt);
    } else if (e.type == ButtonRelease) {
      int tgt = (e.xbutton.window == c->x_popup_win) ? 1 : 0;
      ev_push(c, 3, e.xbutton.x, e.xbutton.y, e.xbutton.x_root,
              e.xbutton.y_root, e.xbutton.button, tgt);
    }
  }
}

int lbar_poll(lbar_ctx *c, int timeout_ms) {
  if (c->is_wayland) {
    /* 删除 pop_visible && ptr_target==0 && leave_ms>300 的自动隐藏分支 */
    wl_display_dispatch_pending(c->wl_dpy);
    wl_display_flush(c->wl_dpy);
    struct pollfd pfd = {wl_display_get_fd(c->wl_dpy), POLLIN, 0};
    if (poll(&pfd, 1, timeout_ms) > 0) {
      wl_display_dispatch(c->wl_dpy);
      wl_display_dispatch_pending(c->wl_dpy);
    }
    wl_display_flush(c->wl_dpy);
  } else {
    if (timeout_ms > 0) {
      struct pollfd pfd = {ConnectionNumber(c->x_dpy), POLLIN, 0};
      poll(&pfd, 1, timeout_ms);
    }
    drain_x11_events(c);
  }
  return 0;
}

int lbar_next_event(lbar_ctx *c, lbar_ev_t *out) {
  if (c->ev_head == c->ev_tail)
    return 0;
  *out = c->events[c->ev_head];
  c->ev_head = (c->ev_head + 1) % LBAR_EV_MAX;
  return 1;
}

void lbar_close(lbar_ctx *c) {
  if (!c)
    return;
  if (c->is_wayland) {
    if (c->pop_surf)
      wl_surface_destroy(c->pop_surf);
    if (c->pop_layer)
      zwlr_ls_destroy(c->pop_layer);
    if (c->pop_buf)
      wl_buffer_destroy(c->pop_buf);
    if (c->pop_pool)
      wl_shm_pool_destroy(c->pop_pool);
    if (c->pop_pix)
      munmap(c->pop_pix, (size_t)c->pop_map_w * c->pop_map_h * 4);

    if (c->bar_surf)
      wl_surface_destroy(c->bar_surf);
    if (c->bar_layer)
      zwlr_ls_destroy(c->bar_layer);
    if (c->bar_buf)
      wl_buffer_destroy(c->bar_buf);
    if (c->bar_pool)
      wl_shm_pool_destroy(c->bar_pool);
    if (c->bar_pix)
      munmap(c->bar_pix, (size_t)c->bar_map_w * c->bar_map_h * 4);

    if (c->wl_ptr)
      wl_pointer_destroy(c->wl_ptr);
    if (c->wl_seat)
      wl_seat_destroy(c->wl_seat);
    if (c->wl_out)
      wl_output_destroy(c->wl_out);
    if (c->wl_shell)
      wl_proxy_destroy((struct wl_proxy *)c->wl_shell);
    if (c->wl_shm)
      wl_shm_destroy(c->wl_shm);
    if (c->wl_comp)
      wl_compositor_destroy(c->wl_comp);
    if (c->wl_reg)
      wl_registry_destroy(c->wl_reg);
    if (c->wl_dpy)
      wl_display_disconnect(c->wl_dpy);
    LOG_INFO("wayland closed");
  } else {
    if (c->x_popup_win)
      XDestroyWindow(c->x_dpy, c->x_popup_win);
    if (c->x_popup_gc)
      XFreeGC(c->x_dpy, c->x_popup_gc);
    if (c->x_popup_mask)
      XFreePixmap(c->x_dpy, c->x_popup_mask);
    if (c->x_bar_win)
      XDestroyWindow(c->x_dpy, c->x_bar_win);
    if (c->x_bar_gc)
      XFreeGC(c->x_dpy, c->x_bar_gc);
    if (c->x_dpy)
      XCloseDisplay(c->x_dpy);
    LOG_INFO("x11 closed");
  }
  free(c);
}