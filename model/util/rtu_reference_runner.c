/*
 * Run the software BVH traversal reference against the exact quantized
 * memory image consumed by the SystemVerilog testbench.
 *
 * Usage:
 *   rtu_reference_runner bvh_nodes.hex triangles.hex \
 *       reference_rays.hex reference_results.hex
 *
 * File formats are documented in BVH_REFERENCE_COMPARE_README.md.
 */
#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "hardware_rtu.h"

#ifndef RTU_BVH_BASE
#error "hardware_rtu.h must define RTU_BVH_BASE"
#endif
#ifndef RTU_TRI_BASE
#error "hardware_rtu.h must define RTU_TRI_BASE"
#endif

#ifndef TB_NODE_BYTES
#define TB_NODE_BYTES 32u
#endif
#ifndef TB_TRI_STRIDE
#define TB_TRI_STRIDE 40u
#endif
#define Q16_SCALE 65536.0

/* Provided by the software reference implementation. */
extern traversal_result_t traverse_bvh(traversal_request_t traversal_request);

static int read_u32_hex(FILE *file, uint32_t *value)
{
    char token[64];
    char *end = NULL;
    unsigned long parsed;

    if (fscanf(file, "%63s", token) != 1)
        return 0;
    errno = 0;
    parsed = strtoul(token, &end, 16);
    if (errno != 0 || end == token || *end != '\0' || parsed > UINT32_MAX)
        return 0;
    *value = (uint32_t)parsed;
    return 1;
}

static int read_decimal_count(FILE *file, uint32_t *count)
{
    unsigned long parsed;
    char token[64];
    char *end = NULL;

    if (fscanf(file, "%63s", token) != 1)
        return 0;
    errno = 0;
    parsed = strtoul(token, &end, 10);
    if (errno != 0 || end == token || *end != '\0' || parsed > UINT32_MAX)
        return 0;
    *count = (uint32_t)parsed;
    return 1;
}

static float q16_to_float(uint32_t word)
{
    return (float)(int32_t)word / (float)Q16_SCALE;
}

static int float_to_q16(float value, uint32_t *word)
{
    double scaled;
    int64_t rounded;

    if (!isfinite((double)value))
        return 0;
    scaled = (double)value * Q16_SCALE;
    if (scaled < -2147483648.0 || scaled > 2147483647.0)
        return 0;
    rounded = llround(scaled);
    if (rounded < INT32_MIN || rounded > INT32_MAX)
        return 0;
    *word = (uint32_t)(int32_t)rounded;
    return 1;
}

static int load_bvh_file(const char *filename, bvh_node_t **out_nodes,
                         uint32_t *out_count)
{
    FILE *file = NULL;
    bvh_node_t *nodes = NULL;
    uint32_t count = 0;
    uint32_t i;
    int ok = 0;

    file = fopen(filename, "r");
    if (file == NULL) {
        perror(filename);
        goto cleanup;
    }
    if (!read_decimal_count(file, &count) || count == 0) {
        fprintf(stderr, "%s: invalid or empty node-count header\n", filename);
        goto cleanup;
    }
    nodes = (bvh_node_t *)calloc(count, sizeof(*nodes));
    if (nodes == NULL) {
        fprintf(stderr, "Unable to allocate %" PRIu32 " BVH nodes\n", count);
        goto cleanup;
    }

    for (i = 0; i < count; ++i) {
        uint32_t w[8];
        unsigned j;
        for (j = 0; j < 8; ++j) {
            if (!read_u32_hex(file, &w[j])) {
                fprintf(stderr, "%s: malformed node record %" PRIu32
                                " (word %u/8)\n", filename, i, j + 1);
                goto cleanup;
            }
        }
        nodes[i].aabb.corner_a.x = q16_to_float(w[0]);
        nodes[i].aabb.corner_a.y = q16_to_float(w[1]);
        nodes[i].aabb.corner_a.z = q16_to_float(w[2]);
        nodes[i].aabb.corner_b.x = q16_to_float(w[3]);
        nodes[i].aabb.corner_b.y = q16_to_float(w[4]);
        nodes[i].aabb.corner_b.z = q16_to_float(w[5]);
        nodes[i].left_first = w[6];
        nodes[i].tri_count = w[7];
    }

    *out_nodes = nodes;
    *out_count = count;
    nodes = NULL;
    ok = 1;

cleanup:
    free(nodes);
    if (file != NULL)
        fclose(file);
    return ok;
}

static int load_triangle_file(const char *filename, tri_t **out_triangles,
                              uint32_t *out_count)
{
    FILE *file = NULL;
    tri_t *triangles = NULL;
    uint32_t count = 0;
    uint32_t i;
    int ok = 0;

    file = fopen(filename, "r");
    if (file == NULL) {
        perror(filename);
        goto cleanup;
    }
    if (!read_decimal_count(file, &count) || count == 0) {
        fprintf(stderr, "%s: invalid or empty triangle-count header\n", filename);
        goto cleanup;
    }
    triangles = (tri_t *)calloc(count, sizeof(*triangles));
    if (triangles == NULL) {
        fprintf(stderr, "Unable to allocate %" PRIu32 " triangles\n", count);
        goto cleanup;
    }

    for (i = 0; i < count; ++i) {
        uint32_t w[10];
        unsigned j;
        for (j = 0; j < 10; ++j) {
            if (!read_u32_hex(file, &w[j])) {
                fprintf(stderr, "%s: malformed triangle record %" PRIu32
                                " (word %u/10)\n", filename, i, j + 1);
                goto cleanup;
            }
        }
        if (w[0] > UINT16_MAX) {
            fprintf(stderr, "%s: primitive ID 0x%08" PRIx32
                            " exceeds RTL's 16-bit primitive ID\n", filename, w[0]);
            goto cleanup;
        }
        triangles[i].primitive_id = w[0];
        triangles[i].vertex1.x = q16_to_float(w[1]);
        triangles[i].vertex1.y = q16_to_float(w[2]);
        triangles[i].vertex1.z = q16_to_float(w[3]);
        triangles[i].vertex2.x = q16_to_float(w[4]);
        triangles[i].vertex2.y = q16_to_float(w[5]);
        triangles[i].vertex2.z = q16_to_float(w[6]);
        triangles[i].vertex3.x = q16_to_float(w[7]);
        triangles[i].vertex3.y = q16_to_float(w[8]);
        triangles[i].vertex3.z = q16_to_float(w[9]);
    }

    *out_triangles = triangles;
    *out_count = count;
    triangles = NULL;
    ok = 1;

cleanup:
    free(triangles);
    if (file != NULL)
        fclose(file);
    return ok;
}

static int write_reference_results(const char *rays_filename,
                                   const char *results_filename,
                                   bvh_node_t *nodes, uint32_t node_count,
                                   tri_t *triangles, uint32_t triangle_count)
{
    FILE *rays = NULL;
    FILE *results = NULL;
    rtu_scene_t scene;
    uint32_t ray_count = 0;
    uint32_t i;
    int ok = 0;

    rays = fopen(rays_filename, "r");
    if (rays == NULL) {
        perror(rays_filename);
        goto cleanup;
    }
    if (!read_decimal_count(rays, &ray_count) || ray_count == 0) {
        fprintf(stderr, "%s: invalid or empty ray-count header\n", rays_filename);
        goto cleanup;
    }

    results = fopen(results_filename, "w");
    if (results == NULL) {
        perror(results_filename);
        goto cleanup;
    }
    if (fprintf(results, "%" PRIu32 "\n", ray_count) < 0)
        goto cleanup;

    /* Bind the imported, quantized memory image, not a second BVH build. */
    rtu_scene_bind(&scene, nodes, node_count, triangle_count, triangles);

    for (i = 0; i < ray_count; ++i) {
        uint32_t words[12];
        unsigned j;
        ray_request_t ray;
        traversal_request_t request;
        traversal_result_t result;
        uint32_t hit;
        uint32_t primitive;
        uint32_t distance_word = 0;
        uint32_t u_word = 0;
        uint32_t v_word = 0;

        for (j = 0; j < 12; ++j) {
            if (!read_u32_hex(rays, &words[j])) {
                fprintf(stderr, "%s: malformed ray record %" PRIu32
                                " (word %u/12)\n", rays_filename, i, j + 1);
                goto cleanup;
            }
        }
        if (words[0] > UINT16_MAX) {
            fprintf(stderr, "Ray ID 0x%08" PRIx32 " exceeds 16 bits\n", words[0]);
            goto cleanup;
        }

        memset(&ray, 0, sizeof(ray));
        ray.ray_id = words[0];
        ray.bvh_root = (uint32_t)RTU_BVH_BASE;
        ray.control = 0;
        ray.origin.x = q16_to_float(words[1]);
        ray.origin.y = q16_to_float(words[2]);
        ray.origin.z = q16_to_float(words[3]);
        ray.direction.x = q16_to_float(words[4]);
        ray.direction.y = q16_to_float(words[5]);
        ray.direction.z = q16_to_float(words[6]);
        ray.t_min = q16_to_float(words[10]);
        ray.t_max = q16_to_float(words[11]);

        memset(&request, 0, sizeof(request));
        request.ray = ray;
        result = traverse_bvh(request);

        hit = isfinite((double)result.distance) ? 1u : 0u;
        primitive = hit ? (uint32_t)result.primitive_id : 0u;
        if (primitive > UINT16_MAX) {
            fprintf(stderr, "Reference primitive ID %" PRIu32
                            " exceeds RTL's 16-bit field\n", primitive);
            goto cleanup;
        }
        if (hit) {
            if (!float_to_q16(result.distance, &distance_word) ||
                !float_to_q16(result.bary_pos.u, &u_word) ||
                !float_to_q16(result.bary_pos.v, &v_word)) {
                fprintf(stderr, "Ray %" PRIu32
                                ": reference result cannot be represented in Q16.16\n", i);
                goto cleanup;
            }
        }

        if (fprintf(results, "%08" PRIx32 " %08" PRIx32
                            " %08" PRIx32 " %08" PRIx32
                            " %08" PRIx32 " %08" PRIx32 "\n",
                    words[0], hit, primitive, distance_word, u_word, v_word) < 0) {
            fprintf(stderr, "Failed writing %s\n", results_filename);
            goto cleanup;
        }
        printf("[CREF] ray=%" PRIu32 " hit=%u prim=%" PRIu32
               " distance=% .7f u=%.7f v=%.7f\n",
               words[0], hit, primitive,
               hit ? (double)result.distance : 0.0,
               hit ? (double)result.bary_pos.u : 0.0,
               hit ? (double)result.bary_pos.v : 0.0);
    }

    if (fclose(results) != 0) {
        results = NULL;
        perror(results_filename);
        goto cleanup;
    }
    results = NULL;
    ok = 1;

cleanup:
    if (rays != NULL)
        fclose(rays);
    if (results != NULL)
        fclose(results);
    return ok;
}

int main(int argc, char **argv)
{
    bvh_node_t *nodes = NULL;
    tri_t *triangles = NULL;
    uint32_t node_count = 0;
    uint32_t triangle_count = 0;
    int ok = 0;

    if (argc != 5) {
        fprintf(stderr,
                "Usage: %s bvh_nodes.hex triangles.hex reference_rays.hex reference_results.hex\n",
                argv[0]);
        return EXIT_FAILURE;
    }
    if (sizeof(bvh_node_t) != TB_NODE_BYTES) {
        fprintf(stderr, "Expected sizeof(bvh_node_t)=%u, got %zu\n",
                TB_NODE_BYTES, sizeof(bvh_node_t));
        goto cleanup;
    }
    if (sizeof(tri_t) != TB_TRI_STRIDE) {
        fprintf(stderr, "Expected sizeof(tri_t)=%u, got %zu\n",
                TB_TRI_STRIDE, sizeof(tri_t));
        goto cleanup;
    }

    if (!load_bvh_file(argv[1], &nodes, &node_count) ||
        !load_triangle_file(argv[2], &triangles, &triangle_count))
        goto cleanup;

    printf("[CREF] Loaded %" PRIu32 " nodes and %" PRIu32 " triangles\n",
           node_count, triangle_count);
    if (!write_reference_results(argv[3], argv[4], nodes, node_count,
                                 triangles, triangle_count))
        goto cleanup;
    printf("[CREF] Wrote software reference results to %s\n", argv[4]);
    ok = 1;

cleanup:
    free(nodes);
    free(triangles);
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
