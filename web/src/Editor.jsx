import { useState, useCallback, useRef, useEffect } from 'react'
import { postNui, isBrowserMode } from './nui.js'
import Toolbar from './Toolbar.jsx'
import Sidebar from './Sidebar.jsx'
import MapCanvas from './Map.jsx'
import Inspector from './Inspector.jsx'
import FloodPanel from './FloodPanel.jsx'
import { defaultMapColorForIndex } from './zoneColorUtils.js'

const SCALE_KEY = 'dw_ui_scale'

const DEFAULT_FLOOD_SETTINGS = {
  enabled: true,
  chance: 0.08,
  maxOffset: 2,
  recommendedMaxOffset: 2,
  requireThunder: true,
  thunderCondition: 'any_zone',
  stormLeadSeconds: 45,
}

function readStoredScale() {
  try {
    const raw = localStorage.getItem(SCALE_KEY)
    const v = parseFloat(raw == null || raw === '' ? '1.15' : raw)
    if (Number.isFinite(v) && v >= 0.82 && v <= 1.58) return v
  } catch (_) {
    /* ignore */
  }
  return 1.15
}

export default function Editor({ payload, onClose }) {
  const [zones, setZones] = useState(payload?.zones || [])
  const [states, setStates] = useState(payload?.states || {})
  const [sequences, setSequences] = useState(payload?.sequences || {})
  const [floodSettings, setFloodSettings] = useState({ ...DEFAULT_FLOOD_SETTINGS, ...(payload?.floodSettings || {}) })
  const [floodIgnoreZones, setFloodIgnoreZones] = useState(payload?.floodIgnoreZones || [])
  const [activeLayer, setActiveLayer] = useState('zones')
  const [selectedId, setSelectedId] = useState(null)
  const [drawMode, setDrawMode] = useState(false)
  const [drawShape, setDrawShape] = useState('polygon')
  const [drawPoints, setDrawPoints] = useState([])
  const [dirty, setDirty] = useState(false)
  const [message, setMessage] = useState(null)
  const [uiScale, setUiScale] = useState(readStoredScale)
  const [fitSignal, setFitSignal] = useState(0)
  const [deleteConfirmId, setDeleteConfirmId] = useState(null)
  const messageTimer = useRef(null)
  const rectCornerRef = useRef(null)

  useEffect(() => {
    document.documentElement.style.setProperty('--es-ui-scale', String(uiScale))
    try {
      localStorage.setItem(SCALE_KEY, String(uiScale))
    } catch (_) {
      /* ignore */
    }
  }, [uiScale])

  useEffect(() => {
    if (payload?.zones) setZones(payload.zones)
    if (payload?.states) setStates(payload.states)
    if (payload?.sequences) setSequences(payload.sequences)
    if (payload?.floodSettings) {
      setFloodSettings((prev) => ({ ...prev, ...payload.floodSettings }))
    }
    if (payload?.floodIgnoreZones) setFloodIgnoreZones(payload.floodIgnoreZones)
  }, [payload])

  useEffect(() => {
    return () => {
      if (messageTimer.current) clearTimeout(messageTimer.current)
      postNui('dw_closeEditor')
    }
  }, [])

  useEffect(() => {
    if (!drawMode) {
      rectCornerRef.current = null
      setDrawPoints([])
    }
  }, [drawMode])

  useEffect(() => {
    if (!deleteConfirmId) return
    const exists = activeLayer === 'floods'
      ? floodIgnoreZones.some((z) => z.id === deleteConfirmId)
      : zones.some((z) => z.id === deleteConfirmId)
    if (!exists) setDeleteConfirmId(null)
  }, [zones, floodIgnoreZones, activeLayer, deleteConfirmId])

  const flashMessage = useCallback((text) => {
    setMessage(text)
    if (messageTimer.current) clearTimeout(messageTimer.current)
    messageTimer.current = setTimeout(() => setMessage(null), 3200)
  }, [])

  const selected = activeLayer === 'floods'
    ? floodIgnoreZones.find((z) => z.id === selectedId) || null
    : zones.find((z) => z.id === selectedId) || null

  const handleSave = useCallback(async () => {
    flashMessage('Saving...')
    await postNui('dw_saveZones', { zones })
    await postNui('dw_saveFloodSettings', { floodSettings })
    await postNui('dw_saveFloodIgnoreZones', { floodIgnoreZones })
    flashMessage('Zones and floods saved')
    setDirty(false)
  }, [zones, floodSettings, floodIgnoreZones, flashMessage])

  const handleLoad = useCallback(async () => {
    flashMessage('Loading from server...')
    await postNui('dw_loadZones')
    setTimeout(async () => {
      const resp = await postNui('dw_requestZones')
      if (resp.zones) setZones(resp.zones)
      if (resp.states) setStates(resp.states)
      if (resp.floodSettings) setFloodSettings((prev) => ({ ...prev, ...resp.floodSettings }))
      if (resp.floodIgnoreZones) setFloodIgnoreZones(resp.floodIgnoreZones)
      setDirty(false)
      flashMessage('Data reloaded')
    }, 300)
  }, [flashMessage])

  const beginNewZone = useCallback(
    (shape) => {
      if (drawMode) {
        setDrawMode(false)
        setDrawPoints([])
        rectCornerRef.current = null
        return
      }

      const newId = `zone_${Date.now()}`
      const newZone = {
        id: newId,
        label: `Zone ${zones.length + 1}`,
        points: [],
        sequence: 'urban_coastal',
        weatherPool: ['CLEAR', 'CLOUDS', 'EXTRASUNNY', 'OVERCAST'],
        transitionDuration: 15,
        thickness: 50.0,
        enabled: true,
        mapColor: defaultMapColorForIndex(zones.length),
      }
      setZones((prev) => [...prev, newZone])
      setActiveLayer('zones')
      setSelectedId(newId)
      setDrawShape(shape)
      setDrawMode(true)
      setDrawPoints([])
      rectCornerRef.current = null
      setDirty(true)
      flashMessage(
        shape === 'rectangle'
          ? 'Rectangle: first click a corner, then the opposite corner.'
          : 'Polygon: place vertices; click near the first point to close.'
      )
    },
    [drawMode, zones.length, flashMessage]
  )

  const handleAddZone = useCallback(() => beginNewZone('polygon'), [beginNewZone])
  const handleAddRectZone = useCallback(() => beginNewZone('rectangle'), [beginNewZone])

  const beginNewFloodIgnoreZone = useCallback(
    (shape) => {
      if (drawMode) {
        setDrawMode(false)
        setDrawPoints([])
        rectCornerRef.current = null
        return
      }

      const newId = `flood_ignore_${Date.now()}`
      const newZone = {
        id: newId,
        zoneType: 'flood_ignore',
        name: `Flood Ignore Zone ${floodIgnoreZones.length + 1}`,
        type: 'polygon',
        points: [],
        enabled: true,
        fadeDistance: 150,
        mapColor: '#38bdf8',
      }
      setFloodIgnoreZones((prev) => [...prev, newZone])
      setActiveLayer('floods')
      setSelectedId(newId)
      setDrawShape(shape)
      setDrawMode(true)
      setDrawPoints([])
      rectCornerRef.current = null
      setDirty(true)
      flashMessage(
        shape === 'rectangle'
          ? 'Rectangle ignore zone: place opposite corners.'
          : 'Polygon ignore zone: place vertices; click near start to close.'
      )
    },
    [drawMode, floodIgnoreZones.length, flashMessage]
  )

  const handleAddFloodIgnoreZone = useCallback(() => beginNewFloodIgnoreZone('polygon'), [beginNewFloodIgnoreZone])
  const handleAddFloodIgnoreRectZone = useCallback(() => beginNewFloodIgnoreZone('rectangle'), [beginNewFloodIgnoreZone])

  const handleDrawShapeChange = useCallback((shape) => {
    if (!drawMode) return
    setDrawShape(shape)
    setDrawPoints([])
    rectCornerRef.current = null
    flashMessage(shape === 'rectangle' ? 'Switched to rectangle draw.' : 'Switched to polygon draw.')
  }, [drawMode, flashMessage])

  const handleMapClick = useCallback(
    (latlng) => {
      if (!drawMode || (activeLayer !== 'zones' && activeLayer !== 'floods') || !selectedId) return

      const newPoint = { x: latlng.x, y: latlng.y }
      const applyPoints = (points) => {
        if (activeLayer === 'floods') {
          setFloodIgnoreZones((prevZones) =>
            prevZones.map((z) => (z.id === selectedId ? { ...z, points } : z))
          )
        } else {
          setZones((prevZones) =>
            prevZones.map((z) => (z.id === selectedId ? { ...z, points } : z))
          )
        }
      }

      if (drawShape === 'rectangle') {
        if (!rectCornerRef.current) {
          rectCornerRef.current = newPoint
          setDrawPoints([newPoint])
          return
        }
        const a = rectCornerRef.current
        const b = newPoint
        rectCornerRef.current = null
        const minX = Math.min(a.x, b.x)
        const maxX = Math.max(a.x, b.x)
        const minY = Math.min(a.y, b.y)
        const maxY = Math.max(a.y, b.y)
        applyPoints([
          { x: minX, y: minY },
          { x: maxX, y: minY },
          { x: maxX, y: maxY },
          { x: minX, y: maxY },
        ])
        setDirty(true)
        setDrawMode(false)
        setDrawPoints([])
        flashMessage(activeLayer === 'floods' ? 'Rectangle ignore zone completed' : 'Rectangle zone completed')
        return
      }

      setDrawPoints((prev) => {
        const updated = [...prev, newPoint]

        if (prev.length >= 2) {
          const first = prev[0]
          const dist = Math.sqrt((newPoint.x - first.x) ** 2 + (newPoint.y - first.y) ** 2)
          if (dist < 5) {
            applyPoints(prev)
            setDirty(true)
            setDrawMode(false)
            setDrawPoints([])
            flashMessage(activeLayer === 'floods' ? 'Ignore zone polygon completed' : 'Zone polygon completed')
            return prev
          }
        }

        return updated
      })
    },
    [drawMode, selectedId, activeLayer, drawShape, flashMessage]
  )

  const handleFinishDraw = useCallback(() => {
    if (drawShape === 'rectangle') {
      rectCornerRef.current = null
      setDrawPoints([])
      setDrawMode(false)
      flashMessage('Rectangle draw cancelled')
      return
    }
    if (drawPoints.length >= 3 && selectedId) {
      if (activeLayer === 'floods') {
        setFloodIgnoreZones((prev) =>
          prev.map((z) => (z.id === selectedId ? { ...z, points: drawPoints } : z))
        )
      } else {
        setZones((prev) =>
          prev.map((z) => (z.id === selectedId ? { ...z, points: drawPoints } : z))
        )
      }
      setDirty(true)
      flashMessage(activeLayer === 'floods' ? 'Ignore zone polygon completed' : 'Zone polygon completed')
    } else if (drawPoints.length > 0 && drawPoints.length < 3) {
      flashMessage('Need at least 3 points for a polygon')
    }
    setDrawMode(false)
    setDrawPoints([])
    rectCornerRef.current = null
  }, [drawPoints, selectedId, flashMessage, drawShape, activeLayer])

  const handleSelectZone = useCallback(
    (id) => {
      if (drawMode) handleFinishDraw()
      if (activeLayer !== 'floods') setActiveLayer('zones')
      setSelectedId(id)
    },
    [drawMode, handleFinishDraw, activeLayer]
  )

  const handleDeleteZone = useCallback(
    (id) => {
      if (activeLayer === 'floods') {
        setFloodIgnoreZones((prev) => prev.filter((z) => z.id !== id))
      } else {
        setZones((prev) => prev.filter((z) => z.id !== id))
      }
      if (selectedId === id) setSelectedId(null)
      setDirty(true)
      flashMessage(activeLayer === 'floods' ? 'Ignore zone deleted (unsaved)' : 'Zone deleted (unsaved)')
    },
    [selectedId, flashMessage, activeLayer]
  )

  const pendingDeleteItem = deleteConfirmId
    ? (activeLayer === 'floods' ? floodIgnoreZones : zones).find((z) => z.id === deleteConfirmId)
    : null

  const handleConfirmDeleteZone = useCallback(() => {
    if (!deleteConfirmId) return
    handleDeleteZone(deleteConfirmId)
    setDeleteConfirmId(null)
  }, [deleteConfirmId, handleDeleteZone])

  const handleUpdateZone = useCallback((id, updates) => {
    setDirty(true)
    setZones((prev) => prev.map((z) => (z.id === id ? { ...z, ...updates } : z)))
  }, [])

  const handleUpdatePoints = useCallback((id, points) => {
    setDirty(true)
    if (activeLayer === 'floods') {
      setFloodIgnoreZones((prev) => prev.map((z) => (z.id === id ? { ...z, points } : z)))
    } else {
      setZones((prev) => prev.map((z) => (z.id === id ? { ...z, points } : z)))
    }
  }, [activeLayer])

  const handleUpdateFloodIgnoreZone = useCallback((id, updates) => {
    setDirty(true)
    setFloodIgnoreZones((prev) => prev.map((z) => (z.id === id ? { ...z, ...updates } : z)))
  }, [])

  const handleUpdateFloodIgnorePoints = useCallback((id, points) => {
    setDirty(true)
    setFloodIgnoreZones((prev) => prev.map((z) => (z.id === id ? { ...z, points } : z)))
  }, [])

  const handleUpdateFloodSettings = useCallback((updates) => {
    setDirty(true)
    setFloodSettings((prev) => ({ ...prev, ...updates }))
  }, [])

  const handleDuplicateZone = useCallback(
    (zone) => {
      const newId = `zone_${Date.now()}`
      const copy = {
        ...zone,
        id: newId,
        label: `${zone.label || 'Zone'} copy`,
        points: (zone.points || []).map((p) => ({ x: p.x, y: p.y })),
      }
      setZones((prev) => [...prev, copy])
      setSelectedId(newId)
      setDirty(true)
      flashMessage('Zone duplicated (unsaved)')
    },
    [flashMessage]
  )

  const handleDuplicateFloodIgnoreZone = useCallback(
    (zone) => {
      const newId = `flood_ignore_${Date.now()}`
      const copy = {
        ...zone,
        id: newId,
        name: `${zone.name || 'Flood Ignore Zone'} copy`,
        points: (zone.points || []).map((p) => ({ x: p.x, y: p.y })),
      }
      setFloodIgnoreZones((prev) => [...prev, copy])
      setSelectedId(newId)
      setDirty(true)
      flashMessage('Ignore zone duplicated (unsaved)')
    },
    [flashMessage]
  )

  const handleFitMap = useCallback(() => {
    if (!selected?.points?.length) {
      flashMessage('Selected zone has no geometry yet')
      return
    }
    setFitSignal((n) => n + 1)
  }, [selected, flashMessage])

  const handleActiveLayerChange = useCallback(
    (layer) => {
      if (drawMode) handleFinishDraw()
      setActiveLayer(layer)
    },
    [drawMode, handleFinishDraw]
  )

  const handleClose = useCallback(async () => {
    await postNui('dw_closeEditor')
    onClose()
  }, [onClose])

  const handleEditorSetZoneWeather = useCallback(
    async (zoneId, weather) => {
      if (isBrowserMode()) {
        setStates((prev) => ({
          ...prev,
          [zoneId]: {
            ...(prev[zoneId] || {}),
            currentWeather: weather,
            nextWeather: weather,
          },
        }))
        flashMessage('Weather set (browser preview)')
        return
      }
      const r = await postNui('dw_editorSetZoneWeather', { zoneId, weather })
      if (r?.ok === false) flashMessage('Set weather failed')
      else flashMessage('Weather set for zone')
    },
    [flashMessage]
  )

  const handleEditorAdvanceZone = useCallback(
    async (zoneId) => {
      if (isBrowserMode()) {
        const z = zones.find((x) => x.id === zoneId)
        const pool = z?.weatherPool?.length ? z.weatherPool : ['CLEAR']
        setStates((prev) => {
          const cur = prev[zoneId]?.currentWeather || pool[0]
          const idx = Math.max(0, pool.indexOf(cur))
          const nextW = pool[(idx + 1) % pool.length]
          return {
            ...prev,
            [zoneId]: {
              ...(prev[zoneId] || {}),
              currentWeather: nextW,
              nextWeather: nextW,
            },
          }
        })
        flashMessage('Advanced (browser: cycles pool)')
        return
      }
      const r = await postNui('dw_editorAdvanceZone', { zoneId })
      if (r?.ok === false) flashMessage('Advance failed')
      else flashMessage('Sequence advanced for zone')
    },
    [zones, flashMessage]
  )

  return (
    <div className="dw-editor">
      {deleteConfirmId && pendingDeleteItem && (
        <div
          className="dw-modal-backdrop"
          role="dialog"
          aria-modal="true"
          aria-labelledby="dw-delete-zone-title"
          onClick={() => setDeleteConfirmId(null)}
        >
          <div className="dw-modal" onClick={(e) => e.stopPropagation()}>
            <p id="dw-delete-zone-title" className="dw-modal-title">Delete this zone?</p>
            <p className="dw-modal-subtitle">{pendingDeleteItem.name || pendingDeleteItem.label || pendingDeleteItem.id}</p>
            <div className="dw-modal-actions">
              <button type="button" className="dw-btn dw-btn-ghost" onClick={() => setDeleteConfirmId(null)}>
                Cancel
              </button>
              <button type="button" className="dw-btn dw-btn-danger" onClick={handleConfirmDeleteZone}>
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
      <Toolbar
        onAddZone={handleAddZone}
        onAddRectZone={handleAddRectZone}
        onAddFloodIgnoreZone={handleAddFloodIgnoreZone}
        onAddFloodIgnoreRectZone={handleAddFloodIgnoreRectZone}
        activeLayer={activeLayer}
        onActiveLayerChange={handleActiveLayerChange}
        onSave={handleSave}
        onLoad={handleLoad}
        onClose={handleClose}
        drawMode={drawMode}
        drawShape={drawShape}
        onDrawShapeChange={handleDrawShapeChange}
        message={message}
        dirty={dirty}
        uiScale={uiScale}
        onUiScaleChange={setUiScale}
      />
      <div className="dw-workspace">
        <Sidebar
          zones={zones}
          floodIgnoreZones={floodIgnoreZones}
          states={states}
          activeLayer={activeLayer}
          selectedId={selectedId}
          onSelect={handleSelectZone}
          onRequestDelete={(id) => setDeleteConfirmId(id)}
        />
        <MapCanvas
          zones={zones}
          floodIgnoreZones={floodIgnoreZones}
          states={states}
          activeLayer={activeLayer}
          selectedId={selectedId}
          drawMode={drawMode}
          drawShape={drawShape}
          drawPoints={drawPoints}
          fitSignal={fitSignal}
          onMapClick={handleMapClick}
          onSelectZone={handleSelectZone}
          onUpdatePoints={handleUpdatePoints}
        />
        {activeLayer === 'floods' ? (
          <FloodPanel
            settings={floodSettings}
            ignoreZone={selected}
            onUpdate={handleUpdateFloodSettings}
            onUpdateIgnoreZone={handleUpdateFloodIgnoreZone}
            onUpdateIgnorePoints={handleUpdateFloodIgnorePoints}
            onDuplicateIgnoreZone={handleDuplicateFloodIgnoreZone}
            onFitMap={handleFitMap}
          />
        ) : (
          <Inspector
            zone={selected}
            states={states}
            sequences={sequences}
            onUpdateZone={handleUpdateZone}
            onUpdatePoints={handleUpdatePoints}
            onDuplicate={handleDuplicateZone}
            onFitMap={handleFitMap}
            onSetZoneWeather={handleEditorSetZoneWeather}
            onAdvanceZoneWeather={handleEditorAdvanceZone}
          />
        )}
      </div>
      {drawMode && (
        <div className="dw-draw-indicator" role="status">
          <span>
            {drawShape === 'rectangle'
              ? 'Rectangle: place opposite corners on the map.'
              : 'Polygon: place points; click near start to close.'}
          </span>
          <button type="button" onClick={handleFinishDraw}>
            {drawShape === 'rectangle' ? 'Cancel' : `Finish (${drawPoints.length} pts)`}
          </button>
        </div>
      )}
      <footer className="dw-editor-foot">
        <span>Esc - close editor / F10 - force close if UI freezes</span>
        <span>Floods - controls natural flood chance, map-wide sea offset, and local ignore zones</span>
      </footer>
    </div>
  )
}
