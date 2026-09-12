# 🔥 WinOpt — Safe & Reversible Windows 11 Optimizer

![Tauri 2](https://img.shields.io/badge/Tauri-2-24c8db?logo=tauri&logoColor=white)
![React 19](https://img.shields.io/badge/React-19-61dafb?logo=react)
![Rust](https://img.shields.io/badge/Rust-2021-dea584?logo=rust&logoColor=white)
![Windows 11](https://img.shields.io/badge/Windows-11-0078d4?logo=windows&logoColor=white)
![License MIT](https://img.shields.io/badge/license-MIT-green)

> **Pick a mode. Apply. Roll back anything — item by item, or everything.**
> WinOpt is a desktop app that optimizes Windows 11 without the scare: every change stores its previous value, and you can undo it from the app's history at any time.

📖 **Español:** lee la versión en español en [LEEME.md](LEEME.md).

---

## ✨ Features

- **28 optimizations** in 4 areas: **cleanup**, **performance**, **privacy & telemetry**, **network & internet**.
- **3 presets** — Conservative, Balanced, and Aggressive — or pick the exact items you want.
- **Fully reversible**: each item keeps a backup of what it changed (registry values, services, power plan, DNS servers...). Undo individual items or the whole run from the **History** tab.
- **System Restore point** created (optional) before applying, if available.
- **No admin rights required for the app itself**: the optimization engine runs elevated through a UAC prompt, so the UI stays sandboxed.
- **Native, lightweight UI** (Tauri 2 + React) — no Electron, no bloat.
- **Local-only history** stored in `%LOCALAPPDATA%\WinOpt\history.json`. Nothing leaves your machine.

## 🎚️ Presets

| Mode | Items | Best for |
| --- | --- | --- |
| 🟢 **Conservative** | 5 | Safe cleanups everyone agrees on |
| 🟡 **Balanced** | 14 | Everyday performance + privacy wins |
| 🔴 **Aggressive** | 28 | Maximum performance & privacy |

## 🛡️ How it stays safe

1. Every item **backs up its previous value** before touching the system.
2. An optional **System Restore point** is requested before the run.
3. The engine writes a **run record** with the undo data for each applied item.
4. From **History** you can **revert one item** or **revert the entire run** — even later sessions.
5. Nothing is permanently deleted; the power plan, hibernation, DNS, services and registry values all get restored to their exact previous state.

## ⚙️ How it works

```
┌──────────────────┐   Tauri invoke   ┌──────────────────────────┐
│  React + Vite UI │ ───────────────> │  Rust orchestrator (app) │
│  (3 tabs)        │ <─────────────── │  catalog · history · plan│
└──────────────────┘                  └────────────┬─────────────┘
                                                   │ elevated via UAC
                                                   v
                                        ┌──────────────────────┐
                                        │  engine.ps1 (admin)  │
                                        │  applies + backups   │
                                        └──────────────────────┘
```

- The **optimization catalog lives in Rust** (`src-tauri/src/models.rs`); the UI never hardcodes system logic.
- The engine is embedded into the binary and launched **elevated** with a single UAC prompt via `src-tauri/resources/engine.ps1` + a hidden `launcher.ps1` wrapper — the app itself never runs as admin.

## 🚀 Installation

Download the latest installer from **Releases**:

| Installer | Notes |
| --- | --- |
| `WinOpt_x64-setup.exe` | NSIS installer — recommends this one |
| `WinOpt_x64_en-US.msi` | MSI package (needs webview2runtime when building) |

> ⚠️ Use the *Aggressive* mode only on systems you control. Everything can be undone from History, and a Restore point before the run is the safest habit.

## 🔨 Build from source

Prerequisites: **Node 20+**, **Rust stable**, **WebView2 runtime** (preinstalled on Windows 11).

```powershell
git clone https://github.com/putx4/WinOpt.git
cd WinOpt
npm install
npm run tauri build        # bundles NSIS + MSI into src-tauri/target/release/bundle/
```

For development with hot reload:

```powershell
npm run tauri dev
```

## 🧪 Development checks

```powershell
npm run lint       # oxlint
npx tsc -b         # typescript
cargo clippy       # rust lints (src-tauri/)
```

## 🗂️ Project layout

```
src/                 # React UI (Optimize / History / Info)
src-tauri/src/       # Rust: models, commands, Tauri app
src-tauri/resources/ # engine.ps1 — the elevated optimization engine (the heart)
src-tauri/public/    # icons
docs/                # screenshots
```

## 📄 License

[MIT](LICENSE) © 2026 Luis Solano