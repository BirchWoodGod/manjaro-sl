include config.mk

all: xmatrix

config.h:
	cp config.def.h $@

xmatrix: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xmatrix

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xmatrix ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xmatrix

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xmatrix

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xmatrix -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
