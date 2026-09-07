#include "CResolv.h"

#include <resolv.h>
#include <string.h>

int cresolv_copy_dns_servers(struct sockaddr_storage *out, int capacity) {
    struct __res_state state;
    memset(&state, 0, sizeof(state));
    if (res_9_ninit(&state) != 0) {
        return -1;
    }

    union res_sockaddr_union servers[MAXNS];
    memset(servers, 0, sizeof(servers));
    int count = res_9_getservers(&state, servers, MAXNS);
    if (count > capacity) {
        count = capacity;
    }
    for (int index = 0; index < count; index++) {
        memset(&out[index], 0, sizeof(struct sockaddr_storage));
        size_t length = sizeof(servers[index]) < sizeof(struct sockaddr_storage)
            ? sizeof(servers[index])
            : sizeof(struct sockaddr_storage);
        memcpy(&out[index], &servers[index], length);
    }
    res_9_ndestroy(&state);
    return count;
}
