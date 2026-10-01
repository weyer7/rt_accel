//thanks to Google Gemini

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "hardware_rtu.h"

/**
 * Parses floating-point triplets from a text file into a dynamic array of `tri_t`.
 * 
 * @param filename      Path to the source text file.
 * @param out_tri_count Pointer where the total number of loaded triangles will be written.
 * @return              Pointer to dynamically allocated `tri_t` array, or NULL on error.
 *                      The caller is responsible for calling free() on the returned pointer.
 */
tri_t *load_triangles_from_file(const char *filename, uint32_t *out_tri_count) {
    if (filename == NULL || out_tri_count == NULL) return NULL;

    FILE *file = fopen(filename, "r");
    if (!file) {
        perror("Failed to open triangle file");
        *out_tri_count = 0;
        return NULL;
    }

    // Pass 1: Count total valid floating-point tokens
    uint32_t total_floats = 0;
    float temp_val;
    while (fscanf(file, "%f", &temp_val) == 1) {
        total_floats++;
    }

    // Each triangle requires 9 floats (3 vertices * 3 coordinates [X, Y, Z])
    uint32_t triangle_count = total_floats / 9;

    if (triangle_count == 0) {
        fclose(file);
        *out_tri_count = 0;
        return NULL;
    }

    // Allocate array compatible with construct_bvh()
    tri_t *triangles = malloc(triangle_count * sizeof(tri_t));
    if (!triangles) {
        fclose(file);
        *out_tri_count = 0;
        return NULL;
    }

    // Pass 2: Rewind file pointer and parse triangle data
    rewind(file);

    for (uint32_t i = 0; i < triangle_count; i++) {
        triangles[i].primitive_id = i; // Assign ID matching triangle index

        int read_count = fscanf(file, "%f %f %f %f %f %f %f %f %f",
            &triangles[i].vertex1.x, &triangles[i].vertex1.y, &triangles[i].vertex1.z,
            &triangles[i].vertex2.x, &triangles[i].vertex2.y, &triangles[i].vertex2.z,
            &triangles[i].vertex3.x, &triangles[i].vertex3.y, &triangles[i].vertex3.z
        );

        if (read_count != 9) {
            // Handle partial read errors safely
            break;
        }
    }

    fclose(file);

    *out_tri_count = triangle_count;
    return triangles;
}