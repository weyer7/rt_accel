#include <stdint.h>
#include <stddef.h>

#include "hardware_rtu.h"

static rtu_scene_t *g_scene = NULL;

//registers the BVH nodes and triangle buffers into the scene structure and sets it as the active global scene context
void rtu_scene_bind(rtu_scene_t *scene, bvh_node_t *bvh_root, uint32_t bvh_node_count, uint32_t tri_count, tri_t *triangles) {
    scene->bvh_nodes = bvh_root;
    scene->bvh_node_count = bvh_node_count;
    scene->triangles = triangles;
    scene->tri_count = tri_count;

    g_scene = scene;
}

//returns the total number of triangles present in the currently bound global scene context
uint32_t rtu_scene_tri_count(void) {
    if (g_scene == NULL) return 0;
    return g_scene->tri_count;
}

//converts a simulated hardware memory address into a pointer to the corresponding BVH node array element
bvh_node_t *rtu_bvh_node_from_addr(uint32_t addr) {
    if (g_scene == NULL) return NULL;
    if (addr < RTU_BVH_BASE) return NULL;

    uint32_t offset = addr - RTU_BVH_BASE;
    if (offset % sizeof(bvh_node_t) != 0) return NULL;

    uint32_t index = offset / sizeof(bvh_node_t);
    if (index >= g_scene->bvh_node_count) return NULL;

    return &g_scene->bvh_nodes[index];
}

//converts a simulated hardware memory address into a pointer to the corresponding triangle array element
tri_t *rtu_tri_from_addr(uint32_t addr) {
    if (g_scene == NULL) return NULL;
    if (addr < RTU_TRI_BASE) return NULL;

    uint32_t offset = addr - RTU_TRI_BASE;
    if (offset % sizeof(tri_t) != 0) return NULL;

    uint32_t index = offset / sizeof(tri_t);
    if (index >= g_scene->tri_count) return NULL;

    return &g_scene->triangles[index];
}