include config.mk

all: xcolormix

config.h:
	cp config.def.h $@

xcolormix: main.c config.h
	${CC} ${CFLAGS} -o $@ main.c ${LIBS}

clean:
	rm -f xcolormix

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f xcolormix ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/xcolormix

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/xcolormix

test: all
	@command -v Xvfb >/dev/null || { echo "Xvfb not installed; skipping"; exit 0; }; \
	Xvfb :99 -screen 0 640x480x24 & XVFB=$$!; sleep 1; \
	DISPLAY=:99 ./xcolormix -n 10; RC=$$?; kill $$XVFB; exit $$RC

.PHONY: all clean install uninstall test
