all: libluaevent_shim.so

libluaevent_shim.so: shim.c
	gcc -fPIC -lunbound -shared -o libluaevent_shim.so shim.c
