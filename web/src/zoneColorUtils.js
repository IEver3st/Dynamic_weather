import { getWeatherColor } from './weatherColors.js'

/** Distinct map / list accents (no purple-gradient cliché). */
export const MAP_COLOR_PRESETS = [
  '#14b8a6',
  '#e07c5c',
  '#d4a574',
  '#3b82c4',
  '#84cc16',
  '#f472b6',
  '#fbbf24',
  '#64748b',
]

export function normalizeMapColor(raw) {
  if (raw == null || typeof raw !== 'string') return null
  const s = raw.trim()
  if (!s) return null
  const m = s.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/)
  if (!m) return null
  let h = m[1]
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  }
  return `#${h.toLowerCase()}`
}

export function isValidMapColor(raw) {
  return normalizeMapColor(raw) != null
}

/** Zone outline/fill when `mapColor` set; else weather tint (legacy). */
export function effectiveZoneMapColor(zone, currentWeather) {
  const n = normalizeMapColor(zone?.mapColor)
  if (n) return n
  return getWeatherColor(currentWeather || 'CLEAR')
}

export function defaultMapColorForIndex(index) {
  const i = Number.isFinite(index) && index >= 0 ? index : 0
  return MAP_COLOR_PRESETS[i % MAP_COLOR_PRESETS.length]
}
