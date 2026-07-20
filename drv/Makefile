PREFIX = /usr/local
OBJS = src/drv_main.o \
       src/drv_match.o \
       src/drv_ref.o \
       src/drv_render.o \
       src/intset.o \
       src/strutil.o \
       data/drv_data.o
CFLAGS += -Wall -Isrc/
LDLIBS += -lreadline

drv: $(OBJS)
	$(CC) -o $@ $(LDFLAGS) $(OBJS) $(LDLIBS)

src/drv_main.o: src/drv_main.c src/drv_config.h src/drv_data.h src/drv_match.h src/drv_ref.h src/drv_render.h src/strutil.h

src/drv_match.o: src/drv_match.h src/drv_match.c src/drv_config.h src/drv_data.h src/drv_ref.h

src/drv_ref.o: src/drv_ref.h src/drv_ref.c src/intset.h src/drv_data.h

src/drv_render.o: src/drv_render.h src/drv_render.c src/drv_config.h src/drv_data.h src/drv_match.h src/drv_ref.h

src/insetset.o: src/intset.h src/insetset.c

src/strutil.o: src/strutil.h src/strutil.c

data/drv_data.o: src/drv_data.h data/drv_data.c

data/drv_data.c: data/drv.tsv data/generate.awk src/drv_data.h
	awk -f data/generate.awk $< > $@

.PHONY: clean install uninstall
clean:
	rm -rf $(OBJS) data/drv_data.c drv

install: drv
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	cp -f drv $(DESTDIR)$(PREFIX)/bin
	chmod 755 $(DESTDIR)$(PREFIX)/bin/drv

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/drv
