include config.mk

all: doomfire

config.h:
	cp config.def.h $@

doomfire: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f doomfire

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f doomfire ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/doomfire

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/doomfire

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./doomfire -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
