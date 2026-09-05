import { useState, useRef, useEffect, useId } from 'react'

function ScaleIcon() {
  return (
    <svg className="dw-scale-trigger__svg" viewBox="0 0 24 24" fill="none" aria-hidden>
      <path
        d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function ScaleControl({ uiScale, onUiScaleChange }) {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef(null)
  const rangeRef = useRef(null)
  const popoverId = useId()

  useEffect(() => {
    if (!open) return
    const onKey = (e) => {
      if (e.key === 'Escape') setOpen(false)
    }
    const onPointerDown = (e) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('keydown', onKey)
    document.addEventListener('pointerdown', onPointerDown, true)
    queueMicrotask(() => rangeRef.current?.focus())
    return () => {
      document.removeEventListener('keydown', onKey)
      document.removeEventListener('pointerdown', onPointerDown, true)
    }
  }, [open])

  const pct = Math.round(uiScale * 100)

  return (
    <div className={`dw-scale${open ? ' dw-scale--open' : ''}`} ref={wrapRef}>
      <button
        type="button"
        className="dw-btn dw-scale-trigger"
        aria-expanded={open}
        aria-controls={popoverId}
        aria-haspopup="dialog"
        title={`Interface scale (${pct}%)`}
        onClick={() => setOpen((o) => !o)}
      >
        <ScaleIcon />
        <span className="dw-sr-only">Interface scale, {pct} percent. Opens scale slider.</span>
      </button>
      {open && (
        <div className="dw-scale-popover" id={popoverId} role="dialog" aria-label="Interface scale">
          <div className="dw-scale-popover-inner">
            <span className="dw-scale-popover-label">Scale</span>
            <input
              ref={rangeRef}
              type="range"
              className="dw-scale-range"
              aria-label="Scale percentage"
              aria-valuemin={88}
              aria-valuemax={158}
              aria-valuenow={pct}
              aria-valuetext={`${pct}%`}
              min={0.88}
              max={1.58}
              step={0.02}
              value={uiScale}
              onChange={(e) => onUiScaleChange(parseFloat(e.target.value))}
            />
            <span className="dw-scale-value" aria-hidden>
              {pct}%
            </span>
          </div>
        </div>
      )}
    </div>
  )
}

function SegmentToggle({ label, valueIndex, count = 2, children }) {
  return (
    <div
      className="dw-segment-toggle"
      role="group"
      aria-label={label}
      style={{ '--dw-segment-index': valueIndex, '--dw-segment-count': count }}
    >
      <span className="dw-segment-toggle__thumb" aria-hidden />
      {children}
    </div>
  )
}

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
        <ScaleControl uiScale={uiScale} onUiScaleChange={onUiScaleChange} />
        {drawMode && (
          <div className="dw-draw-tools">
            <SegmentToggle label="Draw shape" valueIndex={drawShape === 'polygon' ? 0 : 1}>
              <button
                type="button"
                className={`dw-segment-toggle__btn ${drawShape === 'polygon' ? 'is-active' : ''}`}
                aria-pressed={drawShape === 'polygon'}
                onClick={() => onDrawShapeChange('polygon')}
              >
                Polygon
              </button>
              <button
                type="button"
                className={`dw-segment-toggle__btn ${drawShape === 'rectangle' ? 'is-active' : ''}`}
                aria-pressed={drawShape === 'rectangle'}
                onClick={() => onDrawShapeChange('rectangle')}
              >
                Rectangle
              </button>
            </SegmentToggle>
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
        <button type="button" className="dw-btn" onClick={onLoad}>
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
