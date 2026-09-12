use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use chrono::Local;
use serde_json::{json, Value};

use crate::models::*;

const ENGINE_PS1: &str = include_str!("../resources/engine.ps1");

// ── Rutas de datos (AppData\Local\WinOpt) ─────────────────────

fn base_dir() -> PathBuf {
  let local = std::env::var_os("LOCALAPPDATA")
    .map(PathBuf::from)
    .unwrap_or_else(|| PathBuf::from("."));
  local.join("WinOpt")
}

fn ensure_dir() -> Result<PathBuf, String> {
  let dir = base_dir();
  fs::create_dir_all(&dir).map_err(|e| format!("No se pudo crear {}: {}", dir.display(), e))?;
  Ok(dir)
}

fn write_helper_scripts(dir: &Path) -> Result<(), String> {
  let engine = dir.join("engine.ps1");
  fs::write(&engine, ENGINE_PS1).map_err(|e| format!("No se pudo escribir engine.ps1: {}", e))?;

  let launcher = dir.join("launcher.ps1");
  let launcher_src = r#"param(
  [string]$Engine,
  [string]$Plan,
  [string]$Output,
  [string]$RunId,
  [string]$Undo
)
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $Engine)
if ($Plan)   { $args += @('-PlanPath', $Plan) }
if ($Output) { $args += @('-OutputPath', $Output) }
if ($RunId)  { $args += @('-RunId', $RunId) }
if ($Undo)   { $args += @('-UndoPath', $Undo) }
Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList $args
exit 0
"#;
  fs::write(&launcher, launcher_src).map_err(|e| format!("No se pudo escribir launcher.ps1: {}", e))
}

/// Lanza el engine ELEVADO (UAC) vía launcher. Devuelve Ok(true) si corrió.
fn run_elevated(args: Vec<&str>) -> Result<(), String> {
  let dir = ensure_dir()?;
  write_helper_scripts(&dir)?;
  let launcher = dir.join("launcher.ps1");

  // Quoting de args que se pasan al launcher sí/no espaciados; las rutas no llevan espacios.
  let mut cmd = Command::new("powershell.exe");
  cmd.arg("-NoProfile").arg("-NonInteractive").arg("-ExecutionPolicy").arg("Bypass")
     .arg("-File").arg(&launcher);
  for a in args {
    cmd.arg(a);
  }
  let out = cmd.output().map_err(|e| format!("No se pudo lanzar PowerShell: {}", e))?;
  let _stderr = String::from_utf8_lossy(&out.stderr).to_string();
  Ok(())
}

fn read_history() -> Vec<RunRecord> {
  let path = base_dir().join("history.json");
  let raw = match fs::read_to_string(&path) {
    Ok(r) => r,
    Err(_) => return Vec::new(),
  };
  match serde_json::from_str::<Value>(&raw) {
    Ok(v) => match v.get("runs") {
      Some(runs) => serde_json::from_value(runs.clone()).unwrap_or_default(),
      None => Vec::new(),
    },
    Err(_) => Vec::new(),
  }
}

fn write_history(runs: &[RunRecord]) -> Result<(), String> {
  let dir = ensure_dir()?;
  let path = dir.join("history.json");
  let data = json!({ "runs": runs });
  fs::write(&path, serde_json::to_string_pretty(&data).unwrap())
    .map_err(|e| format!("No se pudo guardar el historial: {}", e))
}

fn now_ts() -> String {
  Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
}

// ── Comandos expuestos a la UI ────────────────────────────────

#[tauri::command]
pub fn get_catalog() -> Vec<Cat> {
  catalog()
}

#[tauri::command]
pub fn is_admin() -> bool {
  let probe = r#"[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator"#;
  let script = format!("({})", probe);
  match Command::new("powershell.exe")
    .arg("-NoProfile").arg("-NonInteractive").arg("-Command").arg(&script)
    .output()
  {
    Ok(o) => String::from_utf8_lossy(&o.stdout).trim().contains("True"),
    Err(_) => false,
  }
}

#[tauri::command]
pub fn get_runs() -> Vec<RunSummary> {
  read_history().iter().map(RunSummary::from_record).collect()
}

#[tauri::command]
pub fn get_run(run_id: String) -> Option<RunRecord> {
  read_history().into_iter().find(|r| r.run_id == run_id)
}

#[tauri::command]
pub fn run_plan(plan: PlanReq) -> Result<RunRecord, String> {
  if plan.items.is_empty() {
    return Err("No elegiste ninguna optimización.".into());
  }
  // Validar ids contra el catálogo
  for id in &plan.items {
    if find_item(id).is_none() {
      return Err(format!("Id desconocido en plan: {}", id));
    }
  }

  let dir = ensure_dir()?;
  let run_id = format!("winopt_{}", Local::now().format("%Y%m%d_%H%M%S"));
  let plan_path = dir.join(format!("{}.plan.json", run_id));
  let out_path = dir.join(format!("{}.out.json", run_id));

  let items_json: Vec<Value> = plan
    .items
    .iter()
    .map(|id| {
      let name = find_item(id)
        .map(|(_, _, o)| o.name.to_string())
        .unwrap_or_else(|| id.clone());
      json!({ "id": id, "name": name })
    })
    .collect();

  let plan_json = json!({
    "run_id": run_id,
    "mode": plan.mode,
    "restore_point": plan.restore_point,
    "items": items_json,
  });

  fs::write(&plan_path, serde_json::to_string(&plan_json).unwrap())
    .map_err(|e| format!("No se pudo escribir el plan: {}", e))?;

  // Arranca PowerShell elevado. La UAC le pide permiso al usuario.
  let res = run_elevated(vec![
    "-Engine",
    dir.join("engine.ps1").to_str().unwrap(),
    "-Plan",
    plan_path.to_str().unwrap(),
    "-Output",
    out_path.to_str().unwrap(),
    "-RunId",
    &run_id,
  ]);

  // Limpiar plan temporal
  let _ = fs::remove_file(&plan_path);

  let raw = match fs::read_to_string(&out_path) {
    Ok(r) => r.trim_start_matches('\u{feff}').to_string(),
    Err(_) => {
      if res.is_ok() {
        return Err("La operación fue cancelada (no aceptaste el permiso de administrador).".into());
      }
      return Err(format!("No se pudo ejecutar: {:?}", res.err().unwrap_or_default()));
    }
  };

  let engine_out: EngineOut = serde_json::from_str(&raw)
    .map_err(|e| format!("Respuesta inválida del motor: {}", e))?;
  let _ = fs::remove_file(&out_path);

  let mut record: RunRecord = engine_out.into();
  record.run_id = run_id;
  record.created = now_ts();
  record.mode = plan.mode;

  let mut runs = read_history();
  runs.push(record.clone());
  write_history(&runs)?;

  Ok(record)
}

fn undo_common(run_id: &str, only: Option<&str>) -> Result<RunRecord, String> {
  let mut runs = read_history();
  let idx = runs.iter().position(|r| r.run_id == run_id)
    .ok_or_else(|| "No se encontró esa ejecución en el historial.".to_string())?;

  let steps: Vec<Value> = runs[idx]
    .results
    .iter()
    .filter(|it| match only {
      Some(id) => it.id == id,
      None => true,
    })
    .filter(|it| it.undo.is_some())
    .map(|it| json!({ "item": it.id, "undo": it.undo }))
    .collect();

  if steps.is_empty() {
    return Err("No hay cambios reversibles en esta ejecución.".into());
  }

  let dir = ensure_dir()?;
  let undo_path = dir.join(format!("undo_{}.json", run_id));
  let out_path = dir.join(format!("undo_{}.out.json", run_id));
  fs::write(&undo_path, serde_json::to_string(&json!({ "steps": steps })).unwrap())
    .map_err(|e| format!("No se pudo escribir el plan de undo: {}", e))?;

  let res = run_elevated(vec![
    "-Engine",
    dir.join("engine.ps1").to_str().unwrap(),
    "-Undo",
    undo_path.to_str().unwrap(),
    "-Output",
    out_path.to_str().unwrap(),
  ]);
  let _ = fs::remove_file(&undo_path);

  let raw = match fs::read_to_string(&out_path) {
    Ok(r) => r.trim_start_matches('\u{feff}').to_string(),
    Err(_) => {
      if res.is_ok() {
        return Err("La reversión fue cancelada (no aceptaste el permiso de administrador).".into());
      }
      return Err(format!("No se pudo ejecutar: {:?}", res.err().unwrap_or_default()));
    }
  };
  let _engine_out: EngineOut = serde_json::from_str(&raw)
    .map_err(|e| format!("Respuesta inválida del motor: {}", e))?;
  let _ = fs::remove_file(&out_path);

  // Marcar los ítems revertidos (solo los que tenían undo)
  for it in runs[idx].results.iter_mut() {
    if it.status == "ok" && it.undo.is_some() && (only.is_none() || it.id == only.unwrap()) {
      it.status = "reverted".to_string();
    }
  }
  let record = runs[idx].clone();
  write_history(&runs)?;
  Ok(record)
}

#[tauri::command]
pub fn undo_run(run_id: String) -> Result<RunRecord, String> {
  undo_common(&run_id, None)
}

#[tauri::command]
pub fn undo_item(run_id: String, item_id: String) -> Result<RunRecord, String> {
  undo_common(&run_id, Some(&item_id))
}