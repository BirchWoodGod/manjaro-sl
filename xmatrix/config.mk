VERSION = 0.1
PREFIX = /usr/local
X11INC = /usr/include/X11
X11LIB = /usr/lib/X11
INCS = -I${X11INC}
LIBS = -L${X11LIB} -lX11
CPPFLAGS = -DVERSION=\"${VERSION}\" -D_POSIX_C_SOURCE=200809L
CFLAGS = -std=c99 -pedantic -Wall -Wextra -Os ${INCS} ${CPPFLAGS}
CC = cc
