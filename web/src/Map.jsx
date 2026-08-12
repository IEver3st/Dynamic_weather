import { useMemo, useCallback, useEffect } from 'react'
import {
  MapContainer,
  Polygon,
  CircleMarker,
  useMapEvents,
  useMap,
} from 'react-leaflet'
import L from 'leaflet'
import {
  OX_MAP_CENTER,
  OX_MIN_ZOOM,
  OX_MAX_ZOOM,
  OX_STARTUP_ZOOM,
  OX_MAP_BOUNDS,
  gameToMap,
  mapToGame,
} from './constants.js'
import { effectiveZoneMapColor } from './zoneColorUtils.js'

const ACCENT_STROKE = '#14b8a6'

function MapBootstrap() {
  const map = useMap()
  useEffect(() => {
    map.setMaxBounds(OX_MAP_BOUNDS)
    map.attributionControl?.setPrefix(false)
    const frame = requestAnimationFrame(() => {
      map.invalidateSize(false)
    })
    return () => cancelAnimationFrame(frame)
  }, [map])
  return null
}

function MapZoomControls() {
  const map = useMap()
  return (
    <div className="dw-map-overlay dw-map-zoom" aria-label="Map zoom">
      <button type="button" className="dw-map-zoom-btn" onClick={() => map.zoomIn()}>
        +
      </button>
      <button type="button" className="dw-map-zoom-btn" onClick={() => map.zoomOut()}>
        −
      </button>
    </div>
  )
}

function FitBoundsController({ fitSignal, zone }) {
  const map = useMap()
  useEffect(() => {
    if (!fitSignal || !zone?.points?.length) return
    const latlngs = zone.points.map((p) => gameToMap(p.x, p.y))
    if (latlngs.length === 1) {
      map.setView(latlngs[0], Math.min(OX_MAX_ZOOM, map.getZoom() + 1), { animate: true })
      return
    }
    const b = L.latLngBounds(latlngs)
    map.fitBounds(b, { padding: [32, 32], maxZoom: OX_MAX_ZOOM, animate: true })
  }, [fitSignal, zone, map])
  return null
}

function ClickHandler({ onClick }) {
  useMapEvents({
    click(e) {
      const { lat, lng } = e.latlng
      onClick(mapToGame(lat, lng))
    },
  })
  return null
}

function ZonePolygon({ zone, weather, isSelected, onClick }) {
  const color = effectiveZoneMapColor(zone, weather)

  const positions = useMemo(
    () => zone.points.map((p) => gameToMap(p.x, p.y)),
    [zone.points]
  )

  const pathOptions = useMemo(
    () => ({
      color: isSelected ? ACCENT_STROKE : color,
      weight: isSelected ? 3 : 2,
      fillColor: color,
      fillOpacity: isSelected ? 0.22 : 0.1,
      dashArray: zone.enabled === false ? '8 4' : undefined,
    }),
    [isSelected, color, zone.enabled]
  )

  const handleClick = useCallback(
    (e) => {
      L.DomEvent.stopPropagation(e)
      onClick(zone.id)
    },
    [zone.id, onClick]
  )

  const eventHandlers = useMemo(
    () => ({ click: handleClick }),
    [handleClick]
  )

  return (
    <Polygon
      positions={positions}
      pathOptions={pathOptions}
      eventHandlers={eventHandlers}
    />
  )
}

function FloodIgnorePolygon({ zone, isSelected, onClick }) {
  const color = zone.mapColor || '#38bdf8'
  const positions = useMemo(
    () => (zone.points || []).map((p) => gameToMap(p.x, p.y)),
    [zone.points]
  )

  const pathOptions = useMemo(
    () => ({
      color: isSelected ? '#e0f2fe' : color,
      weight: isSelected ? 3 : 2,
      fillColor: color,
      fillOpacity: isSelected ? 0.2 : 0.1,
      dashArray: zone.enabled === false ? '8 4' : '4 4',
    }),
    [isSelected, color, zone.enabled]
  )

  const handleClick = useCallback(
    (e) => {
      L.DomEvent.stopPropagation(e)
      onClick(zone.id)
    },
    [zone.id, onClick]
  )

  const eventHandlers = useMemo(
    () => ({ click: handleClick }),
    [handleClick]
  )

  if (positions.length < 3) return null

  return (
    <Polygon
      positions={positions}
      pathOptions={pathOptions}
      eventHandlers={eventHandlers}
    />
  )
}

function DrawPreview({ points, shape }) {
  if (!points || points.length === 0) return null

  if (shape === 'rectangle') {
    if (points.length === 1) {
      const [lat, lng] = gameToMap(points[0].x, points[0].y)
      return (
        <CircleMarker
          center={[lat, lng]}
          radius={7}
          pathOptions={{
            color: ACCENT_STROKE,
            weight: 2,
            fillColor: ACCENT_STROKE,
            fillOpacity: 0.35,
          }}
        />
      )
    }
  }

  const positions = points.map((p) => gameToMap(p.x, p.y))

  if (points.length === 1) {
    const [lat, lng] = gameToMap(points[0].x, points[0].y)
    return (
      <Polygon
        positions={[
          [lat - 0.05, lng - 0.05],
          [lat + 0.05, lng - 0.05],
          [lat + 0.05, lng + 0.05],
          [lat - 0.05, lng + 0.05],
        ]}
        pathOptions={{
          color: ACCENT_STROKE,
          weight: 2,
          fillColor: ACCENT_STROKE,
          fillOpacity: 0.28,
          dashArray: '6 3',
        }}
      />
    )
  }

  const closePositions = points.length >= 3 ? [...positions, positions[0]] : positions

  return (
    <Polygon
      positions={closePositions}
      pathOptions={{
        color: ACCENT_STROKE,
        weight: 2,
        fillColor: ACCENT_STROKE,
        fillOpacity: 0.14,
        dashArray: '6 3',
      }}
    />
  )
}

function SelectedZoneHandles({ zone, onUpdatePoints }) {
  const map = useMap()
  const dragRef = useMemo(() => ({ index: null }), [])

  useMapEvents({
    mousemove(e) {
      if (dragRef.index === null) return

      const { x, y } = mapToGame(e.latlng.lat, e.latlng.lng)
      const nextPoints = zone.points.map((point, index) =>
        index === dragRef.index ? { x, y } : point
      )
      onUpdatePoints(zone.id, nextPoints)
    },
  })

  return zone.points.map((point, index) => {
    const [lat, lng] = gameToMap(point.x, point.y)

    return (
      <CircleMarker
        key={`${zone.id}-${index}`}
        center={[lat, lng]}
        radius={6}
        pathOptions={{
          color: '#0c1211',
          weight: 2,
          fillColor: ACCENT_STROKE,
          fillOpacity: 1,
        }}
        eventHandlers={{
          mousedown(e) {
            L.DomEvent.stop(e)
            if (map.dragging?.enabled()) map.dragging.disable()
            dragRef.index = index
            const end = () => {
              dragRef.index = null
              if (map.dragging && !map.dragging.enabled()) map.dragging.enable()
              document.removeEventListener('pointerup', end)
              document.removeEventListener('mouseup', end)
            }
            document.addEventListener('pointerup', end)
            document.addEventListener('mouseup', end)
          },
        }}
      />
    )
  })
}

export default function MapCanvas({
  zones,
  floodIgnoreZones = [],
  states,
  activeLayer,
  selectedId,
  drawMode,
  drawShape,
  drawPoints,
  fitSignal,
  onMapClick,
  onSelectZone,
  onUpdatePoints,
}) {
  const activeItems = activeLayer === 'floods' ? floodIgnoreZones : zones
  const selectedZone = activeItems.find((zone) => zone.id === selectedId) || null
  const fitTarget = selectedZone

  return (
    <div className="dw-map-shell">
      <div className="dw-map-container">
        <MapContainer
          center={OX_MAP_CENTER}
          zoom={OX_STARTUP_ZOOM}
          minZoom={OX_MIN_ZOOM}
          maxZoom={OX_MAX_ZOOM}
          maxBounds={OX_MAP_BOUNDS}
          maxBoundsViscosity={1.0}
          zoomControl={false}
          crs={L.CRS.Simple}
          className="dw-map"
        >
          <MapBootstrap />
          <ClickHandler onClick={onMapClick} />
          <MapZoomControls />
          <FitBoundsController fitSignal={fitSignal} zone={fitTarget} />

          {activeLayer === 'zones' &&
            zones.map((zone) => (
              <ZonePolygon
                key={zone.id}
                zone={zone}
                weather={states[zone.id]?.currentWeather || 'CLEAR'}
                isSelected={zone.id === selectedId}
                onClick={onSelectZone}
              />
            ))}

          {activeLayer === 'floods' &&
            floodIgnoreZones.map((zone) => (
              <FloodIgnorePolygon
                key={zone.id}
                zone={zone}
                isSelected={zone.id === selectedId}
                onClick={onSelectZone}
              />
            ))}

          {drawMode && <DrawPreview points={drawPoints} shape={drawShape} />}

          {!drawMode && (activeLayer === 'zones' || activeLayer === 'floods') && selectedZone && selectedZone.points?.length >= 3 && (
            <SelectedZoneHandles zone={selectedZone} onUpdatePoints={onUpdatePoints} />
          )}
        </MapContainer>
      </div>
    </div>
  )
}
