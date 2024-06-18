// clang -O3 -dynamiclib helper_macos_arm64.c -o helper_macos_arm64.dylib

#include <stddef.h>
#include <string.h>
#include <pthread.h>

void jit_memcpy(void *dst, const void *src, size_t n)
{
    pthread_jit_write_protect_np(0);
    memcpy(dst, src, n);
    pthread_jit_write_protect_np(1);
}
