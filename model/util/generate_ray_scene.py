#!/usr/bin/env python3
"""Generate spatially coherent triangle scenes in the project's .tri format.

Each output line contains nine whitespace-separated floats:
    v0.x v0.y v0.z v1.x v1.y v1.z v2.x v2.y v2.z

Coordinates use Y-up, with the object layout spread across the XZ plane.
"""

import argparse
import heapq
import json
import math
import random
from pathlib import Path

Vec3 = tuple[float, float, float]
Triangle = tuple[Vec3, Vec3, Vec3]


def add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a: Vec3, s: float) -> Vec3:
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def length2(a: Vec3) -> float:
    return dot(a, a)


def triangle_area2(tri: Triangle) -> float:
    return length2(cross(sub(tri[1], tri[0]), sub(tri[2], tri[0])))


def triangle_area(tri: Triangle) -> float:
    return 0.5 * math.sqrt(triangle_area2(tri))


def midpoint(a: Vec3, b: Vec3) -> Vec3:
    return ((a[0] + b[0]) * 0.5,
            (a[1] + b[1]) * 0.5,
            (a[2] + b[2]) * 0.5)


# ---------------------------------------------------------------------------
# Base meshes
# ---------------------------------------------------------------------------


def make_box() -> list[Triangle]:
    """Unit box centered at the origin; 12 triangles."""
    v = [
        (-1.0, -1.0, -1.0), ( 1.0, -1.0, -1.0),
        ( 1.0,  1.0, -1.0), (-1.0,  1.0, -1.0),
        (-1.0, -1.0,  1.0), ( 1.0, -1.0,  1.0),
        ( 1.0,  1.0,  1.0), (-1.0,  1.0,  1.0),
    ]
    faces = [
        # -Z, +Z
        (0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7),
        # -X, +X
        (0, 4, 7), (0, 7, 3), (1, 2, 6), (1, 6, 5),
        # -Y, +Y
        (0, 1, 5), (0, 5, 4), (3, 7, 6), (3, 6, 2),
    ]
    return [(v[a], v[b], v[c]) for a, b, c in faces]


def normalize(v: Vec3) -> Vec3:
    n = math.sqrt(length2(v))
    if n == 0.0:
        raise ValueError("Cannot normalize a zero-length vector")
    return mul(v, 1.0 / n)


def make_icosphere(subdivisions: int) -> list[Triangle]:
    """Generate an approximately spherical icosphere.

    The base icosahedron has 20 faces; each subdivision level creates 4x as
    many faces. Vertices are projected back onto the unit sphere.
    """
    phi = (1.0 + math.sqrt(5.0)) * 0.5
    vertices = [
        (-1, phi, 0), (1, phi, 0), (-1, -phi, 0), (1, -phi, 0),
        (0, -1, phi), (0, 1, phi), (0, -1, -phi), (0, 1, -phi),
        (phi, 0, -1), (phi, 0, 1), (-phi, 0, -1), (-phi, 0, 1),
    ]
    vertices = [normalize(tuple(map(float, v))) for v in vertices]
    faces = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]

    for _ in range(subdivisions):
        midpoint_cache: dict[tuple[int, int], int] = {}

        def midpoint_index(i: int, j: int) -> int:
            key = (min(i, j), max(i, j))
            if key not in midpoint_cache:
                p = normalize(midpoint(vertices[i], vertices[j]))
                midpoint_cache[key] = len(vertices)
                vertices.append(p)
            return midpoint_cache[key]

        refined = []
        for a, b, c in faces:
            ab = midpoint_index(a, b)
            bc = midpoint_index(b, c)
            ca = midpoint_index(c, a)
            refined.extend([
                (a, ab, ca),
                (b, bc, ab),
                (c, ca, bc),
                (ab, bc, ca),
            ])
        faces = refined

    return [(vertices[a], vertices[b], vertices[c]) for a, b, c in faces]


def make_cylinder(segments: int) -> list[Triangle]:
    """Unit cylinder centered at the origin; includes side walls and caps."""
    bottom = []
    top = []
    for i in range(segments):
        angle = 2.0 * math.pi * i / segments
        x = math.cos(angle)
        z = math.sin(angle)
        bottom.append((x, -1.0, z))
        top.append((x, 1.0, z))

    triangles: list[Triangle] = []
    bottom_center = (0.0, -1.0, 0.0)
    top_center = (0.0, 1.0, 0.0)
    for i in range(segments):
        j = (i + 1) % segments
        # Side quad
        triangles.extend([
            (bottom[i], bottom[j], top[j]),
            (bottom[i], top[j], top[i]),
        ])
        # End caps
        triangles.append((top_center, top[i], top[j]))
        triangles.append((bottom_center, bottom[j], bottom[i]))
    return triangles


def make_quad(a: Vec3, b: Vec3, c: Vec3, d: Vec3) -> list[Triangle]:
    return [(a, b, c), (a, c, d)]


def transform_mesh(
    mesh: list[Triangle],
    center: Vec3,
    scale_xyz: Vec3,
    yaw_radians: float,
) -> list[Triangle]:
    """Scale, rotate around Y, and translate a local-space mesh."""
    cs = math.cos(yaw_radians)
    sn = math.sin(yaw_radians)

    def transform(p: Vec3) -> Vec3:
        x = p[0] * scale_xyz[0]
        y = p[1] * scale_xyz[1]
        z = p[2] * scale_xyz[2]
        xr = x * cs + z * sn
        zr = -x * sn + z * cs
        return (xr + center[0], y + center[1], zr + center[2])

    return [tuple(transform(p) for p in tri) for tri in mesh]


# ---------------------------------------------------------------------------
# Triangle-count adjustment
# ---------------------------------------------------------------------------


def split_triangle(tri: Triangle) -> tuple[Triangle, Triangle]:
    """Bisect the longest edge; the two children exactly cover the parent."""
    a, b, c = tri
    edges = [
        (length2(sub(a, b)), a, b, c),
        (length2(sub(b, c)), b, c, a),
        (length2(sub(c, a)), c, a, b),
    ]
    _, p0, p1, opposite = max(edges, key=lambda item: item[0])
    m = midpoint(p0, p1)
    return (p0, m, opposite), (m, p1, opposite)


def refine_to_count(mesh: list[Triangle], target_count: int) -> list[Triangle]:
    """Refine a mesh to exactly target_count without changing its silhouette.

    Refinement is area-prioritized. Splitting an edge does not move geometry;
    adjacent faces may contain T-junctions, but the triangle coverage is
    unchanged and there are no holes or overlapping child triangles.
    """
    if target_count < len(mesh):
        raise ValueError(
            f"Triangle budget {target_count} is smaller than base mesh "
            f"({len(mesh)} triangles)"
        )

    heap = []
    serial = 0
    for tri in mesh:
        area_key = triangle_area2(tri)
        if area_key <= 1e-20:
            raise ValueError("Base mesh contains a degenerate triangle")
        heapq.heappush(heap, (-area_key, serial, tri))
        serial += 1

    while len(heap) < target_count:
        _, _, tri = heapq.heappop(heap)
        t0, t1 = split_triangle(tri)
        heapq.heappush(heap, (-triangle_area2(t0), serial, t0))
        serial += 1
        heapq.heappush(heap, (-triangle_area2(t1), serial, t1))
        serial += 1

    return [entry[2] for entry in heap]


def allocate_counts(meshes: list[list[Triangle]], total_count: int) -> list[int]:
    """Allocate a total triangle budget, weighted by each mesh's surface area."""
    base = [len(mesh) for mesh in meshes]
    extra = total_count - sum(base)
    if extra < 0:
        raise ValueError("Not enough triangles for the requested base meshes")
    if not meshes:
        if total_count != 0:
            raise ValueError("No meshes available for the triangle budget")
        return []
    if extra == 0:
        return base

    weights = [sum(triangle_area(t) for t in mesh) for mesh in meshes]
    weight_sum = sum(weights)
    if weight_sum <= 0.0:
        weights = [1.0] * len(meshes)
        weight_sum = float(len(meshes))

    quotas = [extra * w / weight_sum for w in weights]
    additions = [int(math.floor(q)) for q in quotas]
    remainder = extra - sum(additions)
    order = sorted(
        range(len(meshes)),
        key=lambda i: quotas[i] - additions[i],
        reverse=True,
    )
    for i in order[:remainder]:
        additions[i] += 1

    return [base[i] + additions[i] for i in range(len(meshes))]


# ---------------------------------------------------------------------------
# Object placement and scene construction
# ---------------------------------------------------------------------------


def grid_positions(count: int, spacing: float) -> list[tuple[float, float]]:
    cols = math.ceil(math.sqrt(count))
    rows = math.ceil(count / cols)
    result = []
    for i in range(count):
        col = i % cols
        row = i // cols
        x = (col - 0.5 * (cols - 1)) * spacing
        z = (row - 0.5 * (rows - 1)) * spacing
        result.append((x, z))
    return result


def random_positions(
    count: int,
    spacing: float,
    min_separation: float,
    rng: random.Random,
) -> list[tuple[float, float]]:
    """Jittered random layout with a nominal minimum center separation."""
    if count == 1:
        return [(0.0, 0.0)]

    extent = max(spacing, spacing * math.sqrt(count) * 0.65)
    min_sep2 = min_separation * min_separation
    points: list[tuple[float, float]] = []

    for _ in range(count):
        for _attempt in range(5000):
            p = (rng.uniform(-extent, extent), rng.uniform(-extent, extent))
            if all((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 >= min_sep2
                   for q in points):
                points.append(p)
                break
        else:
            # Dense requests can exhaust rejection sampling; add a grid point.
            fallback = grid_positions(count, spacing)
            points.append(fallback[len(points)])
    return points


def clustered_positions(
    count: int,
    spacing: float,
    cluster_count: int,
    cluster_radius: float,
    rng: random.Random,
) -> list[tuple[float, float]]:
    cluster_count = max(1, min(cluster_count, count))
    centers = grid_positions(cluster_count, spacing * 3.0)
    points = []
    for i in range(count):
        cx, cz = centers[i % cluster_count]
        # Uniform sampling over a disk, rather than concentrating at its center.
        radius = cluster_radius * math.sqrt(rng.random())
        angle = rng.uniform(0.0, 2.0 * math.pi)
        points.append((cx + radius * math.cos(angle),
                       cz + radius * math.sin(angle)))
    return points


def make_positions(args: argparse.Namespace, count: int,
                   spacing: float, rng: random.Random) -> list[tuple[float, float]]:
    if args.layout == "grid":
        return grid_positions(count, spacing)
    if args.layout == "random":
        min_sep = args.min_separation
        if min_sep is None:
            min_sep = spacing * 0.60
        return random_positions(count, spacing, min_sep, rng)
    radius = args.cluster_radius
    if radius is None:
        radius = spacing * 0.65
    return clustered_positions(count, spacing, args.clusters, radius, rng)


def make_room_shell(
    positions: list[tuple[float, float]],
    object_size: float,
) -> list[Triangle]:
    """Open-front room: floor, back wall, and two side walls (8 triangles)."""
    margin = 2.0 * object_size
    xmin = min(x for x, _ in positions) - margin
    xmax = max(x for x, _ in positions) + margin
    zmin = min(z for _, z in positions) - margin
    zmax = max(z for _, z in positions) + margin
    height = max(4.0 * object_size, 2.5 * object_size)

    shell = []
    # Floor
    shell += make_quad((xmin, 0.0, zmin), (xmax, 0.0, zmin),
                       (xmax, 0.0, zmax), (xmin, 0.0, zmax))
    # Back wall
    shell += make_quad((xmin, 0.0, zmax), (xmax, 0.0, zmax),
                       (xmax, height, zmax), (xmin, height, zmax))
    # Left and right walls
    shell += make_quad((xmin, 0.0, zmin), (xmin, 0.0, zmax),
                       (xmin, height, zmax), (xmin, height, zmin))
    shell += make_quad((xmax, 0.0, zmax), (xmax, 0.0, zmin),
                       (xmax, height, zmin), (xmax, height, zmax))
    return shell


def generate_random_volume(count: int, scale: float,
                           rng: random.Random) -> list[Triangle]:
    """Original pathological workload: independent triangles in one sphere."""
    def point() -> Vec3:
        while True:
            x = rng.uniform(-1.0, 1.0)
            y = rng.uniform(-1.0, 1.0)
            z = rng.uniform(-1.0, 1.0)
            if x * x + y * y + z * z <= 1.0:
                return (x * scale, y * scale, z * scale)

    triangles = []
    while len(triangles) < count:
        a, b, c = point(), point(), point()
        tri = (a, b, c)
        if triangle_area2(tri) > 1e-8:
            triangles.append(tri)
    return triangles


def generate_object_scene(
    args: argparse.Namespace,
    rng: random.Random,
) -> tuple[list[Triangle], int, int]:
    scale = args.scale
    object_size = args.object_size if args.object_size is not None else 0.55 * scale
    spacing = args.spacing if args.spacing is not None else 3.0 * scale
    fixed_triangles = 8 if args.scene == "room" else (0 if args.no_floor else 2)
    object_budget = args.count - fixed_triangles
    if object_budget <= 0:
        raise ValueError(
            f"Count must exceed the {fixed_triangles} fixed floor/room triangles"
        )

    requested_objects = args.objects
    sphere_subdiv = args.sphere_subdivisions

    def choose_types(n: int) -> list[str]:
        if args.scene == "boxes":
            return ["box"] * n
        if args.scene == "spheres":
            return ["sphere"] * n
        if args.scene == "cylinders":
            return ["cylinder"] * n
        result = []
        for _ in range(n):
            r = rng.random()
            if r < args.sphere_fraction:
                result.append("sphere")
            elif r < args.sphere_fraction + args.cylinder_fraction:
                result.append("cylinder")
            else:
                result.append("box")
        return result

    # Keep the requested total count exact. If the base meshes do not fit,
    # reduce object count first, then sphere tessellation if necessary.
    object_count = requested_objects
    types = choose_types(object_count)
    while True:
        types = types[:object_count]
        sphere_template = make_icosphere(sphere_subdiv)
        cylinder_template = make_cylinder(args.cylinder_segments)
        base_counts = [
            len(sphere_template) if t == "sphere" else
            len(cylinder_template) if t == "cylinder" else 12
            for t in types
        ]
        if sum(base_counts) <= object_budget:
            break
        if object_count > 1:
            object_count -= 1
            continue
        if args.scene not in ("boxes", "cylinders") and sphere_subdiv > 0 and "sphere" in types:
            sphere_subdiv -= 1
            continue
        if args.scene in ("mixed", "room") and len(types) == 1 and types[0] != "box":
            types = ["box"]
            base_counts = [12]
            if sum(base_counts) <= object_budget:
                break
        raise ValueError(
            f"Count={args.count} is too small for this scene; need at least "
            f"{fixed_triangles + min(base_counts)} triangles"
        )

    positions = make_positions(args, object_count, spacing, rng)
    meshes: list[list[Triangle]] = []

    for i, (kind, (x, z)) in enumerate(zip(types, positions)):
        size = object_size * rng.uniform(1.0 - args.size_jitter,
                                          1.0 + args.size_jitter)
        if kind == "sphere":
            local_mesh = sphere_template
            sx = sy = sz = size
            center_y = size
        elif kind == "cylinder":
            local_mesh = cylinder_template
            sx = size * rng.uniform(0.75, 1.25)
            sy = size * rng.uniform(0.8, 1.6)
            sz = sx
            center_y = sy
        else:
            local_mesh = make_box()
            # A range of aspect ratios is more mesh-like than identical cubes.
            sx = size * rng.uniform(0.65, 1.35)
            sy = size * rng.uniform(0.65, 1.45)
            sz = size * rng.uniform(0.65, 1.35)
            center_y = sy
        yaw = math.radians(rng.uniform(-args.rotation_deg,
                                       args.rotation_deg))
        meshes.append(transform_mesh(local_mesh, (x, center_y, z),
                                     (sx, sy, sz), yaw))

    targets = allocate_counts(meshes, object_budget)
    triangles: list[Triangle] = []
    for mesh, target in zip(meshes, targets):
        triangles.extend(refine_to_count(mesh, target))

    if args.scene == "room":
        triangles.extend(make_room_shell(positions, object_size))
    elif not args.no_floor:
        extent = max(
            max(abs(x), abs(z)) for x, z in positions
        ) + 3.0 * object_size
        triangles.extend(make_quad(
            (-extent, 0.0, -extent), (extent, 0.0, -extent),
            (extent, 0.0, extent), (-extent, 0.0, extent),
        ))

    return triangles, object_count, sphere_subdiv


# ---------------------------------------------------------------------------
# Output and command line
# ---------------------------------------------------------------------------


def geometry_stats(triangles: list[Triangle]) -> dict:
    points = [p for tri in triangles for p in tri]
    mins = [min(p[i] for p in points) for i in range(3)]
    maxs = [max(p[i] for p in points) for i in range(3)]
    areas = [triangle_area(t) for t in triangles]
    return {
        "triangle_count": len(triangles),
        "bounds": {
            "min": mins,
            "max": maxs,
        },
        "surface_area": sum(areas),
        "triangle_area_min": min(areas),
        "triangle_area_max": max(areas),
        "triangle_area_average": sum(areas) / len(areas),
    }


def write_tri(path: Path, triangles: list[Triangle]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for tri in triangles:
            values = [coord for vertex in tri for coord in vertex]
            f.write(" ".join(f"{v:.9f}" for v in values) + "\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate a ray-tracing .tri scene with controllable spatial structure."
    )
    parser.add_argument("count", type=int, help="Exact number of output triangles")
    parser.add_argument("output", help="Output .tri filename")
    parser.add_argument(
        "--scene",
        choices=("mixed", "boxes", "spheres", "cylinders", "room", "random-volume"),
        default="mixed",
        help="Geometry workload; random-volume preserves the original stress test (default: mixed)",
    )
    parser.add_argument("--scale", type=float, default=1.0,
                        help="Global scene scale (default: 1.0)")
    parser.add_argument("--seed", type=int, default=None,
                        help="Random seed for reproducible geometry")
    parser.add_argument("--objects", type=int, default=16,
                        help="Number of spatially separate objects (default: 16)")
    parser.add_argument("--object-size", type=float, default=None,
                        help="Nominal object radius/half-extent; default: 0.55 * scale")
    parser.add_argument("--spacing", type=float, default=None,
                        help="Grid spacing / nominal object separation; default: 3 * scale")
    parser.add_argument("--layout", choices=("grid", "random", "clustered"),
                        default="grid", help="Object placement pattern (default: grid)")
    parser.add_argument("--clusters", type=int, default=4,
                        help="Number of groups for --layout clustered (default: 4)")
    parser.add_argument("--cluster-radius", type=float, default=None,
                        help="Cluster radius; default: 0.65 * spacing")
    parser.add_argument("--size-jitter", type=float, default=0.15,
                        help="Random object size variation in [0, 1); default: 0.15")
    parser.add_argument("--rotation-deg", type=float, default=30.0,
                        help="Maximum absolute random object yaw in degrees (default: 30)")
    parser.add_argument("--sphere-subdivisions", type=int, default=2,
                        help="Base icosphere subdivisions, 0-4 (default: 2; 320 base triangles)")
    parser.add_argument("--sphere-fraction", type=float, default=0.4,
                        help="Sphere fraction in mixed/room scenes (default: 0.4)")
    parser.add_argument("--cylinder-fraction", type=float, default=0.2,
                        help="Cylinder fraction in mixed/room scenes (default: 0.2)")
    parser.add_argument("--cylinder-segments", type=int, default=12,
                        help="Cylinder circumference segments (default: 12)")
    parser.add_argument("--min-separation", type=float, default=None,
                        help="Minimum object-center separation for random layout; default: 0.6 * spacing")
    parser.add_argument("--no-floor", action="store_true",
                        help="Do not add the two-triangle ground plane (ignored by room)")
    parser.add_argument("--stats-json", default=None,
                        help="Optional path for a JSON scene summary")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.count <= 0:
        parser.error("count must be positive")
    if args.scale <= 0.0:
        parser.error("--scale must be positive")
    if args.objects <= 0:
        parser.error("--objects must be positive")
    if args.clusters <= 0:
        parser.error("--clusters must be positive")
    if not 0.0 <= args.size_jitter < 1.0:
        parser.error("--size-jitter must be in [0, 1)")
    if args.sphere_subdivisions < 0 or args.sphere_subdivisions > 4:
        parser.error("--sphere-subdivisions must be between 0 and 4")
    if not 0.0 <= args.sphere_fraction <= 1.0:
        parser.error("--sphere-fraction must be in [0, 1]")
    if not 0.0 <= args.cylinder_fraction <= 1.0:
        parser.error("--cylinder-fraction must be in [0, 1]")
    if args.sphere_fraction + args.cylinder_fraction > 1.0:
        parser.error("--sphere-fraction + --cylinder-fraction must be <= 1")
    if args.cylinder_segments < 3 or args.cylinder_segments > 128:
        parser.error("--cylinder-segments must be between 3 and 128")
    if args.min_separation is not None and args.min_separation < 0.0:
        parser.error("--min-separation must be non-negative")
    if args.rotation_deg < 0.0:
        parser.error("--rotation-deg must be non-negative")
    if args.object_size is not None and args.object_size <= 0.0:
        parser.error("--object-size must be positive")
    if args.spacing is not None and args.spacing <= 0.0:
        parser.error("--spacing must be positive")
    if args.cluster_radius is not None and args.cluster_radius < 0.0:
        parser.error("--cluster-radius must be non-negative")

    rng = random.Random(args.seed)

    try:
        if args.scene == "random-volume":
            triangles = generate_random_volume(args.count, args.scale, rng)
            object_count = 0
            sphere_subdiv = None
        else:
            triangles, object_count, sphere_subdiv = generate_object_scene(args, rng)
    except ValueError as exc:
        parser.error(str(exc))

    if len(triangles) != args.count:
        parser.error(f"Internal error: generated {len(triangles)} triangles, expected {args.count}")

    output = Path(args.output)
    write_tri(output, triangles)
    stats = geometry_stats(triangles)
    stats.update({
        "scene": args.scene,
        "seed": args.seed,
        "objects": object_count,
        "layout": None if args.scene == "random-volume" else args.layout,
        "sphere_subdivisions_used": sphere_subdiv,
    })

    print(f"Generated {len(triangles)} triangles")
    print(f"Scene:   {args.scene}")
    if object_count:
        print(f"Objects: {object_count}")
        if object_count != args.objects:
            print(f"Note:    object count reduced from {args.objects} to fit the triangle budget")
        print(f"Layout:  {args.layout}")
        if sphere_subdiv is not None and args.scene not in ("boxes", "cylinders"):
            print(f"Sphere subdivisions used: {sphere_subdiv}")
    print(f"Output:  {output}")
    print("Bounds:  " + "  ".join(
        f"[{stats['bounds']['min'][i]:.3f}, {stats['bounds']['max'][i]:.3f}]"
        for i in range(3)
    ) + "  (x, y, z)")
    print(f"Area:    {stats['surface_area']:.3f} total; "
          f"{stats['triangle_area_average']:.6f} average per triangle")
    if args.stats_json:
        stats_path = Path(args.stats_json)
        stats_path.write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
        print(f"Stats:   {stats_path}")


if __name__ == "__main__":
    main()
