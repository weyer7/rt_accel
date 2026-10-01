#include <math.h>
#include <float.h>
#include <stdint.h>
#include "hardware_rtu.h"

//O(n) brute-force ray-object intersection for comparison
traversal_result_t traverse_bruteforce(traversal_request_t traversal_request)
{
    ray_request_t ray = traversal_request.ray;

    ray_geometry_t ray_geom = {
        .origin = ray.origin,
        .direction = ray.direction,
        .inv_direction = {
            1.0f / ray.direction.x,
            1.0f / ray.direction.y,
            1.0f / ray.direction.z
        },
        .t_min = ray.t_min,
        .t_max = ray.t_max
    };

    float closest_t = ray.t_max;
    uint32_t closest_primitive = 0;
    float2_t closest_bary = {0.0f, 0.0f};
    uint32_t closest_facing_front = 0;
    uint32_t found_hit = 0;

    uint32_t tri_count = rtu_scene_tri_count();

    for (uint32_t i = 0; i < tri_count; i++) {
        uint32_t tri_addr = RTU_TRI_BASE + i * sizeof(tri_t);

        tri_t *triangle = rtu_tri_from_addr(tri_addr);
        if (!triangle) continue;

        //limit the triangle intersection to the closest hit found so far
        ray_geom.t_max = closest_t;

        tri_result_t tri_res = tri_intersect(
            (tri_request_t){.context_id = 0, .ray = ray_geom, .triangle = *triangle}
        );

        if (tri_res.hit && tri_res.t < closest_t) {
            closest_t = tri_res.t;
            closest_primitive = tri_res.primitive_id;
            closest_bary = tri_res.bary_pos;
            closest_facing_front = tri_res.facing_front;
            found_hit = 1;
        }
    }

    if (!found_hit) {
        return (traversal_result_t){
            .primitive_id = 0,
            .distance = INFINITY,
            .bary_pos = {0.0f, 0.0f}
        };
    }

    return (traversal_result_t){
        .primitive_id = closest_primitive,
        .distance = closest_facing_front ? closest_t : -closest_t,
        .bary_pos = closest_bary
    };
}