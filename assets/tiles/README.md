Offline tile directory for flutter_map asset tiles.

Expected structure:
assets/tiles/{z}_{x}_{y}.png

Example:
assets/tiles/15_27940_12680.png

Notes:
- Keep OFFLINE_MAP_TILES=true (default) to use these tiles.
- If files are missing for an area/zoom, map will show blank tiles there.

Generate tiles (from project root):

```bash
cd backend
npm run package:tiles -- --bbox 126.95 37.36 127.04 37.45 --min-zoom 14 --max-zoom 17
```

This writes PNG tiles into `assets/tiles/{z}_{x}_{y}.png`.
