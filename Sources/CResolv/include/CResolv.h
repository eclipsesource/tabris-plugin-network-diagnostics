#ifndef CRESOLV_H
#define CRESOLV_H

#include <sys/socket.h>

/// Copies the system-configured DNS server addresses obtained through
/// res_9_ninit/res_9_getservers into `out`. Returns the number of entries
/// written (at most `capacity`), or -1 when the resolver state could not be
/// initialised.
int cresolv_copy_dns_servers(struct sockaddr_storage *out, int capacity);

#endif
