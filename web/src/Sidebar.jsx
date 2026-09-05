import { useMemo, useState } from 'react'
import { getWeatherColor } from './weatherColors.js'
import { effectiveZoneMapColor } from './zoneColorUtils.js'

export default function Sidebar({
  zones = [],
  states = {},
  selectedId,
  onSelect,
  onRequestDelete,
}) {
  const [query, setQuery] = useState('')

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return zones
    return zones.filter(
      (z) =>
        (z.label || '').toLowerCase().includes(q) ||
        (z.id || '').toLowerCase().includes(q)
    )
  }, [zones, query])

  return (
    <aside className="dw-rail dw-rail-left" aria-label="Weather zones">
      <div className="dw-rail-head">
        <span className="dw-rail-title">Zones</span>
        <span className="dw-rail-count">{zones.length}</span>
      </div>
      <label className="dw-search">
        <span className="dw-sr-only">Filter zones</span>
        <input
          type="search"
          className="dw-input dw-search-input"
          placeholder="Filter by name or id"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          autoComplete="off"
        />
      </label>
      <div className="dw-zone-list" role="list">
        {zones.length === 0 && (
          <div className="dw-empty-state">
            No zones yet. Use the toolbar to add a polygon or rectangle zone.
          </div>
        )}
        {zones.length > 0 && filtered.length === 0 && (
          <div className="dw-empty-state">No matches for this filter.</div>
        )}
        {filtered.map((zone) => {
          const weather = states[zone.id]?.currentWeather || 'CLEAR'
          const isActive = zone.id === selectedId
          const fill = effectiveZoneMapColor(zone, weather)
          const rim = getWeatherColor(weather)
          return (
            <div
              key={zone.id}
              role="listitem"
              className={`dw-zone-item ${isActive ? 'active' : ''}`}
              onClick={() => onSelect(zone.id)}
            >
              <span
                className="dw-zone-swatch"
                style={{ background: fill, boxShadow: `inset 0 0 0 2px ${rim}` }}
                title={`${weather} · map color`}
              />
              <div className="dw-zone-info">
                <span className="dw-zone-label">{zone.label}</span>
                <span className="dw-zone-meta">
                  <span className="dw-zone-weather">{weather}</span>
                  <span className="dw-zone-sep">·</span>
                  <span className="dw-zone-verts">{zone.points?.length ?? 0} pts</span>
                  {zone.enabled === false && (
                    <>
                      <span className="dw-zone-sep">·</span>
                      <span className="dw-zone-off">off</span>
                    </>
                  )}
                </span>
              </div>
              <button
                type="button"
                className="dw-zone-delete"
                onClick={(e) => {
                  e.stopPropagation()
                  onRequestDelete(zone.id)
                }}
                title="Delete zone"
              >
                ×
              </button>
            </div>
          )
        })}
      </div>
    </aside>
  )
}
