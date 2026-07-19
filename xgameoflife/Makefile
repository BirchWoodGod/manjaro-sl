include config.mk

all: xgameoflife

config.h:
	cp config.def.h $@

xgameoflife: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xgameoflife

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xgameoflife ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xgameoflife

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xgameoflife

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xgameoflife -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
