#include <stdint.h>
#include <stdio.h>

uint8_t _MIST_PLUGIN_0_0_MAIN(
    size_t    arg_count,
    uint8_t** arg_pointers,
    size_t*   arg_pointer_sizes
) {
    printf("Hello from C!");

    return 0;
}
