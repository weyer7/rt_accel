#!/usr/bin/env python3
"""Render a PPM image from traversal_controller_tb RTL results.

Pipeline:
  1. Export the input triangle mesh to bvh_nodes.hex / triangles.hex.
  2. Generate camera rays and quantize them to the testbench's Q16.16 format.
  3. Run the C reference runner to create expected result records.
  4. Run the existing Icarus Make target. The updated testbench executes every
     ray through traversal_controller and prints each actual RTL result.
  5. Shade those RTL results in Python and write a P6 PPM image.

No secondary/shadow rays are generated. The direct-light shading follows the
provided C renderer's Blinn-Phong model with ambient + diffuse + specular terms.
"""

from __future__ import annotations

import argparse
import math
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Iterable

Q16 = Decimal(65536)
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1
SUMMARY_RE = re.compile(
    r"\[SUMMARY\]\[TEST\s+(\d+)\]\s+C-reference comparison:\s+"
    r"hit=(\d+)\s+prim=(\d+)\s+t=([-+0-9.eE]+)\s+"
    r"u=([-+0-9.eE]+)\s+v=([-+0-9.eE]+)"
)

Vec3 = tuple[float, float, float]


@dataclass(frozen=True)
class Camera:
    position: Vec3
    forward: Vec3
    right: Vec3
    up: Vec3
    fov_y: float


@dataclass(frozen=True)
class Ray:
    ray_id: int
    origin: Vec3
    direction: Vec3
    words: tuple[int, ...]


@dataclass(frozen=True)
class Hit:
    hit: bool
    primitive_id: int
    distance: float
    u: float
    v: float


@dataclass(frozen=True)
class Triangle:
    primitive_id: int
    v0: Vec3
    v1: Vec3
    v2: Vec3


def f32(x: float) -> float:
    """Round an intermediate to IEEE-754 single precision like the C code."""
    return struct.unpack("<f", struct.pack("<f", float(x)))[0]


def v_add(a: Vec3, b: Vec3) -> Vec3:
    return tuple(f32(x + y) for x, y in zip(a, b))  # type: ignore[return-value]


def v_sub(a: Vec3, b: Vec3) -> Vec3:
    return tuple(f32(x - y) for x, y in zip(a, b))  # type: ignore[return-value]


def v_scale(a: Vec3, s: float) -> Vec3:
    return tuple(f32(x * f32(s)) for x in a)  # type: ignore[return-value]


def v_dot(a: Vec3, b: Vec3) -> float:
    p0 = f32(a[0] * b[0])
    p1 = f32(a[1] * b[1])
    p2 = f32(a[2] * b[2])
    return f32(f32(p0 + p1) + p2)


def v_cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        f32(f32(a[1] * b[2]) - f32(a[2] * b[1])),
        f32(f32(a[2] * b[0]) - f32(a[0] * b[2])),
        f32(f32(a[0] * b[1]) - f32(a[1] * b[0])),
    )


def v_length(a: Vec3) -> float:
    return f32(math.sqrt(max(0.0, v_dot(a, a))))


def v_norm(a: Vec3) -> Vec3:
    length = v_length(a)
    if length < 1.0e-8:
        return (0.0, 0.0, 0.0)
    return v_scale(a, f32(1.0 / length))


def q16_raw(value: float | Decimal | str, label: str) -> int:
    try:
        decimal_value = value if isinstance(value, Decimal) else Decimal(str(value))
        raw = int((decimal_value * Q16).quantize(
            Decimal("1"), rounding=ROUND_HALF_UP
        ))
    except (InvalidOperation, ValueError) as exc:
        raise ValueError(f"{label}: cannot quantize {value!r}") from exc
    if raw < INT32_MIN or raw > INT32_MAX:
        raise ValueError(f"{label}: {value} is outside signed Q16.16 range")
    return raw


def signed_q16(raw: int) -> float:
    raw &= 0xFFFFFFFF
    if raw & 0x80000000:
        raw -= 1 << 32
    return raw / 65536.0


def hex32(raw: int) -> str:
    return f"{raw & 0xFFFFFFFF:08x}"


def read_mesh(path: Path) -> list[Triangle]:
    """Read the exporter's input format: nine vertex floats per triangle."""
    values: list[float] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.split("#", 1)[0].replace(",", " ")
        for token in line.split():
            try:
                value = float(token)
            except ValueError as exc:
                raise ValueError(f"{path}:{line_no}: invalid vertex value {token!r}") from exc
            if not math.isfinite(value):
                raise ValueError(f"{path}:{line_no}: mesh values must be finite")
            values.append(value)
    if not values or len(values) % 9:
        raise ValueError(
            f"{path}: expected nine floats per triangle; found {len(values)} values"
        )
    triangles: list[Triangle] = []
    for i in range(0, len(values), 9):
        triangles.append(Triangle(
            primitive_id=len(triangles),
            v0=(values[i], values[i + 1], values[i + 2]),
            v1=(values[i + 3], values[i + 4], values[i + 5]),
            v2=(values[i + 6], values[i + 7], values[i + 8]),
        ))
    return triangles


def mesh_bounds(triangles: Iterable[Triangle]) -> tuple[Vec3, Vec3]:
    tris = list(triangles)
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for tri in tris:
        for vertex in (tri.v0, tri.v1, tri.v2):
            for axis in range(3):
                mins[axis] = min(mins[axis], vertex[axis])
                maxs[axis] = max(maxs[axis], vertex[axis])
    return tuple(mins), tuple(maxs)  # type: ignore[return-value]


def make_camera(bounds: tuple[Vec3, Vec3], yaw_deg: float, pitch_deg: float) -> Camera:
    lo, hi = bounds
    center = v_scale(v_add(lo, hi), 0.5)
    extents = v_sub(hi, lo)
    radius = f32(0.5 * v_length(extents))
    fov_y = f32(math.radians(60.0))
    distance = f32(f32(radius / f32(math.tan(f32(fov_y * 0.5)))) * 0.8)

    # Match DEG2RAD(deg) from the supplied C renderer, including float rounding.
    pi_f = f32(math.pi)
    yaw = f32(f32(f32(yaw_deg) * pi_f) / 180.0)
    pitch = f32(f32(f32(pitch_deg) * pi_f) / 180.0)
    cp, sp = f32(math.cos(pitch)), f32(math.sin(pitch))
    offset = (
        f32(f32(distance * cp) * f32(math.sin(yaw))),
        f32(distance * sp),
        f32(f32(distance * cp) * f32(math.cos(yaw))),
    )
    position = v_add(center, offset)
    forward = v_norm(v_sub(center, position))
    right = v_norm(v_cross(forward, (0.0, 1.0, 0.0)))
    up = v_cross(right, forward)
    return Camera(position, forward, right, up, fov_y)


def make_ray(
    camera: Camera, px: float, py: float, ray_id: int,
    width: int, height: int, t_min: float, t_max: float,
) -> Ray:
    aspect = f32(width / height)
    tan_fov = f32(math.tan(f32(camera.fov_y * 0.5)))
    ndc_x = f32(f32(f32(2.0 * px) / width) - 1.0)
    ndc_y = f32(1.0 - f32(f32(2.0 * py) / height))
    xoff = f32(f32(ndc_x * aspect) * tan_fov)
    yoff = f32(ndc_y * tan_fov)
    direction = v_norm(v_add(camera.forward, v_add(
        v_scale(camera.right, xoff), v_scale(camera.up, yoff)
    )))

    origin_raw = tuple(q16_raw(x, f"ray {ray_id} origin") for x in camera.position)
    direction_raw = tuple(q16_raw(x, f"ray {ray_id} direction") for x in direction)
    inv_raw: list[int] = []
    for axis, component in zip("xyz", direction_raw):
        if component == 0:
            inv_raw.append(0)
        else:
            quantized_direction = Decimal(component) / Q16
            inverse = Decimal(1) / quantized_direction
            inv_raw.append(q16_raw(inverse, f"ray {ray_id} inverse direction {axis}"))

    t_min_raw = q16_raw(t_min, f"ray {ray_id} t_min")
    t_max_raw = q16_raw(t_max, f"ray {ray_id} t_max")
    words = (
        ray_id,
        *origin_raw,
        *direction_raw,
        *inv_raw,
        t_min_raw,
        t_max_raw,
    )
    return Ray(
        ray_id=ray_id,
        origin=tuple(signed_q16(x) for x in origin_raw),  # type: ignore[arg-type]
        direction=tuple(signed_q16(x) for x in direction_raw),  # type: ignore[arg-type]
        words=words,
    )


def write_ray_file(path: Path, rays: list[Ray]) -> None:
    with path.open("w", encoding="ascii", newline="\n") as stream:
        stream.write(f"{len(rays)}\n")
        for ray in rays:
            stream.write(" ".join(hex32(word) for word in ray.words) + "\n")


def read_exported_triangles(path: Path) -> dict[int, Triangle]:
    """Read 10-word records emitted by export_bvh_mem.c / loaded by the TB."""
    lines = [line.strip() for line in path.read_text(encoding="ascii").splitlines()
             if line.strip()]
    if not lines:
        raise ValueError(f"Triangle memory file is empty: {path}")
    count = int(lines[0], 10)
    if len(lines) - 1 != count:
        raise ValueError(
            f"{path}: header declares {count} triangles, found {len(lines) - 1} records"
        )
    result: dict[int, Triangle] = {}
    for index, line in enumerate(lines[1:]):
        fields = line.split()
        if len(fields) != 10:
            raise ValueError(f"{path}: triangle record {index} has {len(fields)} words, expected 10")
        words = [int(field, 16) for field in fields]
        primitive_id = words[0] & 0xFFFF
        coords = [signed_q16(word) for word in words[1:]]
        tri = Triangle(
            primitive_id,
            (coords[0], coords[1], coords[2]),
            (coords[3], coords[4], coords[5]),
            (coords[6], coords[7], coords[8]),
        )
        if primitive_id in result:
            raise ValueError(f"{path}: duplicate primitive_id {primitive_id}")
        result[primitive_id] = tri
    return result


def resolve_program(program: str, project_dir: Path) -> str:
    candidate = Path(program)
    if candidate.is_absolute():
        if not candidate.is_file():
            raise FileNotFoundError(f"Executable not found: {candidate}")
        return str(candidate)
    local = project_dir / candidate
    if local.is_file():
        return str(local.resolve())
    found = shutil.which(program)
    if found:
        return found
    raise FileNotFoundError(
        f"Cannot find {program!r}; provide an executable path or put it on PATH"
    )


def run_command(
    command: list[str], cwd: Path, description: str, *, print_output: bool = True
) -> subprocess.CompletedProcess[str]:
    print(f"\n[RUN] {description}")
    print("       " + " ".join(command))
    completed = subprocess.run(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False,
    )
    if print_output and completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.returncode != 0:
        raise RuntimeError(f"{description} failed with exit status {completed.returncode}")
    return completed


def parse_rtl_results(log: str, expected_count: int) -> list[Hit]:
    by_index: dict[int, Hit] = {}
    for match in SUMMARY_RE.finditer(log):
        test_number = int(match.group(1))
        if test_number < 1000:
            continue
        ray_index = test_number - 1000
        if ray_index >= expected_count:
            continue
        by_index[ray_index] = Hit(
            hit=(int(match.group(2)) != 0),
            primitive_id=int(match.group(3)),
            distance=float(match.group(4)),
            u=float(match.group(5)),
            v=float(match.group(6)),
        )
    missing = [i for i in range(expected_count) if i not in by_index]
    if missing:
        preview = ", ".join(str(i) for i in missing[:12])
        raise RuntimeError(
            f"Testbench returned {len(by_index)}/{expected_count} ray summaries; "
            f"missing indices: {preview}. Check simulation log for timeout/fatal errors."
        )
    return [by_index[i] for i in range(expected_count)]


def clamp01(x: float) -> float:
    return min(1.0, max(0.0, x))


def sky_color(direction: Vec3) -> Vec3:
    t = clamp01(0.5 * (direction[1] + 1.0))
    low = (0.12, 0.16, 0.22)
    high = (0.55, 0.72, 0.95)
    return tuple(low[i] * (1.0 - t) + high[i] * t for i in range(3))  # type: ignore[return-value]


def shade_hit(camera: Camera, ray: Ray, hit: Hit, triangles: dict[int, Triangle], light: Vec3) -> Vec3:
    if not hit.hit:
        return sky_color(ray.direction)
    tri = triangles.get(hit.primitive_id)
    if tri is None:
        raise ValueError(
            f"RTL hit primitive {hit.primitive_id}, but that ID is absent from triangles.hex"
        )

    hit_pos = v_add(ray.origin, v_scale(ray.direction, abs(hit.distance)))
    normal = v_norm(v_cross(v_sub(tri.v1, tri.v0), v_sub(tri.v2, tri.v0)))
    if v_dot(normal, ray.direction) > 0.0:
        normal = v_scale(normal, -1.0)

    to_light = v_sub(light, hit_pos)
    light_distance = v_length(to_light)
    if light_distance < 1.0e-8:
        return (0.72 * 0.12, 0.58 * 0.12, 0.42 * 0.12)
    light_dir = v_scale(to_light, 1.0 / light_distance)
    n_dot_l = max(v_dot(normal, light_dir), 0.0)

    # Secondary shadow rays are intentionally omitted. This shades every
    # visible surface as directly lit, matching the unshadowed C branch.
    ambient = 0.12
    diffuse = 0.80 * n_dot_l
    view_dir = v_norm(v_sub(camera.position, hit_pos))
    half_vec = v_norm(v_add(light_dir, view_dir))
    specular = 0.20 * pow(max(v_dot(normal, half_vec), 0.0), 64.0)
    intensity = clamp01(ambient + diffuse + specular)
    return (0.72 * intensity, 0.58 * intensity, 0.42 * intensity)


def write_ppm(path: Path, width: int, height: int, pixels: list[Vec3]) -> None:
    with path.open("wb") as stream:
        stream.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        for color in pixels:
            rgb = bytes(int(pow(clamp01(c), 1.0 / 2.2) * 255.0) for c in color)
            stream.write(rgb)


def maybe_write_png(ppm_path: Path, png_path: Path) -> bool:
    try:
        from PIL import Image  # type: ignore[import-not-found]
    except ImportError:
        return False
    with Image.open(ppm_path) as image:
        image.save(png_path)
    return True


def build_rays(
    camera: Camera, width: int, height: int, side_samples: int,
    t_min: float, t_max: float,
) -> list[Ray]:
    rays: list[Ray] = []
    substep = 1.0 / side_samples
    for y in range(height):
        for x in range(width):
            for sy in range(side_samples):
                for sx in range(side_samples):
                    px = f32(x + (sx + 0.5) * substep)
                    py = f32(y + (sy + 0.5) * substep)
                    rays.append(make_ray(
                        camera, px, py, len(rays), width, height, t_min, t_max
                    ))
    if len(rays) > 0xFFFF:
        raise ValueError(
            f"{len(rays)} rays exceed the 16-bit ray_id space; reduce resolution or spp"
        )
    return rays


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render an image using actual traversal_controller testbench results."
    )
    parser.add_argument("triangles", type=Path,
                        help="Mesh file: nine floats per triangle, as accepted by export_bvh_mem")
    parser.add_argument("--project-dir", type=Path, default=Path.cwd())
    parser.add_argument("--exporter", default="model/util/export_bvh_mem")
    parser.add_argument("--reference-runner", default="model/util/rtu_reference_runner")
    parser.add_argument("--make", default="make")
    parser.add_argument("--target", default="sim_traversal_controller_src")
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--height", type=int, default=32)
    parser.add_argument("--yaw", type=float, default=140.0)
    parser.add_argument("--pitch", type=float, default=25.0)
    parser.add_argument("--spp", type=int, default=9,
                        help="Square number of samples/pixel (default 9 means 3x3 AA)")
    parser.add_argument("--t-min", type=float, default=0.001)
    parser.add_argument("--t-max", type=float, default=1000.0,
                        help="Finite Q16.16 ray limit; must be below 32768")
    parser.add_argument("--light", type=float, nargs=3, default=(4.0, 6.0, -4.0),
                        metavar=("X", "Y", "Z"))
    parser.add_argument("--output", type=Path, default=Path("armadillo_rtl.ppm"))
    parser.add_argument("--tolerance-lsb", type=int, default=8)
    parser.add_argument("--keep-marker", action="store_true")
    parser.add_argument("--log", type=Path, default=Path("render_simulation.log"))
    parser.add_argument("--no-png", action="store_true",
                        help="Do not also create a PNG when Pillow is installed")
    args = parser.parse_args()

    if args.width < 1 or args.height < 1:
        parser.error("--width and --height must be positive")
    side_samples = math.isqrt(args.spp)
    if side_samples * side_samples != args.spp or args.spp < 1:
        parser.error("--spp must be a positive perfect square (1, 4, 9, 16, ...)")
    if not (0.0 <= args.t_min < args.t_max < 32768.0):
        parser.error("require 0 <= --t-min < --t-max < 32768 for Q16.16")
    if args.tolerance_lsb < 0:
        parser.error("--tolerance-lsb must be nonnegative")

    project_dir = args.project_dir.resolve()
    mesh_path = args.triangles if args.triangles.is_absolute() else project_dir / args.triangles
    mesh_path = mesh_path.resolve()
    if not project_dir.is_dir():
        parser.error(f"project directory does not exist: {project_dir}")
    if not mesh_path.is_file():
        parser.error(f"mesh file does not exist: {mesh_path}")

    try:
        mesh_triangles = read_mesh(mesh_path)
        bounds = mesh_bounds(mesh_triangles)
        camera = make_camera(bounds, args.yaw, args.pitch)
        rays = build_rays(camera, args.width, args.height, side_samples,
                          args.t_min, args.t_max)
        exporter = resolve_program(args.exporter, project_dir)
        reference_runner = resolve_program(args.reference_runner, project_dir)
    except (ValueError, FileNotFoundError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    bvh_file = project_dir / "bvh_nodes.hex"
    tri_file = project_dir / "triangles.hex"
    ray_file = project_dir / "reference_rays.hex"
    result_file = project_dir / "reference_results.hex"
    marker_file = project_dir / ".reference_run.enable"
    log_file = args.log if args.log.is_absolute() else project_dir / args.log
    output_file = args.output if args.output.is_absolute() else project_dir / args.output

    print(f"[SCENE] {len(mesh_triangles)} source triangles; camera yaw={args.yaw:g}, pitch={args.pitch:g}")
    print(f"[RENDER] {args.width}x{args.height}, {args.spp} spp, {len(rays)} primary RTL traversals")
    print("[RENDER] Secondary shadow rays disabled")

    try:
        write_ray_file(ray_file, rays)
        run_command(
            [exporter, str(mesh_path), str(bvh_file), str(tri_file)],
            project_dir, "export BVH and sorted triangle memories",
        )
        exported_triangles = read_exported_triangles(tri_file)
        if not exported_triangles:
            raise RuntimeError("The exported triangle memory contains no triangles")

        run_command(
            [reference_runner, str(bvh_file), str(tri_file), str(ray_file), str(result_file)],
            project_dir, "generate C-reference result records",
        )

        marker_file.write_text(f"{args.tolerance_lsb}\n", encoding="ascii")
        simulation = run_command(
            [args.make, args.target], project_dir,
            "run Icarus traversal-controller simulation", print_output=False,
        )
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_text(simulation.stdout or "", encoding="utf-8")
        summary_matches = len(SUMMARY_RE.findall(simulation.stdout or ""))
        print(f"[SIM] Captured {summary_matches} per-ray RTL summaries; full log: {log_file}")

        if "[REF] PASS:" not in (simulation.stdout or "") and "[REF] FAIL:" not in (simulation.stdout or ""):
            raise RuntimeError(
                "No C-reference summary found in simulation output. Confirm that this "
                "Make target runs the updated traversal_controller_tb with its "
                "reference-file mode enabled."
            )

        hits = parse_rtl_results(simulation.stdout or "", len(rays))
        pixels: list[Vec3] = []
        hit_count = 0
        ray_index = 0
        inv_samples = 1.0 / args.spp
        for _y in range(args.height):
            for _x in range(args.width):
                accum = [0.0, 0.0, 0.0]
                for _sample in range(args.spp):
                    ray = rays[ray_index]
                    hit = hits[ray_index]
                    ray_index += 1
                    if hit.hit:
                        hit_count += 1
                    color = shade_hit(camera, ray, hit, exported_triangles,
                                      tuple(args.light))
                    for channel in range(3):
                        accum[channel] += color[channel]
                pixels.append(tuple(c * inv_samples for c in accum))  # type: ignore[arg-type]

        output_file.parent.mkdir(parents=True, exist_ok=True)
        write_ppm(output_file, args.width, args.height, pixels)
        print(f"\n[OK] Wrote {output_file} from {len(hits)} RTL traversal results ({hit_count} hits).")
        if not args.no_png:
            png_path = output_file.with_suffix(".png")
            if maybe_write_png(output_file, png_path):
                print(f"[OK] Wrote {png_path}")

        if "[REF] FAIL:" in (simulation.stdout or ""):
            print("[WARNING] The testbench reported RTL/C-reference mismatches; image is from RTL results.")
            print(f"          Inspect {log_file}")
        else:
            print("[CHECK] All hardware traversal results matched the C reference within tolerance.")
        print(f"[LOG] Simulation output saved to {log_file}")
        return 0

    except (OSError, RuntimeError, ValueError) as exc:
        print(f"\n[ERROR] {exc}", file=sys.stderr)
        print(f"[INFO] Generated intermediate files are in {project_dir}", file=sys.stderr)
        return 1
    finally:
        if not args.keep_marker:
            try:
                marker_file.unlink(missing_ok=True)
            except OSError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
