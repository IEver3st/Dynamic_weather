import ToggleSwitch from './ToggleSwitch.jsx'

function updatePoint(points, index, axis, value) {
  return (points || []).map((point, i) =>
    i === index ? { ...point, [axis]: parseFloat(value) || 0 } : point
  )
}

export default function FloodPanel({
  settings,
  ignoreZone,
  onUpdate,
  onUpdateIgnoreZone,
  onUpdateIgnorePoints,
  onDuplicateIgnoreZone,
  onFitMap,
}) {
  const recommended = Number(settings?.recommendedMaxOffset ?? 2)
  const chance = Number(settings?.chance ?? 0)
  const maxOffset = Number(settings?.maxOffset ?? recommended)
  const stormLeadSeconds = Number(settings?.stormLeadSeconds ?? 45)
  const fadeDistance = Number(ignoreZone?.fadeDistance ?? 0)
  const points = ignoreZone?.points || []

  return (
    <aside className="dw-rail dw-rail-right dw-inspector">
      <div className="dw-inspector-head">
        <div className="dw-inspector-head-row">
          <div className="dw-inspector-swatches" aria-label="Flood controls">
            <span className="dw-inspector-swatch dw-inspector-swatch-weather" style={{ background: '#1d4e8f' }} />
            <span className="dw-inspector-swatch dw-inspector-swatch-map" style={{ background: ignoreZone?.mapColor || '#38bdf8' }} />
          </div>
          <div className="dw-inspector-titles dw-inspector-titles--flood">
            <span className="dw-inspector-name">Floods</span>
            <span className="dw-inspector-id">Flood Ignore Zone controls</span>
          </div>
        </div>
        <div className="dw-inspector-metrics dw-inspector-metrics--flood" aria-label="Flood settings">
          <div className="dw-metric">
            <span className="dw-metric-k">Spawn chance</span>
            <span className="dw-metric-v">{Math.round(chance * 100)}%</span>
          </div>
          <div className="dw-metric">
            <span className="dw-metric-k">Max offset</span>
            <span className="dw-metric-v">{maxOffset.toFixed(2)}m</span>
          </div>
          <div className="dw-metric">
            <span className="dw-metric-k">Ignore fade</span>
            <span className="dw-metric-v">{fadeDistance.toFixed(0)}m</span>
          </div>
        </div>
        {ignoreZone && (
          <div className="dw-inspector-actions">
            <button type="button" className="dw-btn dw-btn-ghost dw-btn-compact" onClick={onFitMap}>
              Fit map
            </button>
            <button type="button" className="dw-btn dw-btn-compact" onClick={() => onDuplicateIgnoreZone(ignoreZone)}>
              Duplicate
            </button>
          </div>
        )}
      </div>

      <div className="dw-panel-body">
        <div className="dw-tabs">
          <button type="button" className="dw-tab active">
            Flood
          </button>
          <button type="button" className="dw-tab active">
            Ignore Zone
          </button>
        </div>

        <div className="dw-panel-content">
          <div className="dw-form">
            <div className="dw-field dw-field-row">
              <span id="dw-flood-enabled-label" className="dw-field-toggle-label">Enabled</span>
              <ToggleSwitch
                labelledBy="dw-flood-enabled-label"
                checked={settings?.enabled !== false}
                onChange={(checked) => onUpdate({ enabled: checked })}
              />
            </div>

            <div className="dw-field">
              <label htmlFor="dw-flood-chance">Spawn chance</label>
              <input
                id="dw-flood-chance"
                className="dw-range"
                type="range"
                min="0"
                max="1"
                step="0.01"
                value={chance}
                onChange={(e) => onUpdate({ chance: Number(e.target.value) })}
              />
              <span className="dw-slider-value">{Math.round(chance * 100)}%</span>
            </div>

            <div className="dw-field">
              <label htmlFor="dw-flood-offset">Maximum offset</label>
              <input
                id="dw-flood-offset"
                className="dw-input"
                type="number"
                min="0"
                max="20"
                step="0.1"
                value={maxOffset}
                onChange={(e) => onUpdate({ maxOffset: Number(e.target.value) })}
              />
              <p className={maxOffset > recommended ? 'dw-field-hint dw-field-hint-warn' : 'dw-field-hint'}>
                Recommended max {recommended.toFixed(1)}m
              </p>
            </div>

            <div className="dw-field-row2">
              <div className="dw-field">
                <label htmlFor="dw-flood-lead">Thunder lead seconds</label>
                <input
                  id="dw-flood-lead"
                  className="dw-input"
                  type="number"
                  min="0"
                  max="600"
                  step="1"
                  value={stormLeadSeconds}
                  onChange={(e) => onUpdate({ stormLeadSeconds: Number(e.target.value) })}
                />
              </div>
              <div className="dw-field">
                <label htmlFor="dw-flood-condition">Condition</label>
                <select
                  id="dw-flood-condition"
                  className="dw-input"
                  value={settings?.thunderCondition || 'any_zone'}
                  onChange={(e) => onUpdate({ thunderCondition: e.target.value })}
                >
                  <option value="any_zone">Any thunder zone</option>
                  <option value="all_zones">All zones thunder</option>
                </select>
              </div>
            </div>

            <div className="dw-field dw-field-row">
              <span id="dw-flood-thunder-label" className="dw-field-toggle-label">Thunder weather only</span>
              <ToggleSwitch
                labelledBy="dw-flood-thunder-label"
                checked={settings?.requireThunder !== false}
                onChange={(checked) => onUpdate({ requireThunder: checked })}
              />
            </div>

            <div className="dw-form-divider" />

            {!ignoreZone && (
              <div className="dw-empty-state">No Flood Ignore Zone selected.</div>
            )}

            {ignoreZone && (
              <>
                <div className="dw-field">
                  <label htmlFor="dw-ignore-name">Flood Ignore Zone name</label>
                  <input
                    id="dw-ignore-name"
                    className="dw-input"
                    type="text"
                    maxLength={48}
                    value={ignoreZone.name || ''}
                    onChange={(e) => onUpdateIgnoreZone(ignoreZone.id, { name: e.target.value })}
                  />
                </div>

                <div className="dw-field-row2">
                  <div className="dw-field">
                    <label htmlFor="dw-ignore-fade">Fade distance</label>
                    <input
                      id="dw-ignore-fade"
                      className="dw-input"
                      type="number"
                      min="0"
                      max="2000"
                      step="10"
                      value={fadeDistance}
                      onChange={(e) => onUpdateIgnoreZone(ignoreZone.id, { fadeDistance: Number(e.target.value) })}
                    />
                  </div>
                  <div className="dw-field">
                    <label htmlFor="dw-ignore-color">Map color</label>
                    <input
                      id="dw-ignore-color"
                      className="dw-color-native"
                      type="color"
                      value={ignoreZone.mapColor || '#38bdf8'}
                      onChange={(e) => onUpdateIgnoreZone(ignoreZone.id, { mapColor: e.target.value })}
                    />
                  </div>
                </div>

                <div className="dw-field dw-field-row">
                  <span id="dw-ignore-enabled-label" className="dw-field-toggle-label">Flood ignore enabled</span>
                  <ToggleSwitch
                    labelledBy="dw-ignore-enabled-label"
                    checked={ignoreZone.enabled !== false}
                    onChange={(checked) => onUpdateIgnoreZone(ignoreZone.id, { enabled: checked })}
                  />
                </div>

                <div className="dw-points-panel">
                  <span className="dw-field-label">Polygon points ({points.length})</span>
                  <div className="dw-points-list">
                    {points.map((pt, i) => (
                      <div key={i} className="dw-point-row">
                        <span className="dw-point-index">{i}</span>
                        <input
                          type="number"
                          value={pt.x}
                          onChange={(e) => onUpdateIgnorePoints(ignoreZone.id, updatePoint(points, i, 'x', e.target.value))}
                          className="dw-input dw-point-input"
                          step="0.1"
                          aria-label={`Flood ignore vertex ${i} X`}
                        />
                        <input
                          type="number"
                          value={pt.y}
                          onChange={(e) => onUpdateIgnorePoints(ignoreZone.id, updatePoint(points, i, 'y', e.target.value))}
                          className="dw-input dw-point-input"
                          step="0.1"
                          aria-label={`Flood ignore vertex ${i} Y`}
                        />
                      </div>
                    ))}
                  </div>
                </div>
              </>
            )}
          </div>
        </div>
      </div>
    </aside>
  )
}
