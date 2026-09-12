import { Archive, Info, RotateCcw, ShieldAlert, ShieldCheck } from 'lucide-react'

const FEATS = [
  { icon: <ShieldCheck size={18} />, title: 'Punto de restauración', desc: 'Antes de cada plan se intenta crear un punto de restauración para poder volver atrás en bloque.' },
  { icon: <RotateCcw size={18} />, title: 'Reversión individual', desc: 'Cada cambio guarda su valor anterior. Puedes revertir solo uno o toda la ejecución desde Historial.' },
  { icon: <Archive size={18} />, title: 'Log completo', desc: 'Todo queda en %LOCALAPPDATA%\\WinOpt\\history.json con fechas, modos y resultados.' },
  { icon: <ShieldAlert size={18} />, title: 'Nada destruye tus datos', desc: 'Solo borra archivos temporales con más de 24 h; nunca toca documentos, fotos ni programas instalados.' },
]

export function InfoView() {
  return (
    <div className="stack">
      <header className="tool-header">
        <div className="tool-icon">
          <Info size={22} />
        </div>
        <div>
          <h1>Acerca de WinOpt</h1>
          <p>Un optimizador de Windows 11 que prioriza seguridad y reversibilidad.</p>
        </div>
      </header>

      <div className="grid-3">
        {FEATS.map((f) => (
          <div key={f.title} className="feat-card">
            <span className="feat-icon">{f.icon}</span>
            <strong>{f.title}</strong>
            <small>{f.desc}</small>
          </div>
        ))}
      </div>

      <div className="info-panel">
        <h3>Cómo funciona</h3>
        <p>
          WinOpt ejecuta un motor PowerShell con permisos de administrador (te lo pide Windows
          con un aviso UAC). El motor aplica los cambios, guarda el valor <em>anterior</em> de
          cada ajuste y escribe el resultado en tu historial local. Nada sale de tu PC.
        </p>
        <h3>Los tres modos</h3>
        <ul>
          <li>
            <strong>Conservador</strong> — limpieza ligera y ajustes triviales. Nivel de riesgo
            mínimo.
          </li>
          <li>
            <strong>Equilibrado</strong> — lo recomendado: rendimiento útil, privacidad de
            telemetría y DNS rápido, sin tocar nada delicado.
          </li>
          <li>
            <strong>Agresivo</strong> — tuneo completo: desactivar SysMain, hibernación,
            telemetría a fondo y latencia de red. Piensa antes de pulsar.
          </li>
        </ul>
        <h3>Lo que NO hace</h3>
        <ul>
          <li>No desinstala programas (el bloatware se gestiona desde Configuración).</li>
          <li>No toca tu configuración de red VPN ni DNS si hay duda.</li>
          <li>No borra nada sin undo o sin un punto de restauración previo.</li>
        </ul>
        <p className="dim note">
          Proyecto personal de Luis Solano · 2026. Backend Rust + PowerShell · UI Tauri 2 + React.
        </p>
      </div>
    </div>
  )
}