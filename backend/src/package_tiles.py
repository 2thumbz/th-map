#!/usr/bin/env python3
"""Download raster map tiles into Flutter asset layout: assets/tiles/{z}_{x}_{y}.png.

Example:
  py src/package_tiles.py --bbox 126.95 37.36 127.04 37.45 --min-zoom 14 --max-zoom 17
"""

from __future__ import annotations

import argparse
import math
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Iterable


def lon_to_tile_x(lon_deg: float, zoom: int) -> int:
    n = 2 ** zoom
    return int((lon_deg + 180.0) / 360.0 * n)


def lat_to_tile_y(lat_deg: float, zoom: int) -> int:
    lat_rad = math.radians(lat_deg)
    n = 2 ** zoom
    y = (1.0 - math.log(math.tan(lat_rad) + (1 / math.cos(lat_rad))) / math.pi) / 2.0 * n
    return int(y)


def clamp_lat(lat: float) -> float:
    # Web Mercator valid latitude range.
    return max(min(lat, 85.05112878), -85.05112878)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Package map tiles for offline Flutter assets",
    )
    parser.add_argument(
        "--bbox",
        nargs=4,
        type=float,
        metavar=("MIN_LON", "MIN_LAT", "MAX_LON", "MAX_LAT"),
        required=True,
        help="Bounding box in WGS84 degrees",
    )
    parser.add_argument("--min-zoom", type=int, required=True, help="Minimum zoom level")
    parser.add_argument("--max-zoom", type=int, required=True, help="Maximum zoom level")
    parser.add_argument(
        "--output",
        type=str,
        default="../../assets/tiles",
        help="Output tile root (default: ../../assets/tiles from this script)",
    )
    parser.add_argument(
        "--url-template",
        type=str,
        default="https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        help="Tile URL template",
    )
    parser.add_argument(
        "--user-agent",
        type=str,
        default="my_nav_app-offline-tiles/1.0 (+https://example.com)",
        help="HTTP User-Agent",
    )
    parser.add_argument("--timeout", type=float, default=15.0, help="HTTP timeout seconds")
    parser.add_argument("--delay", type=float, default=0.05, help="Delay between requests seconds")
    parser.add_argument("--retries", type=int, default=3, help="Retries per tile")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite existing tile files")
    parser.add_argument("--dry-run", action="store_true", help="Print plan only, no downloads")
    parser.add_argument(
        "--max-tiles",
        type=int,
        default=20000,
        help="Safety limit for total tile count",
    )
    return parser.parse_args()


def make_url(template: str, z: int, x: int, y: int) -> str:
    return template.replace("{z}", str(z)).replace("{x}", str(x)).replace("{y}", str(y))


def iter_tiles(min_lon: float, min_lat: float, max_lon: float, max_lat: float, zoom: int) -> Iterable[tuple[int, int, int]]:
    # Convert bbox to XYZ index range. Y grows downward in Web Mercator.
    x1 = lon_to_tile_x(min_lon, zoom)
    x2 = lon_to_tile_x(max_lon, zoom)
    y1 = lat_to_tile_y(max_lat, zoom)
    y2 = lat_to_tile_y(min_lat, zoom)

    x_min, x_max = min(x1, x2), max(x1, x2)
    y_min, y_max = min(y1, y2), max(y1, y2)

    max_index = (2 ** zoom) - 1
    x_min = max(0, min(x_min, max_index))
    x_max = max(0, min(x_max, max_index))
    y_min = max(0, min(y_min, max_index))
    y_max = max(0, min(y_max, max_index))

    for x in range(x_min, x_max + 1):
        for y in range(y_min, y_max + 1):
            yield (zoom, x, y)


def download_tile(url: str, out_file: Path, timeout: float, retries: int, user_agent: str) -> bool:
    backoff = 0.5
    for attempt in range(1, retries + 1):
        request = urllib.request.Request(url, headers={"User-Agent": user_agent})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                if response.status != 200:
                    raise urllib.error.HTTPError(
                        url=url,
                        code=response.status,
                        msg=f"HTTP {response.status}",
                        hdrs=response.headers,
                        fp=None,
                    )
                data = response.read()

            out_file.parent.mkdir(parents=True, exist_ok=True)
            out_file.write_bytes(data)
            return True
        except Exception as exc:  # noqa: BLE001
            if attempt == retries:
                print(f"[FAIL] {url} -> {exc}")
                return False
            time.sleep(backoff)
            backoff *= 2
    return False


def main() -> int:
    args = parse_args()

    if args.min_zoom < 0 or args.max_zoom < args.min_zoom:
        print("[ERROR] Invalid zoom range")
        return 2

    min_lon, min_lat, max_lon, max_lat = args.bbox
    min_lat = clamp_lat(min_lat)
    max_lat = clamp_lat(max_lat)

    script_dir = Path(__file__).resolve().parent
    output_root = (script_dir / args.output).resolve()

    all_tiles: list[tuple[int, int, int]] = []
    for z in range(args.min_zoom, args.max_zoom + 1):
        all_tiles.extend(iter_tiles(min_lon, min_lat, max_lon, max_lat, z))

    total = len(all_tiles)
    if total == 0:
        print("[INFO] No tiles to download for the given bbox/zoom.")
        return 0

    if total > args.max_tiles:
        print(f"[ERROR] Planned tiles={total} exceeds max limit={args.max_tiles}")
        print("        Use lower zoom range, smaller bbox, or raise --max-tiles.")
        return 2

    print(f"[INFO] Output: {output_root}")
    print(f"[INFO] Zoom: {args.min_zoom}..{args.max_zoom}")
    print(f"[INFO] Planned tiles: {total}")

    if args.dry_run:
        return 0

    ok = 0
    skipped = 0
    failed = 0

    for idx, (z, x, y) in enumerate(all_tiles, start=1):
        out_file = output_root / f"{z}_{x}_{y}.png"

        if out_file.exists() and not args.overwrite:
            skipped += 1
            continue

        url = make_url(args.url_template, z, x, y)
        if download_tile(url, out_file, args.timeout, args.retries, args.user_agent):
            ok += 1
        else:
            failed += 1

        if args.delay > 0:
            time.sleep(args.delay)

        if idx % 200 == 0 or idx == total:
            print(f"[INFO] Progress {idx}/{total} (ok={ok}, skipped={skipped}, failed={failed})")

    print("[DONE]")
    print(f"       ok={ok}, skipped={skipped}, failed={failed}, total={total}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
