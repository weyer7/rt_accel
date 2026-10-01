#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdlib.h>
#include "hardware_rtu.h"

#define BVH_STACK_SIZE 64

typedef struct {
    uint32_t node_addr;
    float t_near;
} bvh_stack_entry_t;

traversal_result_t traverse_bvh(traversal_request_t traversal_request) {
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

    bvh_stack_entry_t stack[BVH_STACK_SIZE];
    int stack_ptr = 0;

    stack[stack_ptr++] = (bvh_stack_entry_t){
        .node_addr = ray.bvh_root,
        .t_near = ray.t_min
    };

    float closest_t = ray.t_max;
    uint32_t closest_primitive = 0;
    float2_t closest_bary = {0.0f, 0.0f};
    uint32_t closest_facing_front = 0;
    uint32_t found_hit = 0;

    while (stack_ptr > 0) {
        bvh_stack_entry_t entry = stack[--stack_ptr];

        uint32_t node_addr = entry.node_addr;
        bvh_node_t *node = rtu_bvh_node_from_addr(node_addr);

        if (!node) continue;
        if (entry.t_near > closest_t) continue;

        //the node's AABB was already tested before it was pushed
        //do not test it again here
        ray_geom.t_max = closest_t;

        if (node->tri_count > 1) {
            uint32_t left_addr = node->left_first;
            uint32_t right_addr = left_addr + sizeof(bvh_node_t);

            bvh_node_t *left_node =
                rtu_bvh_node_from_addr(left_addr);
            bvh_node_t *right_node =
                rtu_bvh_node_from_addr(right_addr);

            if (!left_node || !right_node)
                continue;

            aabb_result_t left_res = aabb_intersect(
                (aabb_request_t){
                    .context_id = 0,
                    .ray = ray_geom,
                    .aabb = left_node->aabb
                }
            );

            aabb_result_t right_res = aabb_intersect(
                (aabb_request_t){
                    .context_id = 0,
                    .ray = ray_geom,
                    .aabb = right_node->aabb
                }
            );

            //push far first and near second so that near is processed first
            if (left_res.hit && right_res.hit) {
                if (stack_ptr + 2 > BVH_STACK_SIZE)
                    continue;

                if (left_res.t_near < right_res.t_near) {
                    stack[stack_ptr++] = (bvh_stack_entry_t){
                        .node_addr = right_addr,
                        .t_near = right_res.t_near
                    };

                    stack[stack_ptr++] = (bvh_stack_entry_t){
                        .node_addr = left_addr,
                        .t_near = left_res.t_near
                    };
                } else {
                    stack[stack_ptr++] = (bvh_stack_entry_t){
                        .node_addr = left_addr,
                        .t_near = left_res.t_near
                    };

                    stack[stack_ptr++] = (bvh_stack_entry_t){
                        .node_addr = right_addr,
                        .t_near = right_res.t_near
                    };
                }
            }
            else if (left_res.hit) {
                if (stack_ptr >= BVH_STACK_SIZE)
                    continue;

                stack[stack_ptr++] = (bvh_stack_entry_t){
                    .node_addr = left_addr,
                    .t_near = left_res.t_near
                };
            }
            else if (right_res.hit) {
                if (stack_ptr >= BVH_STACK_SIZE)
                    continue;

                stack[stack_ptr++] = (bvh_stack_entry_t){
                    .node_addr = right_addr,
                    .t_near = right_res.t_near
                };
            }

            continue;
        }

        //leaf node
        for (uint32_t i = 0; i < node->tri_count; i++) {
            uint32_t tri_addr =
                node->left_first + i * sizeof(tri_t);

            tri_t *triangle = rtu_tri_from_addr(tri_addr);

            if (!triangle)
                continue;

            tri_result_t tri_res = tri_intersect(
                (tri_request_t){
                    .context_id = 0,
                    .ray = ray_geom,
                    .triangle = *triangle
                }
            );

            if (tri_res.hit && tri_res.t < closest_t) {
                closest_t = tri_res.t;
                closest_primitive = tri_res.primitive_id;
                closest_bary = tri_res.bary_pos;
                closest_facing_front = tri_res.facing_front;
                found_hit = 1;
            }
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