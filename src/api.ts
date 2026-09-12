import { invoke } from '@tauri-apps/api/core'
import type { Cat, Opt, RunRecord, RunSummary } from './types'

export function getCatalog(): Promise<Cat[]> {
  return invoke<Cat[]>('get_catalog')
}

export function isAdmin(): Promise<boolean> {
  return invoke<boolean>('is_admin')
}

export function getRuns(): Promise<RunSummary[]> {
  return invoke<RunSummary[]>('get_runs')
}

export function getRun(runId: string): Promise<RunRecord | null> {
  return invoke<RunRecord | null>('get_run', { runId })
}

export function runPlan(
  items: Opt[],
  mode: number,
  restorePoint: boolean,
): Promise<RunRecord> {
  return invoke<RunRecord>('run_plan', {
    plan: { items: items.map((i) => i.id), mode, restore_point: restorePoint },
  })
}

export function undoRun(runId: string): Promise<RunRecord> {
  return invoke<RunRecord>('undo_run', { runId })
}

export function undoItem(runId: string, itemId: string): Promise<RunRecord> {
  return invoke<RunRecord>('undo_item', { runId, itemId })
}