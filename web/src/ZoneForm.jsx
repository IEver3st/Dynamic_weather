import { useState, useCallback, useMemo, useRef, useEffect, useLayoutEffect } from 'react'
import { createPortal } from 'react-dom'
import ToggleSwitch from './ToggleSwitch.jsx'
import { normalizeMapColor, MAP_COLOR_PRESETS, effectiveZoneMapColor } from './zoneColorUtils.js'

export const ALL_WEATHERS = [
  'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'OVERCAST', 'RAIN', 'THUNDER',
  'CLEARING', 'NEUTRAL', 'SMOG', 'FOGGY',
  'XMAS', 'SNOWLIGHT', 'SNOW', 'BLIZZARD', 'HALLOWEEN',
]

function SequenceSelect({ id, value, sequences, onChange }) {
  const [open, setOpen] = useState(false)
  const triggerRef = useRef(null)
  const menuRef = useRef(null)
  const [menuPos, setMenuPos] = useState({ top: 0, left: 0, width: 0, maxH: 240 })

  const entries = useMemo(() => Object.entries(sequences), [sequences])
  const currentLabel = sequences[value]?.label || value

  const updatePosition = useCallback(() => {
    const el = triggerRef.current
    if (!el) return
    const r = el.getBoundingClientRect()
    const gap = 4
    const maxH = Math.min(280, Math.max(120, window.innerHeight - r.bottom - gap - 16))
    setMenuPos({
      top: r.bottom + gap,
      left: r.left,
      width: r.width,
      maxH,
    })
  }, [])

  useLayoutEffect(() => {
    if (!open) return
    updatePosition()
    const onScroll = () => updatePosition()
    const onResize = () => updatePosition()
    window.addEventListener('scroll', onScroll, true)
    window.addEventListener('resize', onResize)
    return () => {
      window.removeEventListener('scroll', onScroll, true)
      window.removeEventListener('resize', onResize)
    }
  }, [open, updatePosition])

  useEffect(() => {
    if (!open) return
    const onDown = (e) => {
      if (triggerRef.current?.contains(e.target)) return
      if (menuRef.current?.contains(e.target)) return
      setOpen(false)
    }
    const onKey = (e) => {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  const menu =
    open &&
    createPortal(
      <div
        ref={menuRef}
        className="dw-select-menu"
        role="listbox"
        aria-labelledby={id}
        style={{
          top: menuPos.top,
          left: menuPos.left,
          width: menuPos.width,
          maxHeight: menuPos.maxH,
        }}
      >
        {entries.map(([seqId, seq]) => (
          <button
            key={seqId}
            type="button"
            role="option"
            aria-selected={value === seqId}
            className={`dw-select-option ${value === seqId ? 'dw-select-option-active' : ''}`}
            onClick={() => {
              onChange(seqId)
              setOpen(false)
            }}
          >
            {seq.label || seqId}
          </button>
        ))}
      </div>,
      document.body
    )

  return (
    <div className="dw-select">
      <button
        ref={triggerRef}
        type="button"
        id={id}
        className="dw-input dw-select-trigger"
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="dw-select-value">{currentLabel}</span>
        <span className="dw-select-chevron" aria-hidden>
          ▾
        </span>
      </button>
      {menu}
    </div>
  )
}

export default function ZoneForm({ zone, sequences, currentWeather, onChange, onUpdatePoints }) {
  const [activeTab, setActiveTab] = useState('config')
  const [hexDraft, setHexDraft] = useState(() => (typeof zone.mapColor === 'string' ? zone.mapColor : ''))

  useEffect(() => {
    setHexDraft(typeof zone.mapColor === 'string' ? zone.mapColor : '')
  }, [zone.id, zone.mapColor])

  const update = useCallback(
    (key, value) => {
      onChange({ [key]: value })
    },
    [onChange]
  )

  const toggleWeather = useCallback(
    (w) => {
      const pool = [...(zone.weatherPool || [])]
      const idx = pool.indexOf(w)
      if (idx >= 0) {
        pool.splice(idx, 1)
      } else {
        pool.push(w)
      }
      if (pool.length === 0) return
      update('weatherPool', pool)
    },
    [zone.weatherPool, update]
  )

  const selectAllPool = useCallback(() => {
    update('weatherPool', [...ALL_WEATHERS])
  }, [update])

  const clearPool = useCallback(() => {
    update('weatherPool', ['CLEAR'])
  }, [update])

  const updatePoint = useCallback(
    (index, axis, value) => {
      const points = zone.points.map((p, i) =>
        i === index ? { ...p, [axis]: parseFloat(value) || 0 } : p
      )
      onUpdatePoints(points)
    },
    [zone.points, onUpdatePoints]
  )

  const sequenceLabel = useMemo(() => {
    const cur = zone.sequence || 'urban_coastal'
    return sequences[cur]?.label || cur
  }, [zone.sequence, sequences])

  const weatherNow = currentWeather || 'CLEAR'
  const previewFill = useMemo(
    () => effectiveZoneMapColor(zone, weatherNow),
    [zone, weatherNow]
  )
  const chosenHex = normalizeMapColor(zone.mapColor)
  const pickerHex = chosenHex || '#14b8a6'

  return (
    <div className="dw-panel-body">
      <div className="dw-tabs">
        <button
          type="button"
          className={`dw-tab ${activeTab === 'config' ? 'active' : ''}`}
          onClick={() => setActiveTab('config')}
        >
          Config
        </button>
        <button
          type="button"
          className={`dw-tab ${activeTab === 'weather' ? 'active' : ''}`}
          onClick={() => setActiveTab('weather')}
        >
          Weather
        </button>
        <button
          type="button"
          className={`dw-tab ${activeTab === 'points' ? 'active' : ''}`}
          onClick={() => setActiveTab('points')}
        >
          Points
        </button>
      </div>

      <div className="dw-panel-content">
        {activeTab === 'config' && (
          <div className="dw-form">
            <div className="dw-field">
              <label htmlFor="dw-z-label">Label</label>
              <input
                id="dw-z-label"
                type="text"
                value={zone.label || ''}
                onChange={(e) => update('label', e.target.value)}
                className="dw-input"
                maxLength={48}
              />
              <p className="dw-field-hint">Shown in the zone list and map legend.</p>
            </div>
            <div className="dw-field dw-field-color">
              <label htmlFor="dw-z-mapcolor">Map color</label>
              <div className="dw-color-row">
                <input
                  id="dw-z-mapcolor"
                  type="color"
                  className="dw-color-native"
                  value={pickerHex}
                  onChange={(e) => update('mapColor', e.target.value)}
                  title="Pick zone outline / fill"
                  aria-label="Zone map color"
                />
                <input
                  type="text"
                  className="dw-input dw-color-hex"
                  value={hexDraft}
                  placeholder="#RRGGBB"
                  spellCheck={false}
                  maxLength={7}
                  onChange={(e) => setHexDraft(e.target.value)}
                  onBlur={() => {
                    const t = hexDraft.trim()
                    if (t === '') {
                      update('mapColor', '')
                      setHexDraft('')
                      return
                    }
                    const n = normalizeMapColor(t)
                    if (n) {
                      update('mapColor', n)
                      setHexDraft(n)
                    } else {
                      setHexDraft(typeof zone.mapColor === 'string' ? zone.mapColor : '')
                    }
                  }}
                  aria-label="Hex color"
                />
                <button
                  type="button"
                  className="dw-btn dw-btn-ghost dw-btn-compact"
                  onClick={() => update('mapColor', '')}
                  title="Use live weather tint on the map (no fixed color)"
                >
                  Auto
                </button>
              </div>
              <div className="dw-color-presets" role="group" aria-label="Color presets">
                {MAP_COLOR_PRESETS.map((hex) => (
                  <button
                    key={hex}
                    type="button"
                    className={`dw-color-preset ${chosenHex === hex ? 'active' : ''}`}
                    style={{ background: hex }}
                    title={hex}
                    onClick={() => update('mapColor', hex)}
                  />
                ))}
              </div>
              <p className="dw-field-hint">
                Saved with zones. Preview:{' '}
                <span className="dw-color-preview" style={{ background: previewFill }} aria-hidden /> matches map
                when no custom hex is set, tint follows current weather.
              </p>
            </div>
            <div className="dw-field">
              <label htmlFor="dw-z-seq">Sequence preset</label>
              <SequenceSelect
                id="dw-z-seq"
                value={zone.sequence || 'urban_coastal'}
                sequences={sequences}
                onChange={(v) => update('sequence', v)}
              />
              <p className="dw-field-hint">Active curve: {sequenceLabel}</p>
            </div>
            <div className="dw-field-row2">
              <div className="dw-field">
                <label htmlFor="dw-z-tr">Transition (sec)</label>
                <input
                  id="dw-z-tr"
                  type="number"
                  value={zone.transitionDuration || 15}
                  onChange={(e) => update('transitionDuration', parseInt(e.target.value, 10) || 15)}
                  className="dw-input"
                  min={1}
                  max={120}
                />
              </div>
              <div className="dw-field">
                <label htmlFor="dw-z-th">Thickness (Z)</label>
                <input
                  id="dw-z-th"
                  type="number"
                  value={zone.thickness || 50}
                  onChange={(e) => update('thickness', parseFloat(e.target.value) || 50)}
                  className="dw-input"
                  min={1}
                  max={500}
                />
              </div>
            </div>
            <div className="dw-field dw-field-row">
              <span id="dw-z-en-label" className="dw-field-toggle-label">
                Enabled
              </span>
              <ToggleSwitch
                id="dw-z-en"
                labelledBy="dw-z-en-label"
                checked={zone.enabled !== false}
                onChange={(v) => update('enabled', v)}
              />
            </div>
          </div>
        )}

        {activeTab === 'weather' && (
          <div className="dw-weather-pool">
            <div className="dw-weather-toolbar">
              <span className="dw-field-label">Allowed weather</span>
              <div className="dw-weather-toolbar-btns">
                <button type="button" className="dw-btn dw-btn-ghost dw-btn-tiny" onClick={selectAllPool}>
                  All
                </button>
                <button type="button" className="dw-btn dw-btn-ghost dw-btn-tiny" onClick={clearPool}>
                  Clear
                </button>
              </div>
            </div>
            <p className="dw-field-hint">Tap types the sequencer may pick from for this zone.</p>
            <div className="dw-weather-grid">
              {ALL_WEATHERS.map((w) => {
                const selected = (zone.weatherPool || []).includes(w)
                return (
                  <button
                    key={w}
                    type="button"
                    className={`dw-weather-pill ${selected ? 'active' : ''}`}
                    onClick={() => toggleWeather(w)}
                  >
                    {w}
                  </button>
                )
              })}
            </div>
          </div>
        )}

        {activeTab === 'points' && (
          <div className="dw-points-panel">
            <span className="dw-field-label">Polygon vertices ({zone.points?.length || 0})</span>
            <p className="dw-field-hint">Drag handles on the map or edit coordinates here.</p>
            <div className="dw-points-list">
              {zone.points?.map((pt, i) => (
                <div key={i} className="dw-point-row">
                  <span className="dw-point-index">{i}</span>
                  <input
                    type="number"
                    value={pt.x}
                    onChange={(e) => updatePoint(i, 'x', e.target.value)}
                    className="dw-input dw-point-input"
                    step="0.1"
                    aria-label={`Vertex ${i} X`}
                  />
                  <input
                    type="number"
                    value={pt.y}
                    onChange={(e) => updatePoint(i, 'y', e.target.value)}
                    className="dw-input dw-point-input"
                    step="0.1"
                    aria-label={`Vertex ${i} Y`}
                  />
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
