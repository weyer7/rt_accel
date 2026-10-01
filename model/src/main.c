#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <float.h>
#include "hardware_rtu.h"

#include <time.h>
#include <inttypes.h>
#include "rtu_stats.h"

//calculates elapsed time in seconds
static double elapsed_seconds(struct timespec start, struct timespec end)
{
    return (double)(end.tv_sec - start.tv_sec) + (double)(end.tv_nsec - start.tv_nsec) / 1e9;
}

int main(void) {
    /*
    ray_t ray;
    aabb_t aabb;

    //direction unit vector
    ray.direction.x = -1;
    ray.direction.y = 0;
    ray.direction.z = 0;

    ray.origin.x = 2;    
    ray.origin.y = 0;
    ray.origin.z = 0;

    ray.t_max = 10;
    ray.t_min = 0;
    
    aabb.corner_a.x = -1;
    aabb.corner_a.y = -1;
    aabb.corner_a.z = -1;

    aabb.corner_b.x = 1;
    aabb.corner_b.y = 1;
    aabb.corner_b.z = 1;

    if (aabb_intersect(&ray, aabb)) {
        printf("hit\n");
    } else {
        printf("miss\n");
    }
    */

    /*
    uint32_t tri_count = 0;
    //load tris
    tri_t *triangles = load_triangles_from_file("assets/armadillo.tri", &tri_count);
    if (!triangles) {
        printf("Failed to load geometry or file contained fewer than 9 floats.\n");
        return 1;
    }
    printf("loaded %d tris from file\n", tri_count);

    //build BVH tree
    bvh_node_t *bvh_root = construct_bvh(triangles, tri_count);
    if (!bvh_root) {
        printf("Failed to build BVH.\n");
        free(triangles);
        return 1;
    }

    //cleanup
    */


    uint32_t tri_count = 0;

    tri_t *triangles = load_triangles_from_file("assets/armadillo.tri", &tri_count);

    if (!triangles) {
        printf("Failed to load geometry or file contained\nfewer than 9 floats.\n");
        return 1;
    }

    printf("loaded %u tris from file\n", tri_count);

    // for (uint32_t i = 0; i < tri_count; i++) {
    //     tri_t *t = &triangles[i];

    //     if (fabsf(t->vertex1.x) > 10.0f ||
    //         fabsf(t->vertex1.y) > 10.0f ||
    //         fabsf(t->vertex1.z) > 10.0f ||
    //         fabsf(t->vertex2.x) > 10.0f ||
    //         fabsf(t->vertex2.y) > 10.0f ||
    //         fabsf(t->vertex2.z) > 10.0f ||
    //         fabsf(t->vertex3.x) > 10.0f ||
    //         fabsf(t->vertex3.y) > 10.0f ||
    //         fabsf(t->vertex3.z) > 10.0f) {

    //         printf("OUTLIER triangle %u:\n", i);
    //         printf("  v1 = (%f, %f, %f)\n", t->vertex1.x, t->vertex1.y, t->vertex1.z);
    //         printf("  v2 = (%f, %f, %f)\n", t->vertex2.x, t->vertex2.y, t->vertex2.z);
    //         printf("  v3 = (%f, %f, %f)\n", t->vertex3.x, t->vertex3.y, t->vertex3.z);
    //     }
    // }

    uint32_t bvh_node_count = 0;
    bvh_node_t *bvh_root = construct_bvh(triangles, tri_count, &bvh_node_count);

    if (!bvh_root) {
        printf("Failed to build BVH.\n");
        free(triangles);
        return 1;
    }

    printf("constructed BVH with %u nodes\n", bvh_node_count);

    printf("Root AABB:\n");
    printf("  min = (%f, %f, %f)\n",
        bvh_root->aabb.corner_a.x,
        bvh_root->aabb.corner_a.y,
        bvh_root->aabb.corner_a.z);

    printf("  max = (%f, %f, %f)\n",
        bvh_root->aabb.corner_b.x,
        bvh_root->aabb.corner_b.y,
        bvh_root->aabb.corner_b.z);

    uint32_t total_rays = 0;
    struct timespec start_time, end_time;
    rtu_stats_reset();
    clock_gettime(CLOCK_MONOTONIC, &start_time);

    int render_result = render_bvh(
        triangles, tri_count, bvh_root, bvh_node_count,
        140.0, 25.0, 4, &total_rays
    );

    clock_gettime(CLOCK_MONOTONIC, &end_time);

    double elapsed = elapsed_seconds(start_time, end_time);

    if (render_result != 0) {
        fprintf(stderr, "render failed\n");
        return 1;
    }

    printf("\n");
    printf("========================================\n");
    printf("RTU Render Statistics\n");
    printf("========================================\n");
    printf("Rays:                     %" PRIu32 "\n", total_rays);
    printf("Triangle intersections:   %" PRIu64 "\n", rtu_tri_intersection_count);
    printf("AABB intersections:       %" PRIu64 "\n", rtu_aabb_intersection_count);
    if (total_rays > 0) {
        printf("Triangle tests / ray:     %.3f\n", (double)rtu_tri_intersection_count / total_rays);
        printf("AABB tests / ray:         %.3f\n", (double)rtu_aabb_intersection_count / total_rays);
        printf("Total tests / ray:        %.3f\n", (double)(rtu_aabb_intersection_count + rtu_tri_intersection_count)/ total_rays);
        printf("Time / ray:               %.3f ns\n", elapsed * 1e9 / total_rays);
    }

    if (rtu_tri_intersection_count > 0) {
        printf("Time / test:              %.3f ns\n", elapsed * 1e9 / (rtu_tri_intersection_count + rtu_aabb_intersection_count));
    }

    printf("Render time:              %.6f s\n", elapsed);
    printf("========================================\n");


    free(bvh_root);
    free(triangles);

    return 0;
}