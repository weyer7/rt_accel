// Credit to ChatGPT

/*
 * Export the software reference model's constructed BVH and sorted triangles
 * into simple text memories for traversal_controller_tb.sv.
 *
 * File format (hex words, whitespace separated):
 *   bvh_nodes.hex:
 *     line 1: node_count (decimal)
 *     each following line:
 *       min_x min_y min_z max_x max_y max_z left_first tri_count
 *
 *   triangles.hex:
 *     line 1: triangle_count (decimal)
 *     each following line:
 *       primitive_id v1_x v1_y v1_z v2_x v2_y v2_z v3_x v3_y v3_z
 *
 * All geometry words are signed Q16.16, printed as 32-bit hexadecimal
 * two's-complement values. Addresses are byte addresses and are rebased to
 * the requested output bases. The records match the testbench's 32-byte
 * bvh_node_t and 40-byte triangle-memory stride.
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

/* These are the software-reference-model APIs supplied by the project. */
extern tri_t *load_triangles_from_file(const char *filename,
                                      uint32_t *out_tri_count);
extern bvh_node_t *construct_bvh(tri_t *object_base, uint32_t tri_count,
                                 uint32_t *out_node_count);

#define TB_NODE_BYTES  32u
#ifndef TB_TRI_STRIDE
#define TB_TRI_STRIDE  40u
#endif
#define Q16_SCALE      65536.0

static int parse_u32(const char *text, uint32_t *value)
{
    char *end = NULL;
    unsigned long parsed;

    errno = 0;
    parsed = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0' || parsed > UINT32_MAX)
        return 0;
    *value = (uint32_t)parsed;
    return 1;
}

static int validate_triangle_text(const char *filename, uint32_t *triangle_count)
{
    FILE *file = fopen(filename, "r");
    uint32_t float_count = 0;
    float value;
    int scan_result;

    if (file == NULL) {
        perror(filename);
        return 0;
    }

    while ((scan_result = fscanf(file, "%f", &value)) == 1) {
        if (!isfinite((double)value)) {
            fprintf(stderr, "Non-finite coordinate in %s\n", filename);
            fclose(file);
            return 0;
        }
        if (float_count == UINT32_MAX) {
            fprintf(stderr, "Too many coordinates in %s\n", filename);
            fclose(file);
            return 0;
        }
        ++float_count;
    }

    if (!feof(file)) {
        fprintf(stderr, "Invalid non-numeric token in %s\n", filename);
        fclose(file);
        return 0;
    }
    fclose(file);

    if (float_count == 0 || (float_count % 9u) != 0) {
        fprintf(stderr,
                "%s contains %" PRIu32 " floats; expected a nonzero multiple of 9\n",
                filename, float_count);
        return 0;
    }

    *triangle_count = float_count / 9u;
    return 1;
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

    /* Match the nearest-integer conversion used by the SV testbench. */
    rounded = (int64_t)llround(scaled);
    *word = (uint32_t)(int32_t)rounded;
    return 1;
}

static int write_q16(FILE *file, float value)
{
    uint32_t word;
    if (!float_to_q16(value, &word))
        return 0;
    return fprintf(file, "%08" PRIx32, word) >= 0;
}

static int rebase_address(uint32_t source_address, uint32_t source_base,
                          uint32_t output_base, uint32_t stride,
                          uint32_t count, uint32_t *rebased)
{
    uint32_t offset;

    if (source_address < source_base)
        return 0;
    offset = source_address - source_base;
    if ((offset % stride) != 0 || (offset / stride) >= count)
        return 0;
    if (output_base > UINT32_MAX - offset)
        return 0;
    *rebased = output_base + offset;
    return 1;
}

static int write_bvh_file(const char *filename, const bvh_node_t *nodes,
                          uint32_t node_count, uint32_t tri_count,
                          uint32_t output_bvh_base, uint32_t output_tri_base)
{
    FILE *file = fopen(filename, "w");
    uint32_t i;

    if (file == NULL) {
        perror(filename);
        return 0;
    }

    if (fprintf(file, "%" PRIu32 "\n", node_count) < 0)
        goto io_error;

    for (i = 0; i < node_count; ++i) {
        const bvh_node_t *node = &nodes[i];
        uint32_t left_first = 0;

        if (node->tri_count > 1) {
            if (!rebase_address((uint32_t)node->left_first,
                                (uint32_t)RTU_BVH_BASE,
                                output_bvh_base, TB_NODE_BYTES,
                                node_count, &left_first)) {
                fprintf(stderr,
                        "BVH node %" PRIu32 ": invalid child address 0x%08" PRIx32 "\n",
                        i, (uint32_t)node->left_first);
                fclose(file);
                return 0;
            }
        } else if (node->tri_count == 1) {
            if (!rebase_address((uint32_t)node->left_first,
                                (uint32_t)RTU_TRI_BASE,
                                output_tri_base, TB_TRI_STRIDE,
                                tri_count, &left_first)) {
                fprintf(stderr,
                        "BVH leaf %" PRIu32 ": invalid triangle address 0x%08" PRIx32 "\n",
                        i, (uint32_t)node->left_first);
                fclose(file);
                return 0;
            }
        }

        if (!write_q16(file, node->aabb.corner_a.x) || fprintf(file, " ") < 0 ||
            !write_q16(file, node->aabb.corner_a.y) || fprintf(file, " ") < 0 ||
            !write_q16(file, node->aabb.corner_a.z) || fprintf(file, " ") < 0 ||
            !write_q16(file, node->aabb.corner_b.x) || fprintf(file, " ") < 0 ||
            !write_q16(file, node->aabb.corner_b.y) || fprintf(file, " ") < 0 ||
            !write_q16(file, node->aabb.corner_b.z) || fprintf(file, " ") < 0 ||
            fprintf(file, "%08" PRIx32 " %08" PRIx32 "\n",
                    left_first, (uint32_t)node->tri_count) < 0)
            goto io_error;
    }

    if (fclose(file) != 0) {
        perror(filename);
        return 0;
    }
    return 1;

io_error:
    fprintf(stderr, "Failed writing %s\n", filename);
    fclose(file);
    return 0;
}

static int write_triangle_file(const char *filename, const tri_t *triangles,
                               uint32_t tri_count)
{
    FILE *file = fopen(filename, "w");
    uint32_t i;

    if (file == NULL) {
        perror(filename);
        return 0;
    }

    if (fprintf(file, "%" PRIu32 "\n", tri_count) < 0)
        goto io_error;

    for (i = 0; i < tri_count; ++i) {
        const tri_t *tri = &triangles[i];

        if (fprintf(file, "%08" PRIx32 " ", (uint32_t)tri->primitive_id) < 0 ||
            !write_q16(file, tri->vertex1.x) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex1.y) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex1.z) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex2.x) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex2.y) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex2.z) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex3.x) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex3.y) || fprintf(file, " ") < 0 ||
            !write_q16(file, tri->vertex3.z) || fprintf(file, "\n") < 0)
            goto io_error;
    }

    if (fclose(file) != 0) {
        perror(filename);
        return 0;
    }
    return 1;

io_error:
    fprintf(stderr, "Failed writing %s\n", filename);
    fclose(file);
    return 0;
}

int main(int argc, char **argv)
{
    const char *input_file;
    const char *bvh_file;
    const char *tri_file;
    uint32_t output_bvh_base = (uint32_t)RTU_BVH_BASE;
    uint32_t output_tri_base = (uint32_t)RTU_TRI_BASE;
    uint32_t tri_count = 0;
    uint32_t validated_tri_count = 0;
    uint32_t node_count = 0;
    tri_t *triangles = NULL;
    bvh_node_t *nodes = NULL;
    int ok = 0;

    if (argc < 4 || argc > 6) {
        fprintf(stderr,
                "Usage: %s input_triangles.txt bvh_nodes.hex triangles.hex [bvh_base] [tri_base]\n"
                "Bases accept decimal or 0x-prefixed hexadecimal values.\n",
                argv[0]);
        return EXIT_FAILURE;
    }

    input_file = argv[1];
    bvh_file = argv[2];
    tri_file = argv[3];

    if (argc >= 5 && !parse_u32(argv[4], &output_bvh_base)) {
        fprintf(stderr, "Invalid BVH output base: %s\n", argv[4]);
        return EXIT_FAILURE;
    }
    if (argc >= 6 && !parse_u32(argv[5], &output_tri_base)) {
        fprintf(stderr, "Invalid triangle output base: %s\n", argv[5]);
        return EXIT_FAILURE;
    }

    if (sizeof(bvh_node_t) != TB_NODE_BYTES) {
        fprintf(stderr, "This exporter expects sizeof(bvh_node_t)=%u, got %zu\n",
                TB_NODE_BYTES, sizeof(bvh_node_t));
        goto cleanup;
    }
    if (sizeof(tri_t) != TB_TRI_STRIDE) {
        fprintf(stderr, "This exporter expects sizeof(tri_t)=%u, got %zu\n",
                TB_TRI_STRIDE, sizeof(tri_t));
        goto cleanup;
    }

    if (!validate_triangle_text(input_file, &validated_tri_count))
        goto cleanup;

    triangles = load_triangles_from_file(input_file, &tri_count);
    if (triangles == NULL || tri_count == 0) {
        fprintf(stderr, "No triangles loaded from %s\n", input_file);
        goto cleanup;
    }
    if (tri_count != validated_tri_count) {
        fprintf(stderr, "Triangle loader returned %" PRIu32
                        " records; input scan found %" PRIu32 "\n",
                tri_count, validated_tri_count);
        goto cleanup;
    }
    if (tri_count > UINT16_MAX + 1u) {
        fprintf(stderr, "Triangle count exceeds the 16-bit primitive ID space\n");
        goto cleanup;
    }

    /* construct_bvh sorts triangles in-place and assigns primitive IDs. */
    nodes = construct_bvh(triangles, tri_count, &node_count);
    if (nodes == NULL || node_count == 0) {
        fprintf(stderr, "BVH construction failed\n");
        goto cleanup;
    }

    if (!write_bvh_file(bvh_file, nodes, node_count, tri_count,
                        output_bvh_base, output_tri_base))
        goto cleanup;
    if (!write_triangle_file(tri_file, triangles, tri_count))
        goto cleanup;

    printf("Exported %" PRIu32 " BVH nodes to %s\n", node_count, bvh_file);
    printf("Exported %" PRIu32 " sorted triangles to %s\n", tri_count, tri_file);
    printf("BVH base=0x%08" PRIx32 " stride=%u bytes\n",
           output_bvh_base, TB_NODE_BYTES);
    printf("Triangle base=0x%08" PRIx32 " stride=%u bytes\n",
           output_tri_base, (unsigned)TB_TRI_STRIDE);
    printf("Geometry encoding: signed Q16.16, 32-bit hexadecimal words\n");
    ok = 1;

cleanup:
    free(nodes);
    free(triangles);
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
