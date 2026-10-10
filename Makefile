MAKEFLAGS += -B
CC      ?= cc
PKGS    := freetype2 harfbuzz x11 xext wayland-client xkbcommon
CFLAGS  := -O2 -fPIC -Wall -Wextra -Wno-unused-parameter \
           $(shell pkg-config --cflags $(PKGS))
LDFLAGS := -shared
LIBS    := $(shell pkg-config --libs $(PKGS))

all: lbar.so lbar_audio.so lbar-cli

run: lbar.so lbar_audio.so lbar-cli
	luajit lbar.lua config.lua

lbar-cli: tools/lbar-cli.c
	$(CC) -O2 -Wall -o $@ $<

lbar.so: src/text.c src/backends.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LIBS)

SDL_CFLAGS := $(shell pkg-config --cflags sdl2 SDL2_mixer)
SDL_LIBS   := $(shell pkg-config --libs sdl2 SDL2_mixer)

lbar_audio.so: src/audio.c
	$(CC) $(CFLAGS) $(SDL_CFLAGS) $(LDFLAGS) -o $@ $< $(SDL_LIBS)

clean:
	rm -f lbar.so lbar_audio.so lbar-cli

.PHONY: all clean


# private targets for development
__prompt:
	./collect-as-prompt *.lua src/ core/ plugins/ > /tmp/1.txt 


# luastatic ref link: https://github.com/ers35/luastatic
__native:
	luastatic lbar.lua config.lua core/*.lua plugins/*.lua core/wm/*.lua   -I /usr/include/luajit-2.1/   /usr/lib/x86_64-linux-gnu/libluajit-5.1.a lbar.so lbar_audio.so

__tmp_check_run: lbar.so lbar_audio.so __native lbar-cli
	-cp -rv lbar /tmp/
	-cp -rv config.lua /tmp/
	-cp -rv lbar-cli /tmp/
	-cp -rv *.so /tmp/
	-cp -rv core /tmp/
	-cp -rv plugins /tmp/
	-/tmp/lbar config.lua config.lua

# TODO: can this be dispatched on debian based distro?
__package:
	-cp -rv lbar /tmp/
	-cp -rv config.lua /tmp/
	-cp -rv lbar-cli /tmp/
	-cp -rv *.so /tmp/
	-cp -rv core /tmp/
	-cp -rv plugins /tmp/
	./bake.py -e /tmp/lbar -r /tmp/core -r /tmp/plugins -r /tmp/lbar-cli -r /tmp/config.lua -r /tmp/lbar.so -r /tmp/lbar_audio.so -o lbar.bake