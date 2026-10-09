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
      int keycode;
      int keystate;
      int a, b;
      char text[512];
    } lbar_event_t;

    lbar_ctx   *lbar_open(void);
    void        lbar_close(lbar_ctx *c);
    const char *lbar_backend(lbar_ctx *c);
    int  lbar_screen_w(lbar_ctx *c);
    int  lbar_screen_h(lbar_ctx *c);
    int  lbar_bar_width(lbar_ctx *c);
    int  lbar_bar_height(lbar_ctx *c);
    int  lbar_bar_create(lbar_ctx *c, int h, int pos, int margin);
    void lbar_bar_flush(lbar_ctx *c, const uint32_t *pixels);

    int  lbar_popup_create(lbar_ctx *c, int w, int h, int r);
    int  lbar_popup_resize(lbar_ctx *c, int id, int w, int h);
    void lbar_popup_move(lbar_ctx *c, int id, int x, int y);
    void lbar_popup_show(lbar_ctx *c, int id);
    void lbar_popup_hide(lbar_ctx *c, int id);
    int  lbar_popup_visible(lbar_ctx *c);
    void lbar_popup_size(lbar_ctx *c, int id, int *out_w, int *out_h);
    void lbar_popup_flush(lbar_ctx *c, int id, const uint32_t *pixels, int sw,
                          int sh, int *out_w, int *out_h);

    int lbar_key_code(lbar_ctx *c, const char *name);
    int lbar_key_grab(lbar_ctx *c, int code, int mask);
    int lbar_key_ungrab_all(lbar_ctx *c);
    int lbar_kbd_grab(lbar_ctx *c, int id);
    int lbar_kbd_ungrab(lbar_ctx *c);
    int  lbar_ptr_grab(lbar_ctx *c, int id);
    void lbar_ptr_ungrab(lbar_ctx *c);
    int  lbar_x_get_region(lbar_ctx *c, int x, int y, int w, int h,
                           unsigned char *out, int out_max);
    int64_t lbar_key_lookup(lbar_ctx *c, int keycode, int state, char *out, int out_max);
    int lbar_ipc_take(lbar_ctx *c, char *out, int out_max);

    int lbar_ti_enable(lbar_ctx *c, int x, int y, int w, int h);
    int lbar_ti_disable(lbar_ctx *c);
    int lbar_ti_set_cursor(lbar_ctx *c, int x, int y, int w, int h);

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

    int audio_init(void);
    void audio_shutdown(void);
    int audio_play(const char *path);
    void audio_toggle_pause(void);
    void audio_stop(void);
    int audio_is_playing(void);
    int audio_is_paused(void);
    void audio_set_volume(int v0_100);
    double audio_get_position(void);
    double audio_get_duration(void);
    int audio_scan_dir(const char *dir);
    const char *audio_scan_get(int idx);
    void audio_seek(double sec);
    double audio_probe_duration(const char *path);
    int audio_play_sfx(const char *path, int vol_0_100);
    int audio_finished(void);
  ]])

	local libc = ffi.load("c")
	local L = ffi.load(SCRIPT_DIR .. "/lbar.so")
	local has_aud, AUD = pcall(function()
		return ffi.load(SCRIPT_DIR .. "/lbar_audio.so")
	end)
	if not has_aud then
		AUD = nil
	end
	return { ffi = ffi, libc = libc, L = L, AUD = AUD }
end
