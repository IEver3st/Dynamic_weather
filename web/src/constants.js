const OX_MAP_CENTER = [-119.43, 58.84]
const OX_LAT_PR_100 = 1.421
const OX_MIN_ZOOM = 2
const OX_MAX_ZOOM = 7
const OX_STARTUP_ZOOM = 5

const OX_MAP_BOUNDS = [
  [0.0, 128.0],
  [-192.0, 0.0],
]

export function gameToMap(x, y) {
  const scale = OX_LAT_PR_100 / 100
  return [OX_MAP_CENTER[0] + scale * y, OX_MAP_CENTER[1] + scale * x]
}

export function mapToGame(lat, lng) {
  const scale = OX_LAT_PR_100 / 100
  return {
    x: (lng - OX_MAP_CENTER[1]) / scale,
    y: (lat - OX_MAP_CENTER[0]) / scale,
  }
}

export {
  OX_MAP_CENTER,
  OX_LAT_PR_100,
  OX_MIN_ZOOM,
  OX_MAX_ZOOM,
  OX_STARTUP_ZOOM,
  OX_MAP_BOUNDS,
}
