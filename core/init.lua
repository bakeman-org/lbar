-- core/init.lua
return function(SCRIPT_DIR)
	local ffi = require("ffi")

	ffi.cdef([[
    typedef struct lbar_ctx lbar_ctx;

    typedef struct {
      int type;
      int x, y;
      int root_x, root_y;
      int button;
      int target;
    } lbar_event_t;

    lbar_ctx   *lbar_open(void);
    void        lbar_close(lbar_ctx *c);
    const char *lbar_backend(lbar_ctx *c);
    int  lbar_screen_w(lbar_ctx *c);
    int  lbar_screen_h(lbar_ctx *c);
    int  lbar_bar_width(lbar_ctx *c);
    int  lbar_bar_height(lbar_ctx *c);
    int  lbar_bar_create(lbar_ctx *c, int h, int pos);
    void lbar_bar_flush(lbar_ctx *c, const uint32_t *pixels);

    int  lbar_popup_create(lbar_ctx *c, int w, int h, int r);
    void lbar_popup_move(lbar_ctx *c, int x, int y);
    void lbar_popup_show(lbar_ctx *c);
    void lbar_popup_hide(lbar_ctx *c);
    int  lbar_popup_visible(lbar_ctx *c);
    void lbar_popup_flush(lbar_ctx *c, const uint32_t *pixels);

    int  lbar_poll(lbar_ctx *c, int timeout_ms);
    int  lbar_next_event(lbar_ctx *c, lbar_event_t *out);

    int   xft_init(void);
    void *xft_load(const char *primary_path, int size, const char *fallback_paths);
    void  xft_done(void *ctx);
    int   xft_primary_line_height(void *ctx);
    void  xft_text_extent(void *ctx, const char *text, int *w_out, int *h_out);
    void  xft_draw_rgba(void *ctx, uint32_t *buf, int bw, int bh, int x, int y,
                        const char *text, unsigned long fg);
    void  surf_fill(uint32_t *buf, int W, int H, int x, int y, int w, int h,
                    unsigned int color);
    void  surf_rrect_aa(uint32_t *buf, int W, int H, int x, int y, int w, int h,
                        int r, unsigned int color);

    typedef struct { long tv_sec; long tv_nsec; } lbar_ts;
    int clock_gettime(int clk, lbar_ts *tp);
  ]])

	local libc = ffi.load("c")
	local L = ffi.load(SCRIPT_DIR .. "/lbar.so")
	return { ffi = ffi, libc = libc, L = L }
end
