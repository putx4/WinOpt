import { useEffect, useState } from 'react'
import {
  CalendarClock,
  ChevronDown,
  ChevronRight,
  History as HistoryIcon,
  RotateCcw,
  ShieldCheck,
} from 'lucide-react'
import { getRun, getRuns, undoItem, undoRun } from '../api'
import { MODE_NAME } from '../types'
import type { ItemOut, RunRecord, RunSummary } from '../types'

export function HistoryView() {
  const [runs, setRuns] = useState<RunSummary[]>([])
  const [open, setOpen] = useState<string | null>(null)
  const [detail, setDetail] = useState<RunRecord | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refresh = () => getRuns().then(setRuns)

  useEffect(() => {
    refresh()
  }, [])

  const expand = async (id: string) => {
    if (open === id) {
      setOpen(null)
      setDetail(null)
      return
    }
    setOpen(id)
    setDetail(null)
    const rec = await getRun(id)
    if (rec) setDetail(rec)
  }

  const revert = async (what: 'run' | string, runId: string) => {
    if (busy) return
    const ok = window.confirm(
      what === 'run'
        ? '¿Revertir TODOS los cambios reversibles de esta ejecución?'
        : '¿Revertir este cambio solo?',
    )
    if (!ok) return
    setBusy(true)
    setError(null)
    try {
      if (what === 'run') await undoRun(runId)
      else await undoItem(runId, what)
      await refresh()
      const rec = await getRun(open!)
      if (rec) setDetail(rec)
    } catch (e) {
      setError(String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="stack">
      <header className="tool-header">
        <div className="tool-icon">
          <HistoryIcon size={22} />
        </div>
        <div>
          <h1>Historial de optimización</h1>
          <p>Cada ejecución queda registrada. Revertir es seguro y reversible.</p>
        </div>
      </header>

      {error && <div className="alert alert-error">{error}</div>}

      {runs.length === 0 && (
        <div className="empty">
          <CalendarClock size={28} />
          <p>
            Todavía no hay ejecuciones. Ve a <strong>Optimizar</strong> y aplica tu primer
            plan.
          </p>
        </div>
      )}

      <div className="history-list">
        {runs.map((r) => (
          <div key={r.run_id} className="history-block">
            <button className="history-item" onClick={() => expand(r.run_id)}>
              {open === r.run_id ? <ChevronDown size={15} /> : <ChevronRight size={15} />}
              <span className="text">
                {r.created}
                <span className={`badge level-${r.mode}`}>{MODE_NAME(r.mode)}</span>
                <span className="dim">
                  {' '}
                  · {r.ok}/{r.total} aplicados
                </span>
              </span>
              <span className="time">
                {r.restore_point_created && (
                  <ShieldCheck size={14} className="ok" aria-label="Punto de restauración creado" />
                )}
              </span>
            </button>

            {open === r.run_id && detail && (
              <div className="history-detail">
                {detail.results.length > 0 && (
                  <div className="items-list compact">
                    {detail.results.map((it) => (
                      <div key={it.id} className={`item-out st-${it.status}`}>
                        <span className="item-out-name">{it.name}</span>
                        <span className="item-out-detail dim">{it.detail || it.status}</span>
                        {!!it.undo && it.status === 'ok' && (
                          <button
                            className="btn btn-mini"
                            disabled={busy}
                            onClick={() => revert(it.id, r.run_id)}
                          >
                            <RotateCcw size={12} /> revertir
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                )}
                <div className="row-between history-actions">
                  <span className="dim">
                    {detail.results.filter((x: ItemOut) => x.undo).length} cambios reversibles
                  </span>
                  <button
                    className="btn btn-magenta btn-mini"
                    disabled={busy || detail.results.filter((x: ItemOut) => x.undo && x.status === 'ok').length === 0}
                    onClick={() => revert('run', r.run_id)}
                  >
                    <RotateCcw size={13} /> Revertir todo
                  </button>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}