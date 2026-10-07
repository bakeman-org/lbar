MAKEFLAGS += -B
CC      ?= cc
PKGS    := freetype2 harfbuzz x11 xext wayland-client
CFLAGS  := -O2 -fPIC -Wall -Wextra -Wno-unused-parameter \
           $(shell pkg-config --cflags $(PKGS))
LDFLAGS := -shared
LIBS    := $(shell pkg-config --libs $(PKGS))

all: lbar.so lbar_audio.so

run: lbar.so lbar_audio.so
	luajit lbar.lua config.lua

lbar.so: src/text.c src/backends.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LIBS)

SDL_CFLAGS := $(shell pkg-config --cflags sdl2 SDL2_mixer)
SDL_LIBS   := $(shell pkg-config --libs sdl2 SDL2_mixer)

lbar_audio.so: src/audio.c
	$(CC) $(CFLAGS) $(SDL_CFLAGS) $(LDFLAGS) -o $@ $< $(SDL_LIBS)

clean:
	rm -f lbar.so lbar_audio.so

.PHONY: all clean

__prompt:
	./collect-as-prompt *.lua src/ core/ plugins/ > /tmp/1.txt 