const RESOURCE_NAME = window.GetParentResourceName
  ? window.GetParentResourceName()
  : 'Dynamic_weather'
const EVENT_PATTERN = /^[A-Za-z0-9:_-]{1,64}$/

export async function postNui(event, data = {}, timeoutMs = 5000) {
  if (!EVENT_PATTERN.test(event)) {
    throw new Error('Invalid NUI event')
  }

  if (!window.GetParentResourceName) {
    return { ok: true, event, data }
  }

  const controller = new AbortController()
  const timer = window.setTimeout(() => controller.abort(), timeoutMs)

  try {
    const res = await fetch(`https://${RESOURCE_NAME}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
      signal: controller.signal,
    })

    if (!res.ok) {
      throw new Error(`NUI request failed with status ${res.status}`)
    }

    const text = await res.text()
    if (!text) return { ok: true }

    try {
      return JSON.parse(text)
    } catch {
      return { ok: text === 'ok', raw: text }
    }
  } finally {
    window.clearTimeout(timer)
  }
}

export function onNuiMessage(callback) {
  const handler = (e) => {
    callback(e.data)
  }

  window.addEventListener('message', handler)

  return () => {
    window.removeEventListener('message', handler)
  }
}

export function isBrowserMode() {
  return !window.GetParentResourceName
}
