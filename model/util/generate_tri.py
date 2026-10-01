#thanks again to Google Gemini

#!/usr/bin/env python3

import argparse
import random
import math


def random_point_in_sphere(radius):
    while True:
        x = random.uniform(-1.0, 1.0)
        y = random.uniform(-1.0, 1.0)
        z = random.uniform(-1.0, 1.0)

        if x * x + y * y + z * z <= 1.0:
            return (
                x * radius,
                y * radius,
                z * radius,
            )


def generate_triangle(scale):
    while True:
        v1 = random_point_in_sphere(scale)
        v2 = random_point_in_sphere(scale)
        v3 = random_point_in_sphere(scale)

        # Reject degenerate triangles.
        ax = v2[0] - v1[0]
        ay = v2[1] - v1[1]
        az = v2[2] - v1[2]

        bx = v3[0] - v1[0]
        by = v3[1] - v1[1]
        bz = v3[2] - v1[2]

        cx = ay * bz - az * by
        cy = az * bx - ax * bz
        cz = ax * by - ay * bx

        area2 = cx * cx + cy * cy + cz * cz

        if area2 > 1e-8:
            return v1, v2, v3


def main():
    parser = argparse.ArgumentParser(
        description="Generate a random .tri triangle asset."
    )

    parser.add_argument(
        "count",
        type=int,
        help="Number of triangles to generate"
    )

    parser.add_argument(
        "output",
        help="Output .tri filename"
    )

    parser.add_argument(
        "--scale",
        type=float,
        default=1.0,
        help="Geometry radius (default: 1.0)"
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Random seed for reproducible geometry"
    )

    args = parser.parse_args()

    if args.count <= 0:
        raise ValueError("Triangle count must be positive")

    if args.seed is not None:
        random.seed(args.seed)

    with open(args.output, "w") as f:
        for _ in range(args.count):
            v1, v2, v3 = generate_triangle(args.scale)

            f.write(
                f"{v1[0]:.9f} {v1[1]:.9f} {v1[2]:.9f} "
                f"{v2[0]:.9f} {v2[1]:.9f} {v2[2]:.9f} "
                f"{v3[0]:.9f} {v3[1]:.9f} {v3[2]:.9f}\n"
            )

    print(f"Generated {args.count} triangles")
    print(f"Output: {args.output}")
    print(f"Scale:  {args.scale}")


if __name__ == "__main__":
    main()