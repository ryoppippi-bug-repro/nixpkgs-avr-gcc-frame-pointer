#include <stdint.h>

uint32_t now(void);

uint32_t mix(uint32_t x, uint32_t y) {
    uint32_t t = now();
    return (x * t) ^ (y + now()) ^ t;
}
