#include "pmsis.h"

typedef struct Monitor {
    uint32_t empty;
    uint32_t full;
} Monitor;


int monitor_init(Monitor * const monitor, int buffer_size) {
    monitor->empty = pi_cl_sem_alloc();
    if (monitor->empty == 0) {
        return -1;
    }

    monitor->full = pi_cl_sem_alloc();
    if (monitor->full == 0) {
        pi_cl_sem_free(monitor->empty);
        return -2;
    }

    pi_cl_sem_set(monitor->full, 0);
    pi_cl_sem_set(monitor->empty, buffer_size);

    return 0;
}

void monitor_term(Monitor * const monitor) {
    pi_cl_sem_free(monitor->empty);
    pi_cl_sem_free(monitor->full);
}

void monitor_produce_begin(Monitor * const monitor) {
    pi_cl_sem_dec(monitor->empty);
}

void monitor_produce_end(Monitor * const monitor) {
    pi_cl_sem_inc(monitor->full, 1);
}

void monitor_consume_begin(Monitor * const monitor) {
    pi_cl_sem_dec(monitor->full);
}

void monitor_consume_end(Monitor * const monitor) {
    pi_cl_sem_inc(monitor->empty, 1);
}

