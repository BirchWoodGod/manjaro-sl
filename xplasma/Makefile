include config.mk

all: xplasma

config.h:
	cp config.def.h $@

xplasma: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xplasma

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xplasma ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xplasma

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xplasma

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xplasma -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
