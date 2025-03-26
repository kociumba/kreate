#include <windows.h>
#include <stdio.h>

extern void hello_from_c() {
    printf("Hello from C! Tick count: %lu\n", GetTickCount());
}