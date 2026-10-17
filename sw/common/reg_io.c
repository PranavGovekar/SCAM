#include "reg_io.h"

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

void *map_phys(uint32_t base, size_t size)
{
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return MAP_FAILED;
    }
    void *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    if (p == MAP_FAILED) {
        fprintf(stderr, "mmap /dev/mem at 0x%08X: ", (unsigned)base);
        perror(NULL);
    }
    close(fd);
    return p;
}
