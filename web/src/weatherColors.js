/** Single accent-aligned palette: no purple thunder (per design guard). */
export const WEATHER_COLORS = {
  CLEAR: '#d4a574',
  EXTRASUNNY: '#e8c48a',
  CLOUDS: '#94a3b8',
  OVERCAST: '#64748b',
  RAIN: '#3b82c4',
  THUNDER: '#1d4e8f',
  CLEARING: '#34a37a',
  NEUTRAL: '#9ca3af',
  SMOG: '#a8a29e',
  FOGGY: '#cbd5e1',
  XMAS: '#c24133',
  SNOWLIGHT: '#dbeafe',
  SNOW: '#f1f5f9',
  BLIZZARD: '#93c5d4',
  HALLOWEEN: '#c2410c',
}

export function getWeatherColor(weather) {
  return WEATHER_COLORS[weather] || '#14b8a6'
}
