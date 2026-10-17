#include "udp.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int udp_open(udp_socket_t *s, const char *dest_ip, uint16_t port)
{
    memset(s, 0, sizeof(*s));
    s->fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (s->fd < 0) {
        perror("socket");
        return -1;
    }
    s->dest.sin_family = AF_INET;
    s->dest.sin_port   = htons(port);
    if (inet_pton(AF_INET, dest_ip, &s->dest.sin_addr) != 1) {
        fprintf(stderr, "bad destination IP: %s\n", dest_ip);
        close(s->fd);
        return -1;
    }
    return 0;
}

int udp_send(udp_socket_t *s, const void *buf, size_t len)
{
    ssize_t n = sendto(s->fd, buf, len, 0,
                       (struct sockaddr *)&s->dest, sizeof(s->dest));
    if (n < 0) {
        perror("sendto");
        return -1;
    }
    return (int)n;
}

void udp_close(udp_socket_t *s)
{
    if (s->fd >= 0) close(s->fd);
    s->fd = -1;
}
