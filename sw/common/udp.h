/* udp.h -- minimal UDP sender. */
#ifndef SCAM_UDP_H
#define SCAM_UDP_H

#include <stddef.h>
#include <stdint.h>
#include <netinet/in.h>

typedef struct {
    int fd;
    struct sockaddr_in dest;
} udp_socket_t;

int  udp_open(udp_socket_t *s, const char *dest_ip, uint16_t port);
int  udp_send(udp_socket_t *s, const void *buf, size_t len);
void udp_close(udp_socket_t *s);

#endif
