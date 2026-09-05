import { useMemo, useState } from 'react'
import { getWeatherColor } from './weatherColors.js'
import { effectiveZoneMapColor } from './zoneColorUtils.js'

export default function Sidebar({
  activeLayer,
  zones = [],
  floodIgnoreZones = [],
  states = {},
  selectedId,
  onSelect,
  onRequestDelete,
}) {
  const [query, setQuery] = useState('')
  const items = activeLayer === 'zones' ? zones : activeLayer === 'floods' ? floodIgnoreZones : []
  const title = activeLayer === 'floods' ? 'Flood Ignore' : 'Zones'

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return items
    return items.filter(
      (z) =>
        (z.label || '').toLowerCase().includes(q) ||
        (z.id || '').toLowerCase().includes(q)
    )
  }, [items, query])

  return (
    <aside className="dw-rail dw-rail-left" aria-label={activeLayer === 'floods' ? 'Flood ignore zones' : 'Weather zones'}>
      <div className="dw-rail-head">
        <span className="dw-rail-title">{title}</span>
        <span className="dw-rail-count">{items.length}</span>
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
        {items.length === 0 && (
          <div className="dw-empty-state">
            {activeLayer === 'floods' ? 'No ignore zones yet. Use toolbar to add one.' : 'No zones yet. Use toolbar to add a polygon or rectangle zone.'}
          </div>
        )}
        {items.length > 0 && filtered.length === 0 && (
          <div className="dw-empty-state">No matches for this filter.</div>
        )}
        {filtered.map((zone) => {
          const weather = activeLayer === 'floods' ? 'IGNORE' : states[zone.id]?.currentWeather || 'CLEAR'
          const isActive = zone.id === selectedId
          const fill = activeLayer === 'floods' ? (zone.mapColor || '#38bdf8') : effectiveZoneMapColor(zone, weather)
          const rim = activeLayer === 'floods' ? '#7dd3fc' : getWeatherColor(weather)
          const label = activeLayer === 'floods' ? (zone.name || zone.label || zone.id) : zone.label
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
                <span className="dw-zone-label">{label}</span>
                <span className="dw-zone-meta">
                  <span className="dw-zone-weather">{activeLayer === 'floods' ? 'Flood Ignore Zone' : weather}</span>
                  <span className="dw-zone-sep">·</span>
                  <span className="dw-zone-verts">{zone.points?.length ?? 0} pts</span>
                  {activeLayer === 'floods' && (
                    <>
                      <span className="dw-zone-sep">·</span>
                      <span className="dw-zone-verts">{Number(zone.fadeDistance || 0).toFixed(0)}m fade</span>
                    </>
                  )}
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
