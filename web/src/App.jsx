import { useState, useEffect, useLayoutEffect, useCallback } from 'react'
import { postNui, onNuiMessage, isBrowserMode } from './nui.js'
import Editor from './Editor.jsx'

const BROWSER_PAYLOAD = {
  zones: [
    {
      id: 'downtown_ls',
      label: 'Downtown Los Santos',
      points: [
        { x: 150, y: -280 },
        { x: 400, y: -280 },
        { x: 400, y: -520 },
        { x: 320, y: -620 },
        { x: 200, y: -580 },
        { x: 150, y: -520 },
      ],
      sequence: 'urban_coastal',
      weatherPool: ['CLEAR', 'CLOUDS', 'EXTRASUNNY', 'OVERCAST', 'RAIN'],
      transitionDuration: 15,
      thickness: 50,
      enabled: true,
      mapColor: '#14b8a6',
    },
    {
      id: 'sandy_airfield',
      label: 'Sandy Shores',
      points: [
        { x: 1380, y: 3660 },
        { x: 1580, y: 3660 },
        { x: 1580, y: 3460 },
        { x: 1380, y: 3460 },
      ],
      sequence: 'desert_inland',
      weatherPool: ['CLEAR', 'EXTRASUNNY', 'SMOG', 'OVERCAST'],
      transitionDuration: 22,
      thickness: 60,
      enabled: true,
      mapColor: '#e07c5c',
    },
    {
      id: 'paleto_strip',
      label: 'Paleto Bay',
      points: [
        { x: -120, y: 6420 },
        { x: 80, y: 6420 },
        { x: 80, y: 6280 },
        { x: -120, y: 6280 },
      ],
      sequence: 'rural_farmland',
      weatherPool: ['CLOUDS', 'OVERCAST', 'FOGGY', 'RAIN'],
      transitionDuration: 18,
      thickness: 45,
      enabled: true,
      mapColor: '#3b82c4',
    },
  ],
  states: {
    downtown_ls: { currentWeather: 'RAIN', nextWeather: 'CLOUDS' },
    sandy_airfield: { currentWeather: 'EXTRASUNNY', nextWeather: 'CLEAR' },
    paleto_strip: { currentWeather: 'FOGGY', nextWeather: 'OVERCAST' },
  },
  sequences: {
    urban_coastal: { label: 'Urban Coastal' },
    desert_inland: { label: 'Desert Inland' },
    mountain_alpine: { label: 'Mountain Alpine' },
    rural_farmland: { label: 'Rural Farmland' },
    tropical_coast: { label: 'Tropical Coast' },
  },
  floodSettings: {
    enabled: true,
    chance: 0.08,
    maxOffset: 2,
    recommendedMaxOffset: 2,
    requireThunder: true,
    thunderCondition: 'any_zone',
    stormLeadSeconds: 45,
  },
  floodIgnoreZones: [
    {
      id: 'flood_ignore_sandy_preview',
      zoneType: 'flood_ignore',
      name: 'Flood Ignore Zone',
      type: 'polygon',
      enabled: true,
      fadeDistance: 250,
      mapColor: '#38bdf8',
      points: [
        { x: 1180, y: 3980 },
        { x: 2620, y: 3980 },
        { x: 2620, y: 3080 },
        { x: 1180, y: 3080 },
      ],
    },
  ],
}

export default function App() {
  const [open, setOpen] = useState(false)
  const [payload, setPayload] = useState(null)

  const handleMessage = useCallback((data) => {
    if (!data || !data.type) return

    switch (data.type) {
      case 'openEditor':
        setOpen(true)
        setPayload(data.payload || {})
        break
      case 'editorData':
        setPayload((prev) => ({ ...prev, ...data.payload }))
        break
      case 'closeEditor':
        setOpen(false)
        setPayload(null)
        break
    }
  }, [])

  useEffect(() => {
    if (isBrowserMode()) {
      setOpen(true)
      setPayload(BROWSER_PAYLOAD)
      return
    }

    const cleanup = onNuiMessage(handleMessage)
    return cleanup
  }, [handleMessage])

  useEffect(() => {
    const handler = (e) => {
      if (e.key === 'Escape' && open) {
        postNui('dw_closeEditor')
        setOpen(false)
        setPayload(null)
      }
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [open])

  useEffect(() => {
    if (!open || isBrowserMode()) return
    postNui('dw_editorPing', {}).catch(() => {})
    const id = setInterval(() => {
      postNui('dw_editorPing', {}).catch(() => {})
    }, 2000)
    return () => clearInterval(id)
  }, [open])

  // FiveM CEF often paints a solid gray frame *before* #root is hidden if we use useEffect; empty #root
  // (after `return null`) is still full-size for one frame. useLayoutEffect runs before CEF blits. For
  // NUI, hide the whole document when idle; otherwise body/html still composite as a flat panel.
  useLayoutEffect(() => {
    const root = document.getElementById('root')
    if (!root) return

    if (isBrowserMode()) {
      if (!open) {
        root.style.setProperty('display', 'none')
        root.style.setProperty('pointer-events', 'none')
      } else {
        root.style.removeProperty('display')
        root.style.removeProperty('pointer-events')
      }
      return
    }

    const { body, documentElement } = document
    if (!open) {
      documentElement.style.setProperty('display', 'none')
      body.style.setProperty('display', 'none')
      root.style.setProperty('display', 'none')
      body.style.setProperty('pointer-events', 'none')
      documentElement.style.setProperty('pointer-events', 'none')
    } else {
      documentElement.style.removeProperty('display')
      body.style.removeProperty('display')
      documentElement.style.removeProperty('pointer-events')
      body.style.removeProperty('pointer-events')
      root.style.removeProperty('display')
      root.style.removeProperty('pointer-events')
    }
  }, [open])

  if (!open) return null

  return <Editor payload={payload} onClose={() => { setOpen(false); setPayload(null) }} />
}
