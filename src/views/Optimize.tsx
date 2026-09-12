import { useEffect, useMemo, useState } from 'react'
import {
  AlertTriangle,
  CheckCircle2,
  CheckSquare,
  Globe,
  Gauge,
  Layers,
  Play,
  RotateCcw,
  Shield,
  ShieldAlert,
  ShieldCheck,
  Sparkles,
  Trash2,
  XCircle,
} from 'lucide-react'
import { getCatalog, isAdmin, runPlan } from '../api'
import { LEVEL_NAME, MODES, MODE_NAME } from '../types'
import type { Cat, ItemOut, Opt } from '../types'

const CAT_ICON: Record<string, React.ReactNode> = {
  limpieza: <Trash2 size={15} />,
  rendimiento: <Gauge size={15} />,
  privacidad: <Shield size={15} />,
  redes: <Globe size={15} />,
}

export function Optimize({ onHistory }: { onHistory: () => void }) {
  const [catalog, setCatalog] = useState<Cat[]>([])
  const [mode, setMode] = useState<1 | 2 | 3>(2)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [restorePoint, setRestorePoint] = useState(true)
  const [catFilter, setCatFilter] = useState('all')
  const [running, setRunning] = useState(false)
  const [lastRun, setLastRun] = useState<RunResultView | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [admin, setAdmin] = useState<boolean | null>(null)

  useEffect(() => {
    getCatalog().then((cats) => {
      setCatalog(cats)
      setSelected(new Set(cats.flatMap((c) => c.items.filter((i) => i.level <= 2).map((i) => i.id))))
    })
    isAdmin().then(setAdmin)
  }, [])

  const allItems = useMemo(() => catalog.flatMap((c) => c.items), [catalog])

  const changeMode = (m: 1 | 2 | 3) => {
    setMode(m)
    setSelected(new Set(allItems.filter((i) => i.level <= m).map((i) => i.id)))
  }

  const toggle = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const chosen = allItems.filter((i) => selected.has(i.id))

  const apply = async () => {
    if (running || chosen.length === 0) return
    const ok = window.confirm(
      `¿Aplicar ${chosen.length} optimizaciones en modo ${MODE_NAME(mode)}?\n\n` +
        (restorePoint
          ? 'Se intentará crear un Punto de restauración antes de tocar nada (máx. 1 día).\n'
          : '') +
        'Aparecerá un aviso de Windows: acepta los permisos de administrador.',
    )
    if (!ok) return
    setRunning(true)
    setError(null)
    try {
      const rec = await runPlan(chosen, mode, restorePoint)
      setLastRun(recToView(rec))
    } catch (e) {
      setError(String(e))
    } finally {
      setRunning(false)
    }
  }

  const catCount = (id: string) => catalog.find((c) => c.id === id)?.items.length ?? 0

  return (
    <div className="stack">
      <header className="tool-header">
        <div className="tool-icon">
          <Sparkles size={22} />
        </div>
        <div>
          <h1>Optimización segura de Windows 11</h1>
          <p>
            Elige el modo, revisa los cambios y pulsa Aplicar. Todo queda registrado con
            reversión.
          </p>
        </div>
      </header>

      {error && (
        <div className="alert alert-error">
          <AlertTriangle size={16} />
          {error}
        </div>
      )}

      <div className={`alert ${admin ? 'alert-ok' : 'alert-warn'}`}>
        {admin === null ? null : admin ? (
          <>
            <ShieldCheck size={16} /> WinOpt corre con permisos de administrador.
          </>
        ) : (
          <>
            <ShieldAlert size={16} /> Modo seguro: cada cambio se lanzará elevado y Windows te
            pedirá permiso (UAC). Siempre podrás revertirlo desde Historial.
          </>
        )}
      </div>

      {/* Modos */}
      <div className="grid-3">
        {MODES.map((m) => (
          <button
            key={m.level}
            className={`mode-card mode-${m.color} ${mode === m.level ? 'selected' : ''}`}
            onClick={() => changeMode(m.level)}
          >
            <span className="mode-level">NIVEL {m.level}</span>
            <strong>{m.name}</strong>
            <small>{m.desc}</small>
          </button>
        ))}
      </div>

      <div className="row-between">
        <div className="chips">
          <button
            className={`chip ${catFilter === 'all' ? 'active' : ''}`}
            onClick={() => setCatFilter('all')}
          >
            <Layers size={14} /> Todo ({allItems.length})
          </button>
          {catalog.map((c) => (
            <button
              key={c.id}
              className={`chip ${catFilter === c.id ? 'active' : ''}`}
              onClick={() => setCatFilter(c.id)}
            >
              {CAT_ICON[c.id]}
              {c.name} ({catCount(c.id)})
            </button>
          ))}
        </div>
        <button className="btn" onClick={() => setSelected(new Set(allItems.filter((i) => i.level <= mode).map((i) => i.id)))}>
          <RotateCcw size={14} /> Restablecer a {MODE_NAME(mode)}
        </button>
      </div>

      {/* Lista de ítems */}
      <div className="items-list">
        {catalog
          .filter((c) => catFilter === 'all' || c.id === catFilter)
          .flatMap((c) =>
            c.items.map((i) => (
              <ItemRow key={i.id} item={i} checked={selected.has(i.id)} onToggle={toggle} />
            )),
          )}
      </div>

      <div className="row-between apply-bar">
        <div>
          <div className="apply-count">
            {chosen.length} de {allItems.length} cambios listos
          </div>
          <label className="check">
            <input
              type="checkbox"
              checked={restorePoint}
              onChange={(e) => setRestorePoint(e.target.checked)}
            />
            Crear punto de restauración antes de empezar
          </label>
        </div>
        <button className="btn btn-primary btn-big" onClick={apply} disabled={running || chosen.length === 0}>
          <Play size={17} />
          {running ? 'Ejecutando… acepta el aviso de Windows' : 'Aplicar optimización'}
        </button>
      </div>

      {lastRun && (
        <ResultsPanel run={lastRun} onHistory={onHistory} />
      )}
    </div>
  )
}

function ItemRow({
  item,
  checked,
  onToggle,
}: {
  item: Opt
  checked: boolean
  onToggle: (id: string) => void
}) {
  return (
    <label className={`item-row ${checked ? 'on' : ''} risk-${item.risk}`}>
      <input type="checkbox" checked={checked} onChange={() => onToggle(item.id)} />
      <div className="item-body">
        <div className="item-title">
          <span>{item.name}</span>
          <span className={`badge level-${item.level}`}>{LEVEL_NAME(item.level)}</span>
          <span className={`badge risk-${item.risk}`}>riesgo {item.risk}</span>
          {!item.undoable && <span className="badge risk-medio">sin undo</span>}
        </div>
        <small className="dim">{item.desc}</small>
      </div>
      <ChecKIcon checked={checked} />
    </label>
  )
}

function ChecKIcon({ checked }: { checked: boolean }) {
  return checked ? <CheckSquare size={18} className="gio-check" /> : <CheckSquare size={18} className="gio-uncheck" />
}

interface RunResultView {
  runId: string
  mode: number
  restore: boolean
  items: ItemOut[]
  ok: number
}

function recToView(r: { run_id: string; mode: number; restore_point_created: boolean; results: ItemOut[] }): RunResultView {
  return {
    runId: r.run_id,
    mode: r.mode,
    restore: r.restore_point_created,
    items: r.results,
    ok: r.results.filter((x) => x.status === 'ok').length,
  }
}

function ResultsPanel({ run, onHistory }: { run: RunResultView; onHistory: () => void }) {
  const fails = run.items.filter((x) => x.status === 'error').length
  return (
    <div className="results-panel">
      <div className="row-between">
        <h3 className="results-title">Resultado</h3>
        <span className={`badge level-${run.mode}`}>{MODE_NAME(run.mode)}</span>
      </div>
      <div className="results-grid">
        <div className="result-stat ok">
          <CheckCircle2 size={16} /> {run.ok} aplicados
        </div>
        <div className="result-stat">
          <span className={`${run.restore ? 'ok' : 'dim'}`}>
            {run.restore ? '✓' : '⚠'} punto de restauración {run.restore ? 'creado' : 'no disponible'}
          </span>
        </div>
        <div className="result-stat">
          {run.items.length - run.ok - fails} omitidos · {fails} errores
        </div>
      </div>
      <div className="items-list compact">
        {run.items.map((it) => (
          <div key={it.id} className={`item-out st-${it.status}`}>
            <StatusGlyph s={it.status} />
            <span className="item-out-name">{it.name}</span>
            <span className="item-out-detail dim">{it.detail || it.status}</span>
          </div>
        ))}
      </div>
      <p className="dim note">
        Los cambios <strong>reversibles</strong> de esta ejecución quedaron en el historial para
        revertirlos cuando quieras.
      </p>
      <button className="btn" onClick={onHistory}>
        <RotateCcw size={14} /> Ir a Historial para revertir
      </button>
    </div>
  )
}

function StatusGlyph({ s }: { s: string }) {
  switch (s) {
    case 'ok':
      return <CheckCircle2 size={15} className="ok" />
    case 'skipped':
      return <AlertTriangle size={15} className="warn" />
    case 'reverted':
      return <RotateCcw size={15} className="ok" />
    default:
      return <XCircle size={15} className="err" />
  }
}