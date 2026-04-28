import { useCallback, useEffect, useMemo, useState } from 'react'
import ZoneForm from './ZoneForm.jsx'
import { getWeatherColor } from './weatherColors.js'
import { effectiveZoneMapColor } from './zoneColorUtils.js'

export default function Inspector({
  zone,
  states,
  sequences,
  onUpdateZone,
  onUpdatePoints,
  onDuplicate,
  onFitMap,
  onSetZoneWeather,
  onAdvanceZoneWeather,
}) {
  const st = zone ? states[zone.id] : null
  const current = st?.currentWeather || 'CLEAR'
  const next = st?.nextWeather || current
  const swatch = getWeatherColor(current)
  const mapSwatch = effectiveZoneMapColor(zone, current)
  const pool = useMemo(
    () => (zone?.weatherPool?.length ? zone.weatherPool : ['CLEAR']),
    [zone?.weatherPool]
  )
  const [manualPick, setManualPick] = useState(current)

  useEffect(() => {
    setManualPick(current)
  }, [zone?.id, current])

  useEffect(() => {
    if (!pool.includes(manualPick)) setManualPick(pool[0] || 'CLEAR')
  }, [pool, manualPick])

  const handleDup = useCallback(() => {
    if (zone) onDuplicate(zone)
  }, [zone, onDuplicate])

  const handleApplyManual = useCallback(() => {
    if (!zone || !onSetZoneWeather) return
    onSetZoneWeather(zone.id, manualPick)
  }, [zone, manualPick, onSetZoneWeather])

  const handleAdvance = useCallback(() => {
    if (!zone || !onAdvanceZoneWeather) return
    onAdvanceZoneWeather(zone.id)
  }, [zone, onAdvanceZoneWeather])

  const handleQuickSet = useCallback(
    (w) => {
      if (!zone || !onSetZoneWeather) return
      onSetZoneWeather(zone.id, w)
    },
    [zone, onSetZoneWeather]
  )

  if (!zone) {
    return (
      <div
        className="dw-rail dw-rail-right dw-inspector dw-inspector-empty"
        role="status"
        aria-live="polite"
      >
        <p className="dw-inspector-empty-text">No zone selected</p>
      </div>
    )
  }

  return (
    <div className="dw-rail dw-rail-right dw-inspector">
      <div className="dw-inspector-head">
        <div className="dw-inspector-head-row">
          <div className="dw-inspector-swatches" aria-label="Map color and current weather">
            <span className="dw-inspector-swatch dw-inspector-swatch-map" style={{ background: mapSwatch }} title="Zone map color" />
            <span className="dw-inspector-swatch dw-inspector-swatch-weather" style={{ background: swatch }} title={`Weather: ${current}`} />
          </div>
          <div className="dw-inspector-titles">
            <span className="dw-inspector-name">{zone.label}</span>
            <span className="dw-inspector-id">{zone.id}</span>
          </div>
        </div>
        <div className="dw-inspector-metrics" aria-label="Live weather">
          <div className="dw-metric">
            <span className="dw-metric-k">Now</span>
            <span className="dw-metric-v">{current}</span>
          </div>
          <div className="dw-metric">
            <span className="dw-metric-k">Next</span>
            <span className="dw-metric-v dw-metric-v-dim">{next}</span>
          </div>
          <div className="dw-metric">
            <span className="dw-metric-k">Verts</span>
            <span className="dw-metric-v">{zone.points?.length ?? 0}</span>
          </div>
          <div className="dw-metric">
            <span className="dw-metric-k">Pool</span>
            <span className="dw-metric-v">{(zone.weatherPool || []).length}</span>
          </div>
        </div>
        <div className="dw-inspector-actions">
          <button type="button" className="dw-btn dw-btn-ghost dw-btn-compact" onClick={onFitMap}>
            Fit map
          </button>
          <button type="button" className="dw-btn dw-btn-compact" onClick={handleDup}>
            Duplicate
          </button>
        </div>
        {onSetZoneWeather && onAdvanceZoneWeather && (
          <div className="dw-inspector-live">
            <div className="dw-inspector-live-row">
              <span className="dw-inspector-live-label">Runtime</span>
              <button type="button" className="dw-btn dw-btn-compact" onClick={handleAdvance}>
                Next weather (advance)
              </button>
            </div>
            <p className="dw-field-hint dw-inspector-live-hint">
              Advance rolls the server sequencer once. Set applies immediately (types must stay in the weather pool).
            </p>
            <div className="dw-inspector-live-manual">
              <label className="dw-inspector-live-label" htmlFor="dw-live-weather">
                Set manually
              </label>
              <div className="dw-inspector-live-manual-row">
                <select
                  id="dw-live-weather"
                  className="dw-input dw-inspector-select"
                  value={manualPick}
                  onChange={(e) => setManualPick(e.target.value)}
                >
                  {pool.map((w) => (
                    <option key={w} value={w}>
                      {w}
                    </option>
                  ))}
                </select>
                <button type="button" className="dw-btn" onClick={handleApplyManual}>
                  Apply
                </button>
              </div>
            </div>
            <div className="dw-inspector-live-quick">
              <span className="dw-inspector-live-label">Pool quick-set</span>
              <div className="dw-inspector-live-pills">
                {pool.map((w) => {
                  const col = getWeatherColor(w)
                  const active = w === current
                  return (
                    <button
                      key={w}
                      type="button"
                      className={`dw-live-weather-pill ${active ? 'active' : ''}`}
                      style={{ '--dw-pill-accent': col }}
                      title={w}
                      onClick={() => handleQuickSet(w)}
                    >
                      {w}
                    </button>
                  )
                })}
              </div>
            </div>
          </div>
        )}
      </div>
      <div className="dw-inspector-form">
        <ZoneForm
          zone={zone}
          sequences={sequences}
          currentWeather={current}
          onChange={(updates) => onUpdateZone(zone.id, updates)}
          onUpdatePoints={(points) => onUpdatePoints(zone.id, points)}
        />
      </div>
    </div>
  )
}
