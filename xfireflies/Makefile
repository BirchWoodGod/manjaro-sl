include config.mk

all: xfireflies

config.h:
	cp config.def.h $@

xfireflies: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xfireflies

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xfireflies ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xfireflies

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xfireflies

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xfireflies -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
