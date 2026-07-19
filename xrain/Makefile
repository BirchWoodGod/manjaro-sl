include config.mk

all: xrain

config.h:
	cp config.def.h $@

xrain: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xrain

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xrain ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xrain

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xrain

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xrain -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
