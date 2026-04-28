import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'

/* FiveM CEF: window.confirm opens an OS-level dialog and drops game focus — forbid it. */
try {
  if (typeof GetParentResourceName === 'function') {
    window.confirm = (msg) => {
      console.warn('[dynamic_weather] window.confirm blocked in NUI:', msg)
      return false
    }
  }
} catch (_) {
  /* non-NUI / SSR */
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
