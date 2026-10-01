#include <math.h>
#include "hardware_rtu.h"
#include "rtu_stats.h"

aabb_result_t aabb_intersect (aabb_request_t aabb_request) {
    rtu_aabb_intersection_count ++;
    //should eventually return t_entry and t_exit so
    //BVH traversal can visit closer child first
    //could do in loop. separated for clarity

    aabb_result_t result = {.context_id = aabb_request.context_id,
        .hit = 0, .t_near = 0.0f, .t_far = 0.0f
    };

    //calculate X tmin and tmax
    float inv_direction_x = aabb_request.ray.inv_direction.x;
    float t0_x = (aabb_request.aabb.corner_a.x - aabb_request.ray.origin.x) * inv_direction_x;
    float t1_x = (aabb_request.aabb.corner_b.x - aabb_request.ray.origin.x) * inv_direction_x;
    float tmin_x = fminf(t0_x, t1_x);
    float tmax_x = fmaxf(t0_x, t1_x);

    //calculate Y tmin and tmax
    float inv_direction_y = aabb_request.ray.inv_direction.y;
    float t0_y = (aabb_request.aabb.corner_a.y - aabb_request.ray.origin.y) * inv_direction_y;
    float t1_y = (aabb_request.aabb.corner_b.y - aabb_request.ray.origin.y) * inv_direction_y;
    float tmin_y = fminf(t0_y, t1_y);
    float tmax_y = fmaxf(t0_y, t1_y);

    //calculate Z tmin and tmax
    float inv_direction_z = aabb_request.ray.inv_direction.z;
    float t0_z = (aabb_request.aabb.corner_a.z - aabb_request.ray.origin.z) * inv_direction_z;
    float t1_z = (aabb_request.aabb.corner_b.z - aabb_request.ray.origin.z) * inv_direction_z;
    float tmin_z = fminf(t0_z, t1_z);
    float tmax_z = fmaxf(t0_z, t1_z);

    //find overall tmin and tmax
    float t_near = fmaxf(fmaxf(tmin_x, tmin_y), tmin_z);
    float t_far = fminf(fminf(tmax_x, tmax_y), tmax_z);

    //collision check (all must be within range and collide)
    if (t_near <= t_far && t_far >= aabb_request.ray.t_min && t_near <= aabb_request.ray.t_max) {
        result.hit = 1;
    }
    return result;
}