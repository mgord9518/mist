CC=zig cc
CFLAGS=-Wall -fPIC -Werror -Wextra
LDFLAGS=-shared

name=plugin_c

$(name).so: main.c
	$(CC) -o $(name).so main.c $(CFLAGS) $(LDFLAGS)
