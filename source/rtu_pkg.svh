`ifndef RTU_PKG_SVH
`define RTU_PKG_SVH

// package rtu_pkg;

    //=====================================
    //parameters
    //=====================================
    localparam int STACK_DEPTH = 16;

    //stack_ptr is a COUNT, so it must represent 0..STACK_DEPTH.
    localparam int STACK_PTR_WIDTH = $clog2(STACK_DEPTH + 1);

    //=====================================
    //basic types
    //=====================================

`ifdef FP //a bit corny, but works
    //raw IEEE-754 single-precision floating-point representation.
    typedef struct packed {
        logic sign;
        logic [7:0] exponent;
        logic [22:0] mantissa;
    } fp32_t;
`else
    typedef struct packed {
        logic [31:0] data;
    } fp32_t;
`endif

    typedef logic [31:0] addr_t;

    typedef logic [15:0] ray_id_t;
    typedef logic [15:0] primitive_id_t;

    //=====================================
    //vector / geometry types
    //=====================================

    typedef struct packed {
        fp32_t x;
        fp32_t y;
        fp32_t z;
    } float3_t;


    typedef struct packed {
        float3_t corner_a;
        float3_t corner_b;
    } aabb_t;

    //=====================================
    //triangle
    //=====================================

    typedef struct packed {
        primitive_id_t primitive_id;
        float3_t vertex1, vertex2, vertex3;
    } triangle_t;

    // ============================================================
    // BVH Node
    //
    // Exactly 256 bits:
    //
    //   192-bit AABB
    //    32-bit left_first
    //    32-bit tri_count
    //
    // Internal node:
    //   tri_count == 0
    //   left_first = address of left child
    //   right child = left_first + sizeof(bvh_node_t)
    //
    // Leaf:
    //   tri_count > 0
    //   left_first = address of first triangle
    // ============================================================

    typedef struct packed {
        aabb_t box;
        addr_t left_first;
        logic [31:0] tri_count;
    } bvh_node_t;

    //=====================================
    //ray geometry
    //=====================================

    typedef struct packed {
        float3_t origin;
        float3_t direction;
        float3_t inv_direction;

        fp32_t t_min;
        fp32_t t_max;

    } ray_geometry_t;

    //=====================================
    //top-level ray request
    //=====================================

    typedef struct packed {
        ray_id_t ray_id;
        // addr_t bvh_root;
        logic [31:0] control;

        float3_t origin;
        float3_t direction;

        // fp32_t t_min;
        // fp32_t t_max;

    } ray_request_t;


    //=====================================
    //AABB intersection request / result
    //=====================================

    typedef struct packed {
        logic [7:0] context_id;
        ray_geometry_t ray;
        aabb_t box;
    } aabb_request_t;


    typedef struct packed {
        logic [7:0] context_id;
        logic hit;
        fp32_t t_near;
        fp32_t t_far;
    } aabb_result_t;

    //=====================================
    //triangle intersection request / result
    //=====================================

    typedef struct packed {
        logic [7:0] context_id;
        ray_geometry_t ray;
        triangle_t triangle;
    } tri_request_t;


    typedef struct packed {
        logic [7:0] context_id;
        logic hit;
        primitive_id_t primitive_id;

        fp32_t t;

        //barycentric coordinates.
        fp32_t u;
        fp32_t v;

        logic facing_front;
    } tri_result_t;

    //=====================================
    //traversal request / result
    //=====================================

    typedef struct packed {
        ray_request_t ray;
    } traversal_request_t;


    typedef struct packed {
        primitive_id_t primitive_id;
        fp32_t distance;
        //barycentric coordinates.
        fp32_t u;
        fp32_t v;
    } traversal_result_t;

    // ============================================================
    // BVH Traversal Stack Entry
    //
    // AABB intersection is performed before a node is pushed.
    // Therefore, the traversal stack retains the resulting
    // t_near value and does not need to re-test the node AABB
    // when the node is popped.
    //
    // This is the software optimization currently used by the
    // reference implementation.
    // ============================================================

    typedef struct packed {
        addr_t node_addr;
        fp32_t t_near;
    } bvh_stack_entry_t;

    // ============================================================
    // In-flight Ray Context
    //
    // This is persistent state maintained while the RTU traverses
    // the BVH.
    // ============================================================

    typedef struct packed {
        logic [7:0] context_id;

        //original ray geometry.
        float3_t origin;
        float3_t direction;
        float3_t inv_direction;

        fp32_t t_min;
        fp32_t t_max;

        //current closest intersection.
        logic          hit;
        logic          facing_front;
        primitive_id_t primitive_id;
        fp32_t         distance;

        //barycentric coordinates of closest hit.
        fp32_t bary_u;
        fp32_t bary_v;

        //GPU ray identification.
        ray_id_t ray_id;

        //root of this ray's BVH traversal.
        addr_t bvh_root;

        //reserved traversal/control bits.
        logic [31:0] control;

        //number of valid entries currently in traversal stack.
        logic [STACK_PTR_WIDTH-1:0] stack_ptr;

    } ray_context_t;

    // //traversal Result
    // typedef struct packed {
    //     logic          hit;

    //     primitive_id_t primitive_id;
    //     instance_id_t  instance_id;

    //     fp32_t hit_distance;

    //     ray_id_t ray_id;

    //     //barycentric coordinates.
    //     fp32_t u;
    //     fp32_t v;

    // } hit_result_t;

// endpackage : rtu_pkg

`endif // RTU_PKG_SVH
