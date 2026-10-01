#ifndef RTU_STATS_H
#define RTU_STATS_H

#include <stdint.h>
extern uint64_t rtu_tri_intersection_count;
extern uint64_t rtu_aabb_intersection_count;
void rtu_stats_reset(void);

#endif