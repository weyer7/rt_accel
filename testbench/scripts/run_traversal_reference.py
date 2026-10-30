#!/usr/bin/env python3
"""Build a quantized scene, run the C reference, then invoke the Icarus Make target.

The script deliberately uses the exact BVH/triangle memory files as input to
both the C reference runner and the SystemVerilog testbench. See the README for
C build and Makefile integration instructions.
"""

from __future__ import annotations

import argparse
import csv
import os
import shutil
import subprocess
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path
from typing import Iterable

Q16_SCALE = Decimal(65536)
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1


def q16_raw(text: str, field_name: str) -> int:
    try:
        value = Decimal(text.strip())
    except InvalidOperation as exc:
        raise ValueError(f"{field_name}: invalid number {text!r}") from exc
    if not value.is_finite():
        raise ValueError(f"{field_name}: value must be finite")
    raw = int((value * Q16_SCALE).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    if raw < INT32_MIN or raw > INT32_MAX:
        raise ValueError(f"{field_name}: {value} is outside signed Q16.16 range")
    return raw


def hex32(value: int) -> str:
    return f"{value & 0xFFFFFFFF:08x}"


def read_ray_csv(path: Path) -> list[list[int]]:
    """Read rows: ox,oy,oz,dx,dy,dz,t_min,t_max; quantize to Q16.16."""
    rays: list[list[int]] = []
    with path.open("r", newline="", encoding="utf-8") as stream:
        for line_no, raw_line in enumerate(stream, start=1):
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            # Accept CSV or whitespace-separated values.
            if "," in stripped:
                fields = next(csv.reader([stripped], skipinitialspace=True))
            else:
                fields = stripped.split()
            fields = [field.strip() for field in fields if field.strip()]
            if len(fields) != 8:
                raise ValueError(
                    f"{path}:{line_no}: expected 8 values "
                    "ox,oy,oz,dx,dy,dz,t_min,t_max; got "
                    f"{len(fields)}"
                )
            names = ("ox", "oy", "oz", "dx", "dy", "dz", "t_min", "t_max")
            raw = [q16_raw(value, f"{path}:{line_no}:{name}")
                   for name, value in zip(names, fields)]
            directions = raw[3:6]
            if directions == [0, 0, 0]:
                raise ValueError(f"{path}:{line_no}: direction vector cannot be zero")

            # Hardware receives a Q16.16 inverse direction. The C reference
            # derives its reciprocal internally from the same quantized ray.
            inv_raw: list[int] = []
            for axis, component in zip("xyz", directions):
                if component == 0:
                    inv_raw.append(0)
                else:
                    direction = Decimal(component) / Q16_SCALE
                    inv_raw.append(q16_raw(str(Decimal(1) / direction), f"{path}:{line_no}:inv_d{axis}"))

            ray_id = len(rays)
            if ray_id > 0xFFFF:
                raise ValueError("The testbench ray_id field is 16 bits; too many rays")
            # Protocol: ray_id, O[3], D[3], invD[3], t_min, t_max.
            rays.append([ray_id, raw[0], raw[1], raw[2],
                         raw[3], raw[4], raw[5],
                         inv_raw[0], inv_raw[1], inv_raw[2],
                         raw[6], raw[7]])

    if not rays:
        raise ValueError(f"No rays found in {path}")
    return rays


def write_ray_file(path: Path, rays: Iterable[list[int]]) -> int:
    ray_list = list(rays)
    with path.open("w", encoding="ascii", newline="\n") as stream:
        stream.write(f"{len(ray_list)}\n")
        for ray in ray_list:
            stream.write(" ".join(hex32(value) for value in ray) + "\n")
    return len(ray_list)


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


def run_command(command: list[str], cwd: Path, description: str) -> subprocess.CompletedProcess[str]:
    print(f"\n[RUN] {description}")
    print("       " + " ".join(command))
    completed = subprocess.run(command, cwd=cwd, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               check=False)
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.returncode != 0:
        raise RuntimeError(f"{description} failed with exit status {completed.returncode}")
    return completed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare traversal_controller against the C traverse_bvh reference."
    )
    parser.add_argument("triangles", type=Path,
                        help="Input mesh text file (nine floats per triangle)")
    parser.add_argument("rays", type=Path,
                        help="CSV/whitespace ray file: ox oy oz dx dy dz t_min t_max")
    parser.add_argument("--project-dir", type=Path, default=Path.cwd(),
                        help="Project directory containing the Makefile (default: cwd)")
    parser.add_argument("--exporter", default="build/export_bvh_mem",
                        help="Previously built export_bvh_mem executable")
    parser.add_argument("--reference-runner", default="build/rtu_reference_runner",
                        help="Previously built rtu_reference_runner executable")
    parser.add_argument("--make", default="make", help="Make executable")
    parser.add_argument("--target", default="sim_traversal_controller_src",
                        help="Make target to run")
    parser.add_argument("--tolerance-lsb", type=int, default=8,
                        help="Absolute Q16.16 comparison tolerance (default: 8 LSB)")
    parser.add_argument("--keep-marker", action="store_true",
                        help="Leave .reference_run.enable after simulation")
    args = parser.parse_args()

    project_dir = args.project_dir.resolve()
    if not project_dir.is_dir():
        parser.error(f"project directory does not exist: {project_dir}")
    mesh_file = args.triangles if args.triangles.is_absolute() else (project_dir / args.triangles)
    ray_csv = args.rays if args.rays.is_absolute() else (project_dir / args.rays)
    mesh_file = mesh_file.resolve()
    ray_csv = ray_csv.resolve()
    if not mesh_file.is_file():
        parser.error(f"triangle input file does not exist: {mesh_file}")
    if not ray_csv.is_file():
        parser.error(f"ray CSV does not exist: {ray_csv}")
    if args.tolerance_lsb < 0:
        parser.error("--tolerance-lsb must be nonnegative")

    try:
        exporter = resolve_program(args.exporter, project_dir)
        reference_runner = resolve_program(args.reference_runner, project_dir)
        rays = read_ray_csv(ray_csv)
    except (FileNotFoundError, ValueError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    # The Make target and testbench use these default filenames relative to
    # the project root. Keep all generated files together for reproducibility.
    bvh_file = project_dir / "bvh_nodes.hex"
    tri_file = project_dir / "triangles.hex"
    ray_file = project_dir / "reference_rays.hex"
    result_file = project_dir / "reference_results.hex"
    enable_file = project_dir / ".reference_run.enable"

    try:
        write_ray_file(ray_file, rays)
        run_command(
            [exporter, str(mesh_file), str(bvh_file), str(tri_file)],
            project_dir,
            "export BVH and sorted triangle memories",
        )
        run_command(
            [reference_runner, str(bvh_file), str(tri_file),
             str(ray_file), str(result_file)],
            project_dir,
            "run software traverse_bvh reference",
        )

        # The updated testbench checks for this marker at runtime, avoiding
        # the need to alter the existing Makefile target's compile arguments.
        enable_file.write_text(f"{args.tolerance_lsb}\n", encoding="ascii")
        simulation = run_command(
            [args.make, args.target], project_dir,
            "run Icarus traversal-controller simulation",
        )
        output = simulation.stdout or ""
        if "[REF] PASS:" not in output:
            raise RuntimeError(
                "simulation completed but no '[REF] PASS:' summary was found. "
                "Make sure traversal_controller_tb_reference.sv is installed "
                "as the testbench used by sim_traversal_controller_src."
            )
        if "[REF] FAIL:" in output:
            raise RuntimeError("the Verilog testbench reported reference mismatches")

        print(f"\n[OK] C reference and RTL traversal compared for {len(rays)} ray(s).")
        print(f"     BVH memory:     {bvh_file}")
        print(f"     Triangle memory:{tri_file}")
        print(f"     Ray requests:   {ray_file}")
        print(f"     C expectations: {result_file}")
        return 0
    except (OSError, RuntimeError) as exc:
        print(f"\n[ERROR] {exc}", file=sys.stderr)
        return 1
    finally:
        if not args.keep_marker:
            try:
                enable_file.unlink(missing_ok=True)
            except OSError:
                pass


if __name__ == "__main__":
    raise SystemExit(main())
