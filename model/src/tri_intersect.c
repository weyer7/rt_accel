#include <math.h>
#include "hardware_rtu.h"
#include "rtu_stats.h"

//returns the subtracted sum of 2 float3s
float3_t vec3_sub(float3_t a, float3_t b) {
    return (float3_t){a.x - b.x, a.y - b.y, a.z - b.z};
}

//returns the cross product of 2 float3s
float3_t vec3_cross(float3_t a, float3_t b) {
    return (float3_t){
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
}

//returns the dot product of 2 float3s
float vec3_dot(float3_t a, float3_t b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

//performes ray-triangle intersection with Moller-Trumbore
tri_result_t tri_intersect (tri_request_t tri_request) {
    rtu_tri_intersection_count++;

    const float EPSILON = 1e-7f; //can tune

    tri_result_t result = {.context_id = tri_request.context_id,
        .hit = 0, .primitive_id = tri_request.triangle.primitive_id,
        .t = 0.0f, .bary_pos = {.u = 0.0f, .v = 0.0f}, .facing_front = 0
    };

    //triangle edge vectors
    float3_t edge1 = vec3_sub(tri_request.triangle.vertex2, tri_request.triangle.vertex1);
    float3_t edge2 = vec3_sub(tri_request.triangle.vertex3, tri_request.triangle.vertex1);

    //find determinant: det = ray.direction . (edge1 * edge2)
    float3_t h = vec3_cross(tri_request.ray.direction, edge2);
    float det = vec3_dot(edge1, h);

    //if det is ~0, ray lies parallel to triangle plane
    if (fabs(det) < EPSILON) {
        return result; //clean miss instead of crazy numbers
    }

    float inv_det = 1.0 / det; //will be replaced with pre-computed ivnerse in hardware

    //distance vector from vertex1 to ray origin
    float3_t s = vec3_sub(tri_request.ray.origin, tri_request.triangle.vertex1);

    //calculate u and test bounds
    float u = inv_det * vec3_dot(s, h);
    if (u < 0.0f || u > 1.0f) {
        return result; //miss
    }

    float3_t q = vec3_cross(s, edge1);

    //calculate v and test bounds
    float v = inv_det * vec3_dot(tri_request.ray.direction, q);
    if (v < 0.0f || (u + v) > 1.0f) {
        return result; //miss
    }
    
    //compute ray distance t
    float t = inv_det * vec3_dot(edge2, q);

    //check if hit distance is within ray interval [tmin, tmax]
    if (t < tri_request.ray.t_min || t > tri_request.ray.t_max) {

        return result; //miss
    }

    result.hit = 1;
    result.t = t;
    result.bary_pos.u = u;
    result.bary_pos.v = v;
    result.primitive_id = tri_request.triangle.primitive_id;
    result.facing_front = (det < 0.0) ? 1 : 0;

    return result; //hit
}