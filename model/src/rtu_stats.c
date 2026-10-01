#include "rtu_stats.h"

//global variables for statistics (non-ideal, but easy)
uint64_t rtu_tri_intersection_count = 0;
uint64_t rtu_aabb_intersection_count = 0;

//resets rtu statistics
void rtu_stats_reset(void) {
    rtu_tri_intersection_count = 0;
    rtu_aabb_intersection_count = 0;
}