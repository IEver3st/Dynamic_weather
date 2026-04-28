const RESOURCE_NAME = window.GetParentResourceName
  ? window.GetParentResourceName()
  : 'Dynamic_weather'

export function postNui(event, data = {}) {
  if (!window.GetParentResourceName) {
    return Promise.resolve({ ok: true, event, data })
  }

  return fetch(`https://${RESOURCE_NAME}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  }).then(async (res) => {
    const text = await res.text()
    if (!text) return { ok: true }

    try {
      return JSON.parse(text)
    } catch {
      return { ok: text === 'ok', raw: text }
    }
  })
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
