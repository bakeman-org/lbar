// src/backends.c
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

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/shape.h>

#include <wayland-client.h>

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

#define LBAR_EV_MAX 64
#define LBAR_POPUP_MAX 16

typedef struct {
  int type; /* 1=motion 2=press 3=release 4=expose/popup-hidden 5=key */
  int x, y;
  int root_x, root_y;
  int button;
  int target; /* 0=bar 1=popup 2=key */
  int keycode;
  int keystate;
} lbar_ev_t;

typedef struct {
  /* shared */
  int w, h, r;
  int visible;
  /* X11 */
  Window x_win;
  GC x_gc;
  /* Wayland */
  struct wl_surface *surf;
  struct zwlr_layer_surface_v1 *layer;
  struct wl_shm_pool *pool;
  struct wl_buffer *buf;
  uint32_t *pix;
  int map_w, map_h;
  int x, y;
  int configured;
  int busy;
} lbar_popup_t;

typedef struct lbar_ctx {
  int is_wayland;
  int screen_w, screen_h;

  lbar_ev_t events[LBAR_EV_MAX];
  int ev_head, ev_tail;

  Display *x_dpy;
  int x_screen;
  Window x_root;
  int x_depth;
  Window x_bar_win;
  GC x_bar_gc;
  int x_bar_w, x_bar_h;

  lbar_popup_t popups[LBAR_POPUP_MAX];
  int n_popups;

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

  int have_comp, have_shm, have_seat, have_out, have_shell;

  int ptr_target;
  int ptr_x, ptr_y;
  uint32_t ptr_leave_ms;
} lbar_ctx;

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)((uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static void ev_push(lbar_ctx *c, int type, int x, int y, int rx, int ry,
                    int btn, int target, int key, int ks) {
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
  e->keycode = key;
  e->keystate = ks;
  c->ev_tail = next;
}

static int shm_fd_create(size_t size) {
  int fd = memfd_create("lbar-shm", MFD_CLOEXEC);
  if (fd < 0) {
    char name[64];
    snprintf(name, sizeof(name), "/tmp/lbar-shm-%d", getpid());
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

static void ptr_enter(void *data, struct wl_pointer *p, uint32_t serial,
                      struct wl_surface *surf, wl_fixed_t sx, wl_fixed_t sy) {
  lbar_ctx *c = data;
  (void)p;
  (void)serial;
  if (surf == c->bar_surf)
    c->ptr_target = 1;
  else {
    c->ptr_target = 0;
    for (int i = 0; i < c->n_popups; i++) {
      if (surf == c->popups[i].surf) {
        c->ptr_target = 2;
        break;
      }
    }
  }
  c->ptr_x = wl_fixed_to_int(sx);
  c->ptr_y = wl_fixed_to_int(sy);
  ev_push(c, 1, c->ptr_x, c->ptr_y, 0, 0, 0, c->ptr_target == 2 ? 1 : 0, 0, 0);
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
  ev_push(c, 1, c->ptr_x, c->ptr_y, 0, 0, 0, c->ptr_target == 2 ? 1 : 0, 0, 0);
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
  ev_push(c, type, c->ptr_x, c->ptr_y, 0, 0, (int)btn,
          c->ptr_target == 2 ? 1 : 0, 0, 0);
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
  ev_push(c, 2, c->ptr_x, c->ptr_y, 0, 0, btn, c->ptr_target == 2 ? 1 : 0, 0,
          0);
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
  for (int i = 0; i < c->n_popups; i++)
    c->popups[i].busy = 0;
}
static const struct wl_buffer_listener pop_buf_listener = {
    .release = pop_buf_release,
};

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

static int recreate_pop_buffer(lbar_ctx *c, lbar_popup_t *p) {
  if (p->buf) {
    wl_buffer_destroy(p->buf);
    p->buf = NULL;
  }
  if (p->pool) {
    wl_shm_pool_destroy(p->pool);
    p->pool = NULL;
  }
  if (p->pix) {
    munmap(p->pix, (size_t)p->map_w * p->map_h * 4);
    p->pix = NULL;
  }
  p->map_w = p->w;
  p->map_h = p->h;
  if (wl_make_buffer(c->wl_shm, p->w, p->h, &p->pool, &p->buf, &p->pix) < 0) {
    LOG_ERROR("recreate_pop_buffer failed (%dx%d)", p->w, p->h);
    return -1;
  }
  wl_buffer_add_listener(p->buf, &pop_buf_listener, c);
  p->busy = 0;
  LOG_INFO("popup buffer %dx%d", p->w, p->h);
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
  lbar_popup_t *p = NULL;
  for (int i = 0; i < c->n_popups; i++) {
    if (c->popups[i].layer == ls) {
      p = &c->popups[i];
      break;
    }
  }
  if (!p)
    return;
  int nw = (int)w, nh = (int)h;
  if (nw <= 0)
    nw = p->w;
  if (nh <= 0)
    nh = p->h;
  if (nw != p->w || nh != p->h) {
    LOG_INFO("popup configure -> %dx%d", nw, nh);
    p->w = nw;
    p->h = nh;
    recreate_pop_buffer(c, p);
  }
  p->configured = 1;
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

static int wl_create_bar(lbar_ctx *c, int h, int pos, int margin) {
  if (margin < 0)
    margin = 0;
  int bw = c->screen_w - 2 * margin;
  if (bw < 32)
    bw = 32;
  c->bar_pos = pos;
  c->bar_w = bw;
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
  zwlr_ls_set_margin(c->bar_layer, pos == 0 ? margin : 0, margin,
                     pos == 0 ? 0 : margin, margin);
  zwlr_ls_set_exclusive_zone(c->bar_layer, c->bar_h + margin);
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

static int wl_popup_init(lbar_ctx *c, lbar_popup_t *p, int w, int h, int r) {
  (void)r;
  p->w = w;
  p->h = h;
  p->r = r;
  p->x = 0;
  p->y = 0;

  p->surf = wl_compositor_create_surface(c->wl_comp);
  p->layer = zwlr_ls_get_layer_surface(c->wl_shell, p->surf, c->wl_out,
                                       ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
                                       "lbar-popup");
  zwlr_ls_set_size(p->layer, w, h);
  zwlr_ls_set_anchor(p->layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                   ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
  zwlr_ls_set_exclusive_zone(p->layer, 0);
  zwlr_ls_set_kb(p->layer,
                 ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
  zwlr_layer_surface_v1_add_listener(p->layer, &pop_layer_listener, c);

  p->map_w = w;
  p->map_h = h;
  if (wl_make_buffer(c->wl_shm, w, h, &p->pool, &p->buf, &p->pix) < 0)
    return -1;
  wl_buffer_add_listener(p->buf, &pop_buf_listener, c);

  wl_surface_commit(p->surf);
  wl_display_roundtrip(c->wl_dpy);
  LOG_INFO("popup created: %dx%d r=%d", w, h, r);
  return 0;
}

static void wl_popup_set_position(lbar_ctx *c, lbar_popup_t *p, int x, int y) {
  p->x = x;
  p->y = y;
  if (!p->layer)
    return;
  zwlr_ls_set_margin(p->layer, y, 0, 0, x);
  if (p->visible && p->surf) {
    wl_surface_commit(p->surf);
    wl_display_flush(c->wl_dpy);
  }
}

static void wl_popup_show(lbar_ctx *c, lbar_popup_t *p) {
  p->visible = 1;
  p->busy = 0;
  if (p->surf) {
    zwlr_ls_set_margin(p->layer, p->y, 0, 0, p->x);
    wl_surface_commit(p->surf);
  }
  wl_display_flush(c->wl_dpy);
}

static void wl_popup_hide(lbar_ctx *c, lbar_popup_t *p) {
  p->visible = 0;
  if (p->surf) {
    wl_surface_attach(p->surf, NULL, 0, 0);
    wl_surface_commit(p->surf);
  }
  p->busy = 0;
  wl_display_flush(c->wl_dpy);
}

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
  XSelectInput(c->x_dpy, c->x_root, KeyPressMask);
  LOG_INFO("x11 connected: %dx%d depth=%d", c->screen_w, c->screen_h,
           c->x_depth);
  return 0;
}

static void x_apply_round_mask(lbar_ctx *c, Window win, int w, int h, int r) {
  Pixmap mask = XCreatePixmap(c->x_dpy, win, w, h, 1);
  GC gc = XCreateGC(c->x_dpy, mask, 0, NULL);
  XSetForeground(c->x_dpy, gc, 0);
  XFillRectangle(c->x_dpy, mask, gc, 0, 0, w, h);
  XSetForeground(c->x_dpy, gc, 1);
  if (r <= 0 || r * 2 > w || r * 2 > h) {
    XFillRectangle(c->x_dpy, mask, gc, 0, 0, w, h);
  } else {
    XFillRectangle(c->x_dpy, mask, gc, r, 0, w - 2 * r, h);
    XFillRectangle(c->x_dpy, mask, gc, 0, r, r, h - 2 * r);
    XFillRectangle(c->x_dpy, mask, gc, w - r, r, r, h - 2 * r);
    int D = 64;
    XFillArc(c->x_dpy, mask, gc, 0, 0, 2 * r, 2 * r, 90 * D, 90 * D);
    XFillArc(c->x_dpy, mask, gc, w - 2 * r, 0, 2 * r, 2 * r, 0, 90 * D);
    XFillArc(c->x_dpy, mask, gc, 0, h - 2 * r, 2 * r, 2 * r, 180 * D, 90 * D);
    XFillArc(c->x_dpy, mask, gc, w - 2 * r, h - 2 * r, 2 * r, 2 * r, 270 * D,
             90 * D);
  }
  XFreeGC(c->x_dpy, gc);
  XShapeCombineMask(c->x_dpy, win, ShapeBounding, 0, 0, mask, ShapeSet);
  XFreePixmap(c->x_dpy, mask);
}

static int x_create_bar(lbar_ctx *c, int h, int pos, int margin) {
  if (margin < 0)
    margin = 0;
  int bw = c->screen_w - 2 * margin;
  if (bw < 32)
    bw = 32;
  int y = (pos == 0) ? margin : (c->screen_h - h - margin);
  XSetWindowAttributes a;
  memset(&a, 0, sizeof(a));
  a.override_redirect = 0;
  a.background_pixel = 0x1c1c1e;
  a.border_pixel = 0x1c1c1e;
  unsigned long mask = CWBackPixel | CWBorderPixel;

  c->x_bar_win =
      XCreateWindow(c->x_dpy, c->x_root, margin, y, bw, h, 0, c->x_depth,
                    InputOutput, CopyFromParent, mask, &a);

  long evmask = ExposureMask | ButtonPressMask | ButtonReleaseMask |
                PointerMotionMask | EnterWindowMask | LeaveWindowMask;
  XSelectInput(c->x_dpy, c->x_bar_win, evmask);
  c->x_bar_gc = XCreateGC(c->x_dpy, c->x_bar_win, 0, NULL);
  if (margin > 0)
    x_apply_round_mask(c, c->x_bar_win, bw, h, h / 2);

  XSizeHints hints;
  memset(&hints, 0, sizeof(hints));
  hints.flags = PPosition | PSize;
  hints.x = margin;
  hints.y = y;
  hints.width = bw;
  hints.height = h;
  XSetWMNormalHints(c->x_dpy, c->x_bar_win, &hints);

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

  Atom strut = XInternAtom(c->x_dpy, "_NET_WM_STRUT_PARTIAL", 0);
  unsigned long s[12] = {0};
  if (pos == 0) {
    s[2] = h + margin;
    s[8] = 0;
    s[9] = c->screen_w;
  } else {
    s[3] = h + margin;
    s[10] = 0;
    s[11] = c->screen_w;
  }
  XChangeProperty(c->x_dpy, c->x_bar_win, strut, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)s, 12);

  Atom strut4 = XInternAtom(c->x_dpy, "_NET_WM_STRUT", 0);
  unsigned long s4[4] = {0};
  if (pos == 0)
    s4[2] = h + margin;
  else
    s4[3] = h + margin;
  XChangeProperty(c->x_dpy, c->x_bar_win, strut4, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)s4, 4);

  XMapWindow(c->x_dpy, c->x_bar_win);
  XFlush(c->x_dpy);

  c->bar_w = bw;
  c->bar_h = h;
  LOG_INFO("bar created: %dx%d pos=%s margin=%d", c->bar_w, c->bar_h,
           pos == 0 ? "top" : "bottom", margin);
  return 0;
}

static int x_create_popup(lbar_ctx *c, lbar_popup_t *p, int w, int h, int r) {
  p->w = w;
  p->h = h;
  p->r = r;
  XSetWindowAttributes a;
  memset(&a, 0, sizeof(a));
  a.override_redirect = 1;
  a.background_pixmap = None;
  a.border_pixel = 0x1c1c1e;
  unsigned long mask = CWOverrideRedirect | CWBackPixel | CWBorderPixel;

  p->x_win = XCreateWindow(c->x_dpy, c->x_root, 0, 0, w, h, 0, c->x_depth,
                           InputOutput, CopyFromParent, mask, &a);
  long evmask =
      ExposureMask | ButtonPressMask | ButtonReleaseMask | PointerMotionMask;
  XSelectInput(c->x_dpy, p->x_win, evmask);
  p->x_gc = XCreateGC(c->x_dpy, p->x_win, 0, NULL);

  x_apply_round_mask(c, p->x_win, w, h, r);
  LOG_INFO("popup created: %dx%d r=%d", w, h, r);
  return 0;
}

static void x_popup_move(lbar_ctx *c, lbar_popup_t *p, int x, int y) {
  if (p->x_win)
    XMoveWindow(c->x_dpy, p->x_win, x, y);
}
static void x_popup_show(lbar_ctx *c, lbar_popup_t *p) {
  if (p->x_win) {
    XMapWindow(c->x_dpy, p->x_win);
    XRaiseWindow(c->x_dpy, p->x_win);
    XFlush(c->x_dpy);
    p->visible = 1;
    LOG_INFO("popup show");
  }
}

static void x_popup_hide(lbar_ctx *c, lbar_popup_t *p) {
  if (!p->visible)
    return;
  p->visible = 0;
  XUnmapWindow(c->x_dpy, p->x_win);
  XFlush(c->x_dpy);
  LOG_INFO("popup hide");
}

lbar_ctx *lbar_open(void) {
  lbar_ctx *c = calloc(1, sizeof(*c));
  if (!c)
    return NULL;

  if (getenv("WAYLAND_DISPLAY") && getenv("WAYLAND_DISPLAY")[0]) {
    c->is_wayland = 1;
    if (wl_open(c) == 0) {
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

int lbar_bar_create(lbar_ctx *c, int h, int pos, int margin) {
  return c->is_wayland ? wl_create_bar(c, h, pos, margin)
                       : x_create_bar(c, h, pos, margin);
}

static void x_flush_pixels(lbar_ctx *c, Window win, GC gc,
                           const uint32_t *pixels, int w, int h) {
  Visual *vis = DefaultVisual(c->x_dpy, c->x_screen);
  XImage *img =
      XCreateImage(c->x_dpy, vis, (unsigned int)c->x_depth, ZPixmap, 0, NULL,
                   w, h, 32, 0);
  if (!img)
    return;
  img->data = calloc(1, (size_t)img->bytes_per_line * (size_t)h);
  if (!img->data) {
    img->data = NULL;
    XDestroyImage(img);
    return;
  }
  if (img->bits_per_pixel == 32) {
    for (int y = 0; y < h; y++) {
      memcpy(img->data + (size_t)y * img->bytes_per_line,
             pixels + (size_t)y * w, (size_t)w * 4);
    }
  } else {
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++)
        XPutPixel(img, x, y, pixels[(size_t)y * w + x]);
  }
  XSetFunction(c->x_dpy, gc, GXcopy);
  XPutImage(c->x_dpy, win, gc, img, 0, 0, 0, 0, w, h);
  XFlush(c->x_dpy);
  XDestroyImage(img);
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
    x_flush_pixels(c, c->x_bar_win, c->x_bar_gc, pixels, c->bar_w, c->bar_h);
  }
}

static lbar_popup_t *popup_at(lbar_ctx *c, int id) {
  if (id < 0 || id >= LBAR_POPUP_MAX || id >= c->n_popups)
    return NULL;
  return &c->popups[id];
}

int lbar_popup_create(lbar_ctx *c, int w, int h, int r) {
  if (c->n_popups >= LBAR_POPUP_MAX)
    return -1;
  int id = c->n_popups++;
  lbar_popup_t *p = &c->popups[id];
  memset(p, 0, sizeof(*p));
  int rc = c->is_wayland ? wl_popup_init(c, p, w, h, r)
                         : x_create_popup(c, p, w, h, r);
  if (rc != 0) {
    c->n_popups--;
    return -1;
  }
  return id;
}

static void popup_destroy_slot(lbar_ctx *c, lbar_popup_t *p) {
  if (c->is_wayland) {
    if (p->layer)
      zwlr_ls_destroy(p->layer);
    if (p->surf)
      wl_surface_destroy(p->surf);
    if (p->buf)
      wl_buffer_destroy(p->buf);
    if (p->pool)
      wl_shm_pool_destroy(p->pool);
    if (p->pix)
      munmap(p->pix, (size_t)p->map_w * 4 * (size_t)p->map_h);
  } else {
    if (p->x_gc)
      XFreeGC(c->x_dpy, p->x_gc);
    if (p->x_win)
      XDestroyWindow(c->x_dpy, p->x_win);
    XFlush(c->x_dpy);
  }
}

int lbar_popup_resize(lbar_ctx *c, int id, int w, int h) {
  lbar_popup_t *p = popup_at(c, id);
  if (!p || w <= 0 || h <= 0)
    return -1;
  if (p->w == w && p->h == h)
    return 0;
  int r = p->r;
  popup_destroy_slot(c, p);
  memset(p, 0, sizeof(*p));
  int rc = c->is_wayland ? wl_popup_init(c, p, w, h, r)
                         : x_create_popup(c, p, w, h, r);
  return rc == 0 ? 0 : -1;
}

int lbar_kbd_grab(lbar_ctx *c, int id) {
  if (c->is_wayland)
    return -1;
  lbar_popup_t *p = popup_at(c, id);
  if (!p || !p->x_win)
    return -1;
  XGrabKeyboard(c->x_dpy, p->x_win, True, GrabModeAsync, GrabModeAsync,
                CurrentTime);
  XFlush(c->x_dpy);
  return 0;
}

int lbar_kbd_ungrab(lbar_ctx *c) {
  if (c->is_wayland)
    return -1;
  XUngrabKeyboard(c->x_dpy, CurrentTime);
  XFlush(c->x_dpy);
  return 0;
}

static Cursor s_ptr_cursor = None;

int lbar_ptr_grab(lbar_ctx *c, int id) {
  if (c->is_wayland)
    return -1;
  lbar_popup_t *p = popup_at(c, id);
  if (!p || !p->x_win)
    return -1;
  if (s_ptr_cursor == None)
    s_ptr_cursor = XCreateFontCursor(c->x_dpy, 34);
  XGrabPointer(c->x_dpy, p->x_win, True,
               ButtonPressMask | ButtonReleaseMask | PointerMotionMask,
               GrabModeAsync, GrabModeAsync, None, s_ptr_cursor, CurrentTime);
  XFlush(c->x_dpy);
  return 0;
}

void lbar_ptr_ungrab(lbar_ctx *c) {
  if (c->is_wayland)
    return;
  XUngrabPointer(c->x_dpy, CurrentTime);
  if (s_ptr_cursor != None) {
    XFreeCursor(c->x_dpy, s_ptr_cursor);
    s_ptr_cursor = None;
  }
  XFlush(c->x_dpy);
}

int lbar_x_get_region(lbar_ctx *c, int x, int y, int w, int h,
                      unsigned char *out, int out_max) {
  if (c->is_wayland || w <= 0 || h <= 0 || out_max < w * h * 3)
    return -1;
  memset(out, 0, (size_t)w * h * 3);
  int sx0 = x < 0 ? 0 : x;
  int sy0 = y < 0 ? 0 : y;
  int sx1 = x + w > c->screen_w ? c->screen_w : x + w;
  int sy1 = y + h > c->screen_h ? c->screen_h : y + h;
  if (sx1 <= sx0 || sy1 <= sy0)
    return -1;
  XImage *img = XGetImage(c->x_dpy, c->x_root, sx0, sy0,
                          (unsigned int)(sx1 - sx0), (unsigned int)(sy1 - sy0),
                          AllPlanes, ZPixmap);
  if (!img)
    return -1;
  for (int gy = sy0; gy < sy1; gy++) {
    for (int gx = sx0; gx < sx1; gx++) {
      unsigned long px = XGetPixel(img, gx - sx0, gy - sy0);
      int o = ((gy - y) * w + (gx - x)) * 3;
      out[o] = (unsigned char)((px >> 16) & 0xff);
      out[o + 1] = (unsigned char)((px >> 8) & 0xff);
      out[o + 2] = (unsigned char)(px & 0xff);
    }
  }
  XDestroyImage(img);
  return 0;
}

void lbar_popup_move(lbar_ctx *c, int id, int x, int y) {
  lbar_popup_t *p = popup_at(c, id);
  if (!p)
    return;
  if (c->is_wayland)
    wl_popup_set_position(c, p, x, y);
  else
    x_popup_move(c, p, x, y);
}

void lbar_popup_show(lbar_ctx *c, int id) {
  lbar_popup_t *p = popup_at(c, id);
  if (!p)
    return;
  if (c->is_wayland)
    wl_popup_show(c, p);
  else
    x_popup_show(c, p);
}

void lbar_popup_hide(lbar_ctx *c, int id) {
  lbar_popup_t *p = popup_at(c, id);
  if (!p)
    return;
  if (c->is_wayland)
    wl_popup_hide(c, p);
  else
    x_popup_hide(c, p);
}

int lbar_popup_visible(lbar_ctx *c) {
  if (c->is_wayland) {
    for (int i = 0; i < c->n_popups; i++)
      if (c->popups[i].visible)
        return 1;
    return 0;
  }
  for (int i = 0; i < c->n_popups; i++)
    if (c->popups[i].visible)
      return 1;
  return 0;
}

void lbar_popup_flush(lbar_ctx *c, int id, const uint32_t *pixels) {
  lbar_popup_t *p = popup_at(c, id);
  if (!p)
    return;
  if (c->is_wayland) {
    if (!p->visible)
      return;
    if (p->map_w != p->w || p->map_h != p->h) {
      if (recreate_pop_buffer(c, p) < 0)
        return;
    }
    if (p->busy || !p->buf || !p->surf)
      return;
    memcpy(p->pix, pixels, (size_t)p->w * p->h * 4);
    wl_surface_attach(p->surf, p->buf, 0, 0);
    wl_surface_damage(p->surf, 0, 0, p->w, p->h);
    wl_surface_commit(p->surf);
    wl_display_flush(c->wl_dpy);
    p->busy = 1;
  } else {
    x_flush_pixels(c, p->x_win, p->x_gc, pixels, p->w, p->h);
  }
}

int lbar_key_code(lbar_ctx *c, const char *name) {
  if (c->is_wayland || !name || !name[0])
    return 0;
  KeySym sym = XStringToKeysym(name);
  if (!sym) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%c%s", name[0] >= 'a' && name[0] <= 'z'
                                           ? (char)(name[0] - 32)
                                           : name[0],
             name + 1);
    sym = XStringToKeysym(buf);
  }
  if (!sym)
    sym = XStringToKeysym(name);
  if (!sym)
    return 0;
  return (int)XKeysymToKeycode(c->x_dpy, sym);
}

int lbar_key_grab(lbar_ctx *c, int code, int mask) {
  if (c->is_wayland || code <= 0)
    return -1;
  static const int extra[4] = {0, LockMask, Mod2Mask, LockMask | Mod2Mask};
  for (int i = 0; i < 4; i++)
    XGrabKey(c->x_dpy, (int)code, (unsigned int)(mask | extra[i]), c->x_root, 0,
             GrabModeAsync, GrabModeAsync);
  XFlush(c->x_dpy);
  return 0;
}

int lbar_key_ungrab_all(lbar_ctx *c) {
  if (c->is_wayland)
    return -1;
  XUngrabKey(c->x_dpy, AnyKey, AnyModifier, c->x_root);
  XFlush(c->x_dpy);
  return 0;
}

long lbar_key_lookup(lbar_ctx *c, int keycode, int state, char *out,
                     int out_max) {
  if (c->is_wayland || !out || out_max <= 0)
    return 0;
  out[0] = 0;
  XKeyEvent ev;
  memset(&ev, 0, sizeof(ev));
  ev.display = c->x_dpy;
  ev.type = KeyPress;
  ev.keycode = (KeyCode)keycode;
  ev.state = (unsigned int)state;
  ev.same_screen = True;
  KeySym sym = 0;
  int n = XLookupString(&ev, out, out_max - 1, &sym, NULL);
  if (n < 0)
    n = 0;
  out[n] = 0;
  return (long)sym;
}

static void drain_x11_events(lbar_ctx *c) {
  while (XPending(c->x_dpy) > 0) {
    XEvent e;
    XNextEvent(c->x_dpy, &e);
    if (e.type == Expose) {
      int ptgt = 0;
      for (int i = 0; i < c->n_popups; i++) {
        if (e.xexpose.window == c->popups[i].x_win) {
          ptgt = 1;
          break;
        }
      }
      if (e.xexpose.window == c->x_bar_win)
        ev_push(c, 4, 0, 0, 0, 0, 0, 0, 0, 0);
      else if (ptgt)
        ev_push(c, 4, 0, 0, 0, 0, 0, 1, 0, 0);
    } else if (e.type == MotionNotify) {
      int tgt = 0;
      for (int i = 0; i < c->n_popups; i++) {
        if (e.xmotion.window == c->popups[i].x_win) {
          tgt = 1;
          break;
        }
      }
      ev_push(c, 1, e.xmotion.x, e.xmotion.y, e.xmotion.x_root,
              e.xmotion.y_root, 0, tgt, 0, 0);
    } else if (e.type == ButtonPress) {
      int tgt = 0;
      for (int i = 0; i < c->n_popups; i++) {
        if (e.xbutton.window == c->popups[i].x_win) {
          tgt = 1;
          break;
        }
      }
      ev_push(c, 2, e.xbutton.x, e.xbutton.y, e.xbutton.x_root,
              e.xbutton.y_root, e.xbutton.button, tgt, 0, 0);
    } else if (e.type == ButtonRelease) {
      int tgt = 0;
      for (int i = 0; i < c->n_popups; i++) {
        if (e.xbutton.window == c->popups[i].x_win) {
          tgt = 1;
          break;
        }
      }
      ev_push(c, 3, e.xbutton.x, e.xbutton.y, e.xbutton.x_root,
              e.xbutton.y_root, e.xbutton.button, tgt, 0, 0);
    } else if (e.type == KeyPress) {
      int ktgt = 2;
      for (int i = 0; i < c->n_popups; i++) {
        if (e.xkey.window == c->popups[i].x_win) {
          ktgt = 1;
          break;
        }
      }
      ev_push(c, 5, 0, 0, e.xkey.x_root, e.xkey.y_root, 0, ktgt,
              (int)e.xkey.keycode, (int)e.xkey.state);
    }
  }
}

int lbar_poll(lbar_ctx *c, int timeout_ms) {
  if (c->is_wayland) {
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
    for (int i = 0; i < c->n_popups; i++) {
      lbar_popup_t *p = &c->popups[i];
      if (p->surf)
        wl_surface_destroy(p->surf);
      if (p->layer)
        zwlr_ls_destroy(p->layer);
      if (p->buf)
        wl_buffer_destroy(p->buf);
      if (p->pool)
        wl_shm_pool_destroy(p->pool);
      if (p->pix)
        munmap(p->pix, (size_t)p->map_w * p->map_h * 4);
    }

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
    for (int i = 0; i < c->n_popups; i++) {
      lbar_popup_t *p = &c->popups[i];
      if (p->x_win)
        XDestroyWindow(c->x_dpy, p->x_win);
      if (p->x_gc)
        XFreeGC(c->x_dpy, p->x_gc);
    }
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
