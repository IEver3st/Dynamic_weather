export default function Toolbar({
  onAddZone,
  onAddRectZone,
  onSave,
  onLoad,
  onClose,
  drawMode,
  drawShape,
  onDrawShapeChange,
  message,
  dirty,
  uiScale,
  onUiScaleChange,
}) {
  return (
    <header className="dw-toolbar">
      <div className="dw-toolbar-left">
        <div className="dw-brand">
          <div className="dw-brand-text">
            <span className="dw-toolbar-title dw-toolbar-title-brand">DYNAMIC WEATHER</span>
            <span className="dw-brand-byline">// BY CORTEX</span>
          </div>
        </div>
        <div className="dw-toolbar-status" aria-live="polite">
          {message && <span className="dw-toolbar-msg">{message}</span>}
          {!message && dirty && <span className="dw-toolbar-msg dw-toolbar-warn">Unsaved changes</span>}
        </div>
      </div>
      <div className="dw-toolbar-center">
        <div className="dw-scale" title="Interface scale">
          <span className="dw-scale-label">Scale</span>
          <input
            type="range"
            className="dw-scale-range"
            aria-label="Interface scale"
            min={0.88}
            max={1.58}
            step={0.02}
            value={uiScale}
            onChange={(e) => onUiScaleChange(parseFloat(e.target.value))}
          />
          <span className="dw-scale-value">{Math.round(uiScale * 100)}%</span>
        </div>
        {drawMode && (
          <div className="dw-draw-tools" role="group" aria-label="Draw shape">
            <button
              type="button"
              className={`dw-chip ${drawShape === 'polygon' ? 'active' : ''}`}
              onClick={() => onDrawShapeChange('polygon')}
            >
              Polygon
            </button>
            <button
              type="button"
              className={`dw-chip ${drawShape === 'rectangle' ? 'active' : ''}`}
              onClick={() => onDrawShapeChange('rectangle')}
            >
              Rectangle
            </button>
          </div>
        )}
      </div>
      <div className="dw-toolbar-right">
        <button type="button" className="dw-btn" onClick={onAddZone} disabled={drawMode && drawShape === 'rectangle'}>
          {drawMode && drawShape === 'polygon' ? 'Drawing…' : '+ Polygon zone'}
        </button>
        <button
          type="button"
          className="dw-btn"
          onClick={onAddRectZone}
          disabled={drawMode && drawShape === 'polygon'}
        >
          {drawMode && drawShape === 'rectangle' ? 'Drawing…' : '+ Rectangle zone'}
        </button>
        <button type="button" className="dw-btn dw-btn-ghost" onClick={onLoad}>
          Load
        </button>
        <button type="button" className="dw-btn dw-btn-primary" onClick={onSave}>
          Save
        </button>
        <button type="button" className="dw-btn dw-btn-icon" onClick={onClose} title="Close (Esc)">
          ×
        </button>
      </div>
    </header>
  )
}
