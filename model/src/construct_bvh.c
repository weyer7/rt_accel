#include <math.h>
#include <float.h>
#include <stdint.h>
#include <stdlib.h>

#include "hardware_rtu.h"

#define BVH_MAX_LEAF_TRIANGLES 1

//calculates triangle centroid
static float3_t tri_centroid(const tri_t *tri) {
    return (float3_t) {
        (tri->vertex1.x + tri->vertex2.x + tri->vertex3.x) / 3.0f,
        (tri->vertex1.y + tri->vertex2.y + tri->vertex3.y) / 3.0f,
        (tri->vertex1.z + tri->vertex2.z + tri->vertex3.z) / 3.0f
    };
}

//calculates aabb bounds of a triangle
static aabb_t tri_bounds(const tri_t *tri) {
    aabb_t bounds;

    bounds.corner_a.x = fminf(tri->vertex1.x, fminf(tri->vertex2.x, tri->vertex3.x));
    bounds.corner_a.y = fminf(tri->vertex1.y, fminf(tri->vertex2.y, tri->vertex3.y));
    bounds.corner_a.z = fminf(tri->vertex1.z, fminf(tri->vertex2.z, tri->vertex3.z));
    bounds.corner_b.x = fmaxf(tri->vertex1.x, fmaxf(tri->vertex2.x, tri->vertex3.x));
    bounds.corner_b.y = fmaxf(tri->vertex1.y, fmaxf(tri->vertex2.y, tri->vertex3.y));
    bounds.corner_b.z = fmaxf(tri->vertex1.z, fmaxf(tri->vertex2.z, tri->vertex3.z));

    return bounds;
}

//calculates aabb bounds of N triangles
static aabb_t triangles_bounds(tri_t *triangles, uint32_t first, uint32_t count) {
    aabb_t bounds;

    bounds.corner_a.x =  FLT_MAX;
    bounds.corner_a.y =  FLT_MAX;
    bounds.corner_a.z =  FLT_MAX;
    bounds.corner_b.x = -FLT_MAX;
    bounds.corner_b.y = -FLT_MAX;
    bounds.corner_b.z = -FLT_MAX;

    for (uint32_t i = 0; i < count; i++) {
        aabb_t tri_box = tri_bounds(&triangles[first + i]);
        bounds.corner_a.x = fminf(bounds.corner_a.x, tri_box.corner_a.x);
        bounds.corner_a.y = fminf(bounds.corner_a.y, tri_box.corner_a.y);
        bounds.corner_a.z = fminf(bounds.corner_a.z, tri_box.corner_a.z);
        bounds.corner_b.x = fmaxf(bounds.corner_b.x, tri_box.corner_b.x);
        bounds.corner_b.y = fmaxf(bounds.corner_b.y, tri_box.corner_b.y);
        bounds.corner_b.z = fmaxf(bounds.corner_b.z, tri_box.corner_b.z);
    }

    return bounds;
}

static float centroid_axis(const tri_t *tri, int axis) {
    float3_t c = tri_centroid(tri);

    switch (axis) {
        case 0: return c.x;
        case 1: return c.y;
        default: return c.z;
    }
}

/*
simple in-place insertion sort.

not intended to be a high-performance BVH builder.
BVH construction happens in software, so clarity is preferred.
*/
static void sort_triangles(tri_t *triangles, uint32_t first, uint32_t count, int axis) {
    for (uint32_t i = 1; i < count; i++) {
        tri_t key = triangles[first + i];
        float key_centroid = centroid_axis(&key, axis);
        uint32_t j = i;
        while (j > 0) {
            float previous_centroid = centroid_axis(&triangles[first + j - 1], axis);
            if (previous_centroid <= key_centroid) break;
            triangles[first + j] = triangles[first + j - 1];
            j--;
        }
        triangles[first + j] = key;
    }
}

//finds longest axis of aabb
static int longest_axis(aabb_t bounds) {
    float x = bounds.corner_b.x - bounds.corner_a.x;
    float y = bounds.corner_b.y - bounds.corner_a.y;
    float z = bounds.corner_b.z - bounds.corner_a.z;
    if (x >= y && x >= z) return 0;
    if (y >= z) return 1;
    return 2;
}

/*
Recursive BVH construction.

`node` is already allocated.

`node_index` is not needed because children are allocated
from the same contiguous node pool.
 */
static void build_bvh_node(bvh_node_t *node, bvh_node_t *node_pool,
    uint32_t *next_node, tri_t *triangles, uint32_t first, uint32_t count) {
    
    //calculate the bounding box of all triangles
    //contained by this node
    node->aabb = triangles_bounds(triangles, first, count);

    //Stop recursion when the node is small enough
    if (count <= BVH_MAX_LEAF_TRIANGLES) {
        node->left_first = RTU_TRI_BASE + first * sizeof(tri_t);
        node->tri_count = count;
        return;
    }

    //split along the longest axis of the node
    int axis = longest_axis(node->aabb);

    //sort triangles by centroid along the selected axis
    sort_triangles(triangles, first, count, axis);

    //split approximately in half
    uint32_t left_count = count / 2;
    uint32_t right_count = count - left_count;


    //allocate the two child nodes consecutively
    //this guarantees right_child = left_child + sizeof(bvh_node_t) as required by the current node representation
    bvh_node_t *left = &node_pool[(*next_node)++];
    bvh_node_t *right = &node_pool[(*next_node)++];


    //internal node
    //tri_count > 1 means internal. (may change convention)
    node->left_first = RTU_BVH_BASE + (uint32_t)(left - node_pool) * sizeof(bvh_node_t);
    node->tri_count = count;

    //recursively construct both subtrees.
    build_bvh_node(left, node_pool, next_node, triangles, first, left_count);
    build_bvh_node(right, node_pool, next_node, triangles, first + left_count, right_count);
}

/*
takes an object input as an array of primatives
and returns the root of the constructed BCH tree
*/

bvh_node_t *construct_bvh(tri_t *object_base, uint32_t tri_count, uint32_t *out_node_count) {
    if (out_node_count != NULL) *out_node_count = 0;
    if (object_base == NULL || tri_count == 0) return NULL;

    //a binary tree containing N leaves has at most 2*N - 1 nodes
    uint32_t max_nodes = 2 * tri_count - 1;
    bvh_node_t *node_pool = calloc(max_nodes, sizeof(bvh_node_t));
    if (node_pool == NULL) return NULL;

    //node 0 is the root
    //next_node starts at 1 because root is already allocated
    uint32_t next_node = 1;

    build_bvh_node(&node_pool[0], node_pool, &next_node, object_base, 0, tri_count);

    for (uint32_t i = 0; i < tri_count; i++) {
        object_base[i].primitive_id = i;
    }

    if (out_node_count != NULL) *out_node_count = next_node;
    return &node_pool[0];
}