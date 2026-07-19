include config.mk

all: xblackhole

config.h:
	cp config.def.h $@

xblackhole: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xblackhole

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xblackhole ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xblackhole

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xblackhole

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xblackhole -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
