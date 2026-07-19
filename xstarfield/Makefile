include config.mk

all: xstarfield

config.h:
	cp config.def.h $@

xstarfield: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xstarfield

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xstarfield ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xstarfield

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xstarfield

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xstarfield -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
