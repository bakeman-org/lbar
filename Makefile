CC      ?= cc
PKGS    := freetype2 harfbuzz x11 xext wayland-client
CFLAGS  := -O2 -fPIC -Wall -Wextra -Wno-unused-parameter \
           $(shell pkg-config --cflags $(PKGS))
LDFLAGS := -shared
LIBS    := $(shell pkg-config --libs $(PKGS))

all: lbar.so 

run:
	luajit lbar.lua config.lua

lbar.so: src/text.c src/backends.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LIBS)

clean:
	rm -f lbar.so

.PHONY: all clean

__prompt:
	./collect-as-prompt *.lua src/ core/ plugins/ > /tmp/1.txt 