import { useState } from 'react'
import { Gauge, History, Info, ShieldCheck } from 'lucide-react'
import { Optimize } from './views/Optimize'
import { HistoryView } from './views/History'
import { InfoView } from './views/Info'

type NavId = 'optimize' | 'history' | 'info'

const NAV: { id: NavId; label: string; hint: string; icon: React.ReactNode }[] = [
  { id: 'optimize', label: 'Optimizar', hint: 'Aplica cambios seguros', icon: <Gauge size={18} /> },
  { id: 'history', label: 'Historial', hint: 'Ejecuciones y revertir', icon: <History size={18} /> },
  { id: 'info', label: 'Acerca', hint: 'Qué hace WinOpt', icon: <Info size={18} /> },
]

export default function App() {
  const [nav, setNav] = useState<NavId>('optimize')

  return (
    <div className="hud-bg">
      <div className="app-shell">
        <aside className="sidebar">
          <div className="sidebar-logo">
            <ShieldCheck size={22} className="logo-glow" />
            <span>
              WIN<span className="logo-glow">OPT</span>
              <small className="dim logo-sub">· windows 11</small>
            </span>
          </div>
          <p className="sidebar-title">Optimizador seguro</p>
          {NAV.map((n) => (
            <button
              key={n.id}
              className={`nav-item ${nav === n.id ? 'active' : ''}`}
              onClick={() => setNav(n.id)}
            >
              {n.icon}
              <span>
                {n.label}
                <br />
                <small className="dim">{n.hint}</small>
              </span>
            </button>
          ))}
          <div className="sidebar-foot">
            <small>
              Restore point + log
              <br />+ undo en cada cambio
            </small>
          </div>
        </aside>

        <main className="main">
          {nav === 'optimize' && <Optimize onHistory={() => setNav('history')} />}
          {nav === 'history' && <HistoryView />}
          {nav === 'info' && <InfoView />}
        </main>
      </div>
    </div>
  )
}