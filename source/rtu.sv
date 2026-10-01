`default_nettype none

module rtu
    import rtu_pkg::*;
(
    input logic clk,
    input logic n_rst,

    //Ray Request Interface
    ray_request_t ray_request;

    //SRAM
    input logic mem_busy;
    input logic [255:0] mem_rdata; //byte-addressed
    // input logic mem_rvalid;
    output logic mem_ren;
    output logic mem_wen;
    output addr_t mem_addr;
    output logic [255:0] mem_wdata;
);

    

/*
    for MVP, support
    triangles only
    binary BVH
    static scenes
    one-level BVH
    FP32
    closest-hit traversal
    no recursion
    no instancing
    no motion blur
    no any-hit shaders
    no programmable intersection shaders

    1. ray/triangle intersection
        use Moller-Trumbore
            given ray = 0 + tD and triangle V0, V1, V2, calculate
            barycentric coordinates u, v, and distance t
    2. ray/AABB intersection
        use slab intersection
            for each axis:
                t0 = (box_min - ray_origin) / ray_direction
                t1 = (box_max - ray_origin) / ray_direction
            then:
                t_near = max(x_near, y_near, z_near)
                t_far = min(x_far, y_far, z_far)
            intersection exists when:
                t_near <= t_far
                t_far >= t_min
                t_near <= t_max
        becomes deeply pipelined hardware unit
    3. BVH traversal
        this is the main workloads RT hardware accellerates
        according to NVIDIA

        example:

        struct BVHNode {
            float min_x;
            float min_y;
            float min_z;

            float max_x;
            float max_y;
            float max_z;

            uint32 child0;
            uint32 child1;
        };

        stack[0] = root
        while stack not empty
            node = pop()
            if !AABB(ray,node): continue
            if internal: push(child0) push(child1)
            else (if leaf): test triangles

        if both children intersect, visit closer child first
        to maintain closest_t and reject nodes with node.t_near >
        closest_t

    4. BVH construction
        https://www.youtube.com/watch?v=LAxHQZ8RjQ4
        morton codes
    5. GPU ray divergence
        rays don't traverse the same BVH nodes
        Must support many independent ray contexts

        example:
        typedef struct packed {
            logic [31:0] origin_x;
            logic [31:0] origin_y;
            logic [31:0] origin_z;

            logic [31:0] dir_x;
            logic [31:0] dir_y;
            logic [31:0] dir_z;

            logic [31:0] t_min;
            logic [31:0] closest_t;

            logic [31:0] primitive_id;

            logic [7:0]  stack_ptr;
        } ray_context_t;

    5 pieces to make testable
    1. AABB intersection unit
    2. Triangle intersection unit
    3. BVH traversal controller
    4. Ray context/stack storage
    5. GPU interface
*/

endmodule