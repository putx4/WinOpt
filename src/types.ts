export interface Opt {
  id: string
  name: string
  desc: string
  level: 1 | 2 | 3
  risk: 'bajo' | 'medio' | 'alto'
  undoable: boolean
}

export interface Cat {
  id: string
  name: string
  icon: string
  color: string
  items: Opt[]
}

export interface ItemOut {
  id: string
  name: string
  ok: boolean
  applied: boolean
  detail: string
  status: 'ok' | 'skipped' | 'error' | 'reverted'
  undo: unknown
}

export interface RunRecord {
  run_id: string
  created: string
  mode: 1 | 2 | 3
  restore_point_created: boolean
  results: ItemOut[]
}

export interface RunSummary {
  run_id: string
  created: string
  mode: 1 | 2 | 3
  ok: number
  total: number
  restore_point_created: boolean
}

export const MODES = [
  { level: 1, name: 'Conservador', desc: 'Limpieza ligera y cambios reversibles. Ideal para no romper nada.', color: 'green' },
  { level: 2, name: 'Equilibrado', desc: 'Rendimiento, privacidad y red sin tocar nada delicado. Recomendado.', color: 'cyan' },
  { level: 3, name: 'Agresivo', desc: 'Tuneo completo: telemetría, servicios y latencia al máximo.', color: 'purple' },
] as const

export const MODE_NAME = (m: number): string =>
  MODES.find((x) => x.level === m)?.name ?? `Modo ${m}`

export const LEVEL_NAME = (l: number): string =>
  l === 1 ? '1 · Conservador' : l === 2 ? '2 · Equilibrado' : '3 · Agresivo'