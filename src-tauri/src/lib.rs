pub mod commands;
pub mod models;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .invoke_handler(tauri::generate_handler![
      commands::get_catalog,
      commands::is_admin,
      commands::get_runs,
      commands::get_run,
      commands::run_plan,
      commands::undo_run,
      commands::undo_item,
    ])
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}