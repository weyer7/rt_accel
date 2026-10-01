#ifndef HARDWARE_RTU_H
#define HARDWARE_RTU_H

#include <stdint.h>

#define RTU_BVH_BASE 0x10000000u
#define RTU_TRI_BASE 0x20000000u

//=================================================
//geometry types
//=================================================

//Used to store 3D coordinates / directions
typedef struct float3 {
    float x;
    float y;
    float z;
} float3_t;

//used to store 2D coordinates / directions
typedef struct float2 {
    float u;
    float v;
} float2_t;

//=================================================
//geometry stored in memory
//=================================================

typedef struct aabb {
    float3_t corner_a;
    float3_t corner_b;
} aabb_t;

typedef struct tri {
    uint32_t primitive_id;
    float3_t vertex1;
    float3_t vertex2;
    float3_t vertex3;
    //is centroid needed for BVH traversal?
    //definitely useful for building BVH
} tri_t;

typedef struct bvh_node {
    aabb_t aabb;
    uint32_t left_first; //if leaf, first triangle addr, otherwise left child addr
    /*
    if leaf
        second tri vertex = first vertex addr + sizeof(float3_t)
        third tri vertex = first vertex addr + sizeof(float3_t)
    else
        right_child address = left_child + sizeof(bvh_node_t)
        this must be enforced during BVH construction

    */
    uint32_t tri_count; //number of triangles contained in aabb
    //if nonzero, this BVH node represents a leaf
} bvh_node_t;

//=================================================
//ray data used by intersection logic
//=================================================

typedef struct ray_geometry {
    float3_t origin;
    float3_t direction;
    float3_t inv_direction;
    float t_min;
    float t_max;
} ray_geometry_t;

//=================================================
//RTU top-level interface
//=================================================

//hard RTU inputs
typedef struct ray_request {
    uint32_t ray_id; //unique GPU ray ID (is this a compiler-level construct?)
    uint32_t bvh_root; //address of BVH tree root created by GPU (software)
    uint32_t control; //reserved; can be used later to process in different ways

    float3_t origin; //ray origin (X,Y,Z)
    float3_t direction; //ray direction unit vector <X,Y,Z>

    float t_min; //minimum distance to consider hit
    float t_max; //initial maximum distance to consider hit
} ray_request_t; //1+3+3+1+1+1 = 11 words

//hard RTU outputs
typedef struct ray_result {
    uint32_t primitive_id; //the ID of the triangle that the ray intersected
    float distance; //distance from ray to primative intersection. inf means miss. sign indicates if the ray struck the front or the back of the triangle
    float2_t bary_pos; //barycentric coordinates on triangle (U,V)
} ray_result_t; //1+1+2 = 4 words

//=================================================
//AABB intersection unit
//=================================================

//AABB intersection request (inputs)
typedef struct aabb_request {
    uint8_t context_id;
    ray_geometry_t ray;
    aabb_t aabb;
} aabb_request_t;

//AABB intersection result (outputs)
typedef struct aabb_result {
    uint8_t context_id;
    uint32_t hit;
    float t_near;
    float t_far;
} aabb_result_t;

//=================================================
//triangle intersection unit
//=================================================

//triangle intersection request (inputs)
typedef struct tri_request {
    uint8_t context_id;
    ray_geometry_t ray;
    tri_t triangle;
} tri_request_t;

//triangle intersection result (outputs)
typedef struct tri_result {
    uint8_t context_id;
    uint32_t hit;
    uint32_t primitive_id;
    float t;
    float2_t bary_pos;
    uint32_t facing_front;
} tri_result_t;

//=================================================
//traversal controller interface
//=================================================

typedef struct traversal_request {
    ray_request_t ray;
} traversal_request_t;

typedef struct traversal_result {
    uint32_t primitive_id;
    float distance;
    float2_t bary_pos;
} traversal_result_t;

//=================================================
//internal ray context
//=================================================

//fields tracked by the RTU for each context (stored in SRAM)
typedef struct ray_context {
    //CONTEXT SPECIFIC (INTERNAL ONLY)
    uint8_t context_id; //unique value assigned internally to each context within RTU
    float3_t inv_dir; //pre-computed inverse of the direction vector. This saves many unnecessary hardware divides
    uint32_t hit;
    uint32_t facing_front;

    //FROM RAY REQUEST
    uint32_t ray_id; //unique GPU ray ID (is this a compiler-level construct?)
    uint32_t bvh_root; //address of BVH tree root created by GPU (software)
    uint32_t control; //reserved; can be used later to process in different ways

    float3_t origin; //ray origin (X,Y,Z)
    float3_t direction; //ray direction unit vector <X,Y,Z>

    float t_min; //minimum distance to consider hit
    float t_max; //initial maximum distance to consider hit (updated after each hit for closest_hit)

    //REQUIRED FOR RAY RESULT OUTPUT (stores most recent candidate for closest hit)
    uint32_t primitive_id; //null if no hit, otherwise the triangle that the ray intersected
    float distance; //distance from ray to primative intersection. inf means miss. sign indicates if the ray struck the front or the back of the triangle
    float2_t bary_pos; //barycentric coordinates on triangle (U,V)
} ray_context_t;

//=================================================
// software RTU memory mapping
//=================================================

typedef struct rtu_scene {
    bvh_node_t *bvh_nodes;
    uint32_t bvh_node_count;

    tri_t *triangles;
    uint32_t tri_count;
} rtu_scene_t;

//hardware functions
aabb_result_t aabb_intersect (aabb_request_t aabb_request);
tri_result_t tri_intersect (tri_request_t tri_request);
traversal_result_t traverse_bvh(traversal_request_t traversal_request);

//for benchmark
traversal_result_t traverse_bruteforce(traversal_request_t traversal_request);

//software-only
tri_t *load_triangles_from_file(const char *filename, uint32_t *out_tri_count);
bvh_node_t *construct_bvh(tri_t *triangles, uint32_t tri_count, uint32_t *out_node_count);
int render_bvh(tri_t *triangles, uint32_t tri_count, bvh_node_t *bvh_root, uint32_t bvh_node_count, float yaw_deg, float pitch_deg, uint32_t rays_per_pixel, uint32_t *total_rays);
void rtu_scene_bind(rtu_scene_t *scene, bvh_node_t *bvh_root, uint32_t bvh_node_count, uint32_t tri_count, tri_t *triangles);
bvh_node_t *rtu_bvh_node_from_addr(uint32_t addr);
tri_t *rtu_tri_from_addr(uint32_t addr);
uint32_t rtu_scene_tri_count(void);

#endif