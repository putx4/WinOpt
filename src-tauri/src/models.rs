use serde::{Deserialize, Serialize};
use serde_json::Value;

// ── Catálogo de optimizaciones ────────────────────────────────

#[derive(Serialize, Clone)]
pub struct Cat {
  pub id: &'static str,
  pub name: &'static str,
  pub icon: &'static str,
  pub color: &'static str,
  pub items: Vec<Opt>,
}

#[derive(Serialize, Clone)]
pub struct Opt {
  pub id: &'static str,
  pub name: &'static str,
  pub desc: &'static str,
  /// 1 = conservador, 2 = equilibrado, 3 = agresivo
  pub level: u8,
  pub risk: &'static str,
  pub undoable: bool,
}

/// El catálogo vive aquí (Rust). El plan solo manda ids; el engine
/// conoce las acciones por id. Así nunca divergen frontend y backend.
pub fn catalog() -> Vec<Cat> {
  vec![
    Cat {
      id: "limpieza",
      name: "Limpieza",
      icon: "trash",
      color: "green",
      items: vec![
        Opt { id: "temp_user", name: "Limpiar temporales de usuario", desc: "Borra archivos de %TEMP% y AppData\\Local\\Temp con más de 24 h. Libera espacio sin tocar lo que está en uso.", level: 1, risk: "bajo", undoable: true },
        Opt { id: "temp_system", name: "Limpiar temporales del sistema", desc: "Vacía C:\\Windows\\Temp de archivos antiguos. Requiere administrador.", level: 1, risk: "bajo", undoable: true },
        Opt { id: "update_cleanup", name: "Limpiar actualizaciones viejas", desc: "DISM /StartComponentCleanup: elimina copias obsoletas de Windows Update. Puede tardar unos minutos.", level: 1, risk: "bajo", undoable: true },
        Opt { id: "delivery_optimization", name: "Vaciar caché de Delivery Optimization", desc: "Limpia la cola de optimización de descargas que usa Windows Update por P2P interno.", level: 2, risk: "bajo", undoable: false },
        Opt { id: "browser_cache", name: "Limpiar caché de navegadores", desc: "Cachés de Edge, Chrome y Firefox (los datos vuelven a generarse).", level: 2, risk: "bajo", undoable: false },
        Opt { id: "recycle_bin", name: "Vaciar papelera de reciclaje", desc: "Libera el espacio de la papelera. Imborrable después de hacerlo.", level: 2, risk: "medio", undoable: false },
        Opt { id: "old_restore_points", name: "Borrar puntos de restauración viejos", desc: "Conserva solo el más reciente. Deshace la historia de rollback más antigua a cambio de espacio.", level: 3, risk: "medio", undoable: false },
      ],
    },
    Cat {
      id: "rendimiento",
      name: "Rendimiento",
      icon: "zap",
      color: "cyan",
      items: vec![
        Opt { id: "power_plan", name: "Plan de energía óptimo", desc: "Desktop → ‘Alto rendimiento’; portátil → ‘Equilibrado’; modo agresivo en desktop → ‘Rendimiento máximo’ (Ultimate).", level: 1, risk: "bajo", undoable: true },
        Opt { id: "animations_off", name: "Apagar animaciones y efectos", desc: "Desactiva animaciones de ventanas y ajusta los efectos visuales para rendimiento.", level: 1, risk: "bajo", undoable: true },
        Opt { id: "transparency_off", name: "Apagar transparencia de Windows", desc: "Desactiva el efecto Mica/Fluent en la interfaz. Carga menos la GPU en equipos modestos.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "game_dvr", name: "Modo juego / optimizar juego", desc: "Garantiza que Game Mode y las funciones de captura para juegos estén activas.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "background_apps", name: "Bloquear ejecución en segundo plano", desc: "Impide que las apps de la Store corran en background sin permiso explícito.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "sysmain_off", name: "Apagar SysMain (Superfetch)", desc: "Reduce I/O continuo en discos lentos. En discos NVMe modernos el beneficio es bajo; se recomienda en equipos con HDD.", level: 3, risk: "medio", undoable: true },
        Opt { id: "hibernation_off", name: "Desactivar hibernación", desc: "Libera el archivo hiberfil.sys (varios GB) y acelera el proceso de apagado. Hace más lentos el arranque en frío.", level: 3, risk: "medio", undoable: true },
      ],
    },
    Cat {
      id: "privacidad",
      name: "Privacidad y telemetría",
      icon: "shield",
      color: "purple",
      items: vec![
        Opt { id: "telemetry_off", name: "Reducir telemetría de diagnóstico", desc: "Lleva la recopilación de datos de diagnóstico al mínimo (AllowTelemetry=0). Reversible.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "advertising_id", name: "Desactivar ID de publicidad", desc: "Apaga el identificador de publicidad que asigna Microsoft a tu cuenta.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "tailored_experiences", name: "Quitar contenido personalizado con datos", desc: "Evita que Windows use tus datos de diagnóstico para mostrarte experiencias 'a medida'.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "suggested_content", name: "Quitar sugerencias del menú Inicio", desc: "Apaga apps e historial sugeridos y el contenido promocionado en Inicio.", level: 2, risk: "medio", undoable: true },
        Opt { id: "widgets_off", name: "Quitar icono de Widgets y Chat", desc: "Esconde Tablero de widgets y Chat de la barra de tareas. Ahorra RAM constante.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "welcome_experience", name: "Quitar bienvenidas y consejos", desc: "Apaga 'Experiencia de bienvenida' y los tips de 'Qué hay de nuevo' en bloqueo.", level: 3, risk: "medio", undoable: true },
        Opt { id: "cortana_off", name: "Desactivar Cortana", desc: "Elimina Cortana del árbol de buscador del sistema. El buscador normal sigue funcionando.", level: 3, risk: "medio", undoable: true },
        Opt { id: "location_off", name: "Bloquear acceso a ubicación", desc: "Deniega el acceso a la ubicación a todas las apps de Windows.", level: 3, risk: "medio", undoable: true },
        Opt { id: "activity_history_off", name: "Apagar historial de actividad", desc: "Detiene la recopilación del historial de actividad (línea de tiempo) de tu cuenta.", level: 3, risk: "medio", undoable: true },
        Opt { id: "timeline_tracking", name: "No recordar documentos recientes", desc: "Evita que Inicio/Ejecutar recuerden los archivos y apps que abriste.", level: 3, risk: "bajo", undoable: true },
      ],
    },
    Cat {
      id: "redes",
      name: "Redes e internet",
      icon: "globe",
      color: "yellow",
      items: vec![
        Opt { id: "dns_set", name: "DNS rápido 1.1.1.1 / 1.0.0.1", desc: "Configura Cloudflare en las tarjetas de red activas. Guarda el DNS anterior para revertirlo.", level: 2, risk: "medio", undoable: true },
        Opt { id: "deliveryopt_peer", name: "Quitar P2P en descargas de Windows", desc: "Evita que tu equipo suba actualizaciones a otros PCs de internet. Descargas igual, sin consumir tu subida.", level: 2, risk: "bajo", undoable: true },
        Opt { id: "network_throttling", name: "Quitar límite de ancho de banda multimedia", desc: "Elimina la reserva que Windows tiene para tareas multimedia y libera la red completa.", level: 3, risk: "bajo", undoable: true },
        Opt { id: "nagle_off", name: "Reducir latencia TCP (Nagle)", desc: "Ajusta TCP para menor latencia en juegos. Cambio a nivel de tarjeta, reversible.", level: 3, risk: "medio", undoable: true },
      ],
    },
  ]
}

pub fn find_item(id: &str) -> Option<(usize, usize, Opt)> {
  let cats = catalog();
  for (ci, cat) in cats.iter().enumerate() {
    for (ii, item) in cat.items.iter().enumerate() {
      if item.id == id {
        return Some((ci, ii, item.clone()));
      }
    }
  }
  None
}

// ── Tipos de plan / resultado ─────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct PlanReq {
  pub items: Vec<String>,
  pub restore_point: bool,
  pub mode: u8,
}

#[derive(Deserialize, Serialize, Clone, Default)]
#[serde(default)]
pub struct ItemOut {
  pub id: String,
  pub name: String,
  pub ok: bool,
  pub applied: bool,
  pub detail: String,
  pub status: String,
  pub undo: Option<Value>,
}

#[derive(Deserialize, Serialize, Clone, Default)]
#[serde(default)]
pub struct EngineOut {
  pub ok: bool,
  pub message: String,
  pub restore_point_created: bool,
  pub results: Vec<ItemOut>,
}

#[derive(Serialize, Deserialize, Clone, Default)]
#[serde(default)]
pub struct RunRecord {
  pub run_id: String,
  pub created: String,
  pub mode: u8,
  pub restore_point_created: bool,
  pub results: Vec<ItemOut>,
}

#[derive(Serialize, Clone)]
pub struct RunSummary {
  pub run_id: String,
  pub created: String,
  pub mode: u8,
  pub ok: usize,
  pub total: usize,
  pub restore_point_created: bool,
}

impl RunSummary {
  pub fn from_record(r: &RunRecord) -> RunSummary {
    let total = r.results.len();
    let ok = r.results.iter().filter(|x| x.status == "ok").count();
    RunSummary {
      run_id: r.run_id.clone(),
      created: r.created.clone(),
      mode: r.mode,
      ok,
      total,
      restore_point_created: r.restore_point_created,
    }
  }
}

impl From<EngineOut> for RunRecord {
  fn from(e: EngineOut) -> Self {
    RunRecord {
      run_id: String::new(),
      created: String::new(),
      mode: 0,
      restore_point_created: e.restore_point_created,
      results: e.results,
    }
  }
}