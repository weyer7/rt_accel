#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <float.h>
#include <stdint.h>
#include "hardware_rtu.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define IMAGE_WIDTH  1024
#define IMAGE_HEIGHT 1024
#define OUTPUT_FILE  "armadillo.ppm"
#define DEG2RAD(deg) ((deg) * (float)M_PI / 180.0f)
#define SHADOW_EPSILON 0.001f

#define BRUTE_FORCE

typedef struct { float3_t position, forward, right, up; float fov_y; } camera_t;

//vector helpers
static inline float3_t v3_add(float3_t a, float3_t b) { return (float3_t){a.x + b.x, a.y + b.y, a.z + b.z}; }
static inline float3_t v3_sub(float3_t a, float3_t b) { return (float3_t){a.x - b.x, a.y - b.y, a.z - b.z}; }
static inline float3_t v3_scale(float3_t a, float s)  { return (float3_t){a.x * s, a.y * s, a.z * s}; }
static inline float   v3_dot(float3_t a, float3_t b)   { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline float3_t v3_cross(float3_t a, float3_t b) { return (float3_t){a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x}; }
static inline float   v3_length(float3_t a)            { return sqrtf(v3_dot(a, a)); }
static inline float3_t v3_norm(float3_t a) { float l = v3_length(a); return l < 1e-8f ? (float3_t){0} : v3_scale(a, 1.0f / l); }
static inline float   clamp01(float x)                 { return fminf(fmaxf(x, 0.0f), 1.0f); }

//============================================================
//scene and camera setup
//============================================================

static aabb_t triangles_bounds(const tri_t *tris, uint32_t count) {
    aabb_t b = {{FLT_MAX, FLT_MAX, FLT_MAX}, {-FLT_MAX, -FLT_MAX, -FLT_MAX}};
    for (uint32_t i = 0; i < count; i++) {
        const float3_t v[3] = {tris[i].vertex1, tris[i].vertex2, tris[i].vertex3};
        for (int j = 0; j < 3; j++) {
            b.corner_a.x = fminf(b.corner_a.x, v[j].x); b.corner_b.x = fmaxf(b.corner_b.x, v[j].x);
            b.corner_a.y = fminf(b.corner_a.y, v[j].y); b.corner_b.y = fmaxf(b.corner_b.y, v[j].y);
            b.corner_a.z = fminf(b.corner_a.z, v[j].z); b.corner_b.z = fmaxf(b.corner_b.z, v[j].z);
        }
    }
    return b;
}

//creates camera parameters from object aabb, yaw, and pitch
static camera_t make_camera(aabb_t bounds, float yaw_deg, float pitch_deg) {
    float3_t center = v3_scale(v3_add(bounds.corner_a, bounds.corner_b), 0.5f);
    float3_t extents = v3_sub(bounds.corner_b, bounds.corner_a);
    float radius = 0.5f * v3_length(extents);
    float fov_y = DEG2RAD(60.0f);
    float distance = (radius / tanf(fov_y * 0.5f)) * 1.2f;

    float yaw = DEG2RAD(yaw_deg), pitch = DEG2RAD(pitch_deg);
    float3_t offset = { distance * cosf(pitch) * sinf(yaw), distance * sinf(pitch), distance * cosf(pitch) * cosf(yaw) };

    camera_t cam;
    cam.position = v3_add(center, offset);
    cam.forward  = v3_norm(v3_sub(center, cam.position));
    cam.right    = v3_norm(v3_cross(cam.forward, (float3_t){0.0f, 1.0f, 0.0f}));
    cam.up       = v3_cross(cam.right, cam.forward);
    cam.fov_y    = fov_y;
    return cam;
}

//generates a ray request for hardware model from camera, pixel coordinates, `ray_id`, and `bvh_root`
static ray_request_t generate_ray(const camera_t *cam, float px, float py, uint32_t ray_id, uint32_t bvh_root) {
    float aspect = (float)IMAGE_WIDTH / (float)IMAGE_HEIGHT;
    float tan_fov = tanf(cam->fov_y * 0.5f);
    float ndc_x = (2.0f * px / (float)IMAGE_WIDTH) - 1.0f;
    float ndc_y = 1.0f - (2.0f * py / (float)IMAGE_HEIGHT);

    float3_t dir = v3_add(cam->forward, v3_add(
        v3_scale(cam->right, ndc_x * aspect * tan_fov),
        v3_scale(cam->up, ndc_y * tan_fov)
    ));

    return (ray_request_t){
        .ray_id = ray_id, .bvh_root = bvh_root, .control = 0,
        .origin = cam->position, .direction = v3_norm(dir),
        .t_min = 0.001f, .t_max = FLT_MAX
    };
}

//============================================================
//ray tracing and shading
//============================================================

//computes the normalized unit vector perpendicular to a triangle's surface using cross product of two edges
static inline float3_t triangle_normal(const tri_t *tri) {
    return v3_norm(v3_cross(v3_sub(tri->vertex2, tri->vertex1), v3_sub(tri->vertex3, tri->vertex1)));
}

//returns a light-blue to dark-blue gradient color based on the y direction of a missed ray
static inline float3_t sky_color(float3_t ray_direction) {
    float t = clamp01(0.5f * (ray_direction.y + 1.0f));
    return v3_add(v3_scale((float3_t){0.12f, 0.16f, 0.22f}, 1.0f - t), v3_scale((float3_t){0.55f, 0.72f, 0.95f}, t));
}

//determines if a hit pixel is in shadow by castng a secondary ray towards a light source
static int trace_shadow(const ray_request_t *primary_ray, float3_t hit_pos, float3_t normal, float3_t light_pos, uint32_t bvh_root) {
    float3_t to_light = v3_sub(light_pos, hit_pos);
    float light_dist = v3_length(to_light);
    if (light_dist < SHADOW_EPSILON) return 0;

    ray_request_t shadow_ray = {
        .ray_id = primary_ray->ray_id, .bvh_root = bvh_root, .control = 0,
        .origin = v3_add(hit_pos, v3_scale(normal, SHADOW_EPSILON)),
        .direction = v3_scale(to_light, 1.0f / light_dist),
        .t_min = 0.001f, .t_max = light_dist - SHADOW_EPSILON
    };

#ifdef BRUTE_FORCE
    traversal_result_t res = traverse_bruteforce((traversal_request_t){.ray = shadow_ray});
#else
    traversal_result_t res = traverse_bvh((traversal_request_t){.ray = shadow_ray});
#endif
    return isfinite(res.distance);
}

//calculates the final RBB pixel color at a surface hit using Blinn-Phong model modified by a shadow test
static float3_t shade_hit(const camera_t *camera, const ray_request_t *primary_ray, const traversal_result_t *result, uint32_t bvh_root) {
    if (!isfinite(result->distance)) return sky_color(primary_ray->direction);

    tri_t *tri = rtu_tri_from_addr(RTU_TRI_BASE + result->primitive_id * sizeof(tri_t));
    if (!tri) return sky_color(primary_ray->direction);

    float3_t hit_pos = v3_add(primary_ray->origin, v3_scale(primary_ray->direction, fabsf(result->distance)));
    float3_t normal = triangle_normal(tri);
    // if (result->distance < 0.0f) normal = v3_scale(normal, -1.0f);
    if (v3_dot(normal, primary_ray->direction) > 0.0f) normal = v3_scale(normal, -1.0f);

    const float3_t light_pos = {4.0f, 6.0f, -4.0f};
    float3_t to_light = v3_sub(light_pos, hit_pos);
    float light_dist = v3_length(to_light);
    float3_t light_dir = v3_scale(to_light, 1.0f / light_dist);

    float n_dot_l = fmaxf(v3_dot(normal, light_dir), 0.0f);
    int shadowed = trace_shadow(primary_ray, hit_pos, normal, light_pos, bvh_root);

    float ambient = 0.12f;
    float diffuse = shadowed ? 0.0f : 0.80f * n_dot_l;
    float specular = 0.0f;

    if (!shadowed) {
        float3_t view_dir = v3_norm(v3_sub(camera->position, hit_pos));
        float3_t half_vec = v3_norm(v3_add(light_dir, view_dir));
        specular = 0.20f * powf(fmaxf(v3_dot(normal, half_vec), 0.0f), 64.0f);
    }

    return v3_scale((float3_t){0.72f, 0.58f, 0.42f}, clamp01(ambient + diffuse + specular));
}

static inline float gamma_correct(float val) { return powf(clamp01(val), 1.0f / 2.2f); }

// ============================================================
// Main Render Routine
// ============================================================

//iterates through every pixel in the image to generate primary camera rays, runs BVH traversal, computes anti-aliased pixel colors, and writes the final output to a PPM file
int render_bvh(tri_t *triangles, uint32_t tri_count, bvh_node_t *bvh_root, uint32_t bvh_node_count,
               float yaw_deg, float pitch_deg, uint32_t rays_per_pixel, uint32_t *total_rays) {
    uint32_t side_samples = (uint32_t)(sqrtf((float)rays_per_pixel) + 0.5f);
    if (side_samples * side_samples != rays_per_pixel || rays_per_pixel == 0) {
        printf("Warning: rays_per_pixel (%u) is not a perfect square. Defaulting to 1 ray/pixel.\n", rays_per_pixel);
        side_samples = rays_per_pixel = 1;
    }

    camera_t camera = make_camera(triangles_bounds(triangles, tri_count), yaw_deg, pitch_deg);
    
    rtu_scene_t scene;
    rtu_scene_bind(&scene, bvh_root, bvh_node_count, tri_count, triangles);

    FILE *file = fopen(OUTPUT_FILE, "wb");
    if (!file) { perror("Failed to open output file"); return -1; }
    fprintf(file, "P6\n%d %d\n255\n", IMAGE_WIDTH, IMAGE_HEIGHT);

    *total_rays = 0;
    uint64_t total_primary_hits = 0, total_shadow_rays = 0;
    float sub_step = 1.0f / (float)side_samples;
    float inv_samples = 1.0f / (float)rays_per_pixel;

    for (int y = 0; y < IMAGE_HEIGHT; y++) {
        for (int x = 0; x < IMAGE_WIDTH; x++) {
            float3_t accum_color = {0.0f, 0.0f, 0.0f};

            for (uint32_t sy = 0; sy < side_samples; sy++) {
                for (uint32_t sx = 0; sx < side_samples; sx++) {
                    float px = (float)x + (sx + 0.5f) * sub_step;
                    float py = (float)y + (sy + 0.5f) * sub_step;

                    ray_request_t ray = generate_ray(&camera, px, py, *total_rays, RTU_BVH_BASE);
#ifdef BRUTE_FORCE
                    traversal_result_t res = traverse_bruteforce((traversal_request_t){.ray = ray});
#else
                    traversal_result_t res = traverse_bvh((traversal_request_t){.ray = ray});
#endif
                    (*total_rays)++;

                    if (isfinite(res.distance)) {
                        total_primary_hits++;
                        total_shadow_rays++;
                    }

                    accum_color = v3_add(accum_color, shade_hit(&camera, &ray, &res, RTU_BVH_BASE));
                }
            }

            float3_t col = v3_scale(accum_color, inv_samples);
            uint8_t rgb[3] = {
                (uint8_t)(gamma_correct(col.x) * 255.0f),
                (uint8_t)(gamma_correct(col.y) * 255.0f),
                (uint8_t)(gamma_correct(col.z) * 255.0f)
            };
            fwrite(rgb, 1, 3, file);
        }
    }

    fclose(file);
    printf("Rendered %u primary rays (%llu hits) to %s [Yaw: %.1f, Pitch: %.1f, AA: %ux (%u spp)]\n",
           *total_rays, (unsigned long long)total_primary_hits, OUTPUT_FILE, yaw_deg, pitch_deg, rays_per_pixel, side_samples);
    printf("Generated %llu shadow rays\n", (unsigned long long)total_shadow_rays);

    return 0;
}