export default function ToggleSwitch({ id, labelledBy, checked, onChange, className = '' }) {
  return (
    <button
      type="button"
      id={id}
      role="switch"
      aria-checked={checked}
      aria-labelledby={labelledBy}
      className={`dw-toggle ${checked ? 'dw-toggle-on' : ''} ${className}`.trim()}
      onClick={() => onChange(!checked)}
    >
      <span className="dw-toggle-track" aria-hidden="true">
        <span className="dw-toggle-thumb" />
      </span>
    </button>
  )
}
