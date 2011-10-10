all: libluaevent_shim.so

libluaevent_shim.so: shim.c
	gcc -fPIC -I/usr/local/include -L/usr/local/lib -lunbound -shared -o ../libluaevent_shim.so shim.c
