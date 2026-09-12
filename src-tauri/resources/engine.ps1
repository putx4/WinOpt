<#
  WinOpt — Motor de optimización de Windows 11
  Autor: Solano / opencode (2026-09-12)

  Modos de uso:
    -PlanPath   <json> : { run_id, mode, items:[ids], restore_point }
    -OutputPath <json> : ruta donde escribir el resultado
    -RunId      <string>
    -UndoPath   <json> : { steps:[ { item, undo } ] } -> revierte
#>
param(
  [string]$PlanPath,
  [string]$OutputPath,
  [string]$RunId,
  [string]$UndoPath
)

$ErrorActionPreference = 'Continue'
$script:Undos = @()
$script:Results = @()
$script:RestorePointCreated = $false
$script:DidNothing = $true

# ── Helpers de registro (hive-agnósticos) ──────────────────────
function Split-RegPath([string]$Path, [ref]$Hive, [ref]$Sub) {
  if ($Path.StartsWith('HKCU\') -or $Path.StartsWith('HKCU:')) { $Hive.Value = 'CurrentUser'; $Sub.Value = ($Path -replace '^HKCU[\\:]', '') }
  elseif ($Path.StartsWith('HKLM\') -or $Path.StartsWith('HKLM:')) { $Hive.Value = 'LocalMachine'; $Sub.Value = ($Path -replace '^HKLM[\\:]', '') }
}

function Open-Reg([string]$Path, [bool]$Writable) {
  $h = ''; $s = ''
  Split-RegPath $Path ([ref]$h) ([ref]$s)
  if ($s -eq '') { return $null }
  $root = if ($h -eq 'CurrentUser') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine }
  $key = $root.OpenSubKey($s, $Writable)
  if ($null -eq $key) {
    if ($Writable) {
      # crear subclaves intermedias (políticas de datos)
      $parts = $s.Split('\')
      $acc = ''
      foreach ($p in $parts) {
        $acc = if ($acc) { "$acc\$p" } else { $p }
        if ($null -eq $root.OpenSubKey($acc, $true)) { [void]$root.CreateSubKey($acc) }
      }
      $key = $root.OpenSubKey($s, $true)
    }
  }
  return $key
}

function Backup-Reg([string]$Path, [string]$Name) {
  $key = Open-Reg $Path $false
  if ($null -eq $key) { return [pscustomobject]@{ Path = $Path; Name = $Name; Existed = $false; Value = $null; Kind = 'None' } }
  try {
    $val = $key.GetValue($Name)
    if ($null -eq $val) {
      $key.Close()
      return [pscustomobject]@{ Path = $Path; Name = $Name; Existed = $false; Value = $null; Kind = 'None' }
    }
    $kind = $key.GetValueKind($Name)
    $key.Close()
    return [pscustomobject]@{ Path = $Path; Name = $Name; Existed = $true; Value = $val; Kind = $kind }
  } catch {
    $key.Close()
    return [pscustomobject]@{ Path = $Path; Name = $Name; Existed = $false; Value = $null; Kind = 'None' }
  }
}

function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
  $key = Open-Reg $Path $true
  if ($null -eq $key) { return $false }
  try {
    $key.SetValue($Name, $Value, $Type)
    $key.Close()
    return $true
  } catch { $key.Close(); return $false }
}

function Remove-Reg([string]$Path, [string]$Name) {
  $key = Open-Reg $Path $true
  if ($null -eq $key) { return $true }
  try {
    $key.DeleteValue($Name, $false)
    $key.Close()
    return $true
  } catch { $key.Close(); return $true }
}

# ── Gestión de undo ────────────────────────────────────────────
function New-Undo([string]$ItemId, [string]$Kind, $Data) {
  $script:Undos += [pscustomobject]@{ item = $ItemId; kind = $Kind; data = $Data }
}

function Resolve-RegKind($k) {
  if ($null -eq $k) { return [Microsoft.Win32.RegistryValueKind]::None }
  if ($k -is [string]) {
    if ($k -eq 'None') { return [Microsoft.Win32.RegistryValueKind]::None }
    try { return [enum]::Parse([Microsoft.Win32.RegistryValueKind], $k, $true) } catch { return [Microsoft.Win32.RegistryValueKind]::None }
  }
  try { return [Microsoft.Win32.RegistryValueKind]$k } catch { return [Microsoft.Win32.RegistryValueKind]::None }
}

function Undo-Step($step) {
  $u = $step.undo
  $out = [pscustomobject]@{ id = $step.item; ok = $true; detail = '' }
  try {
    switch ($u.kind) {
      'reg' {
        $b = $u.data
        $vk = Resolve-RegKind $b.Kind
        if ($b.Existed -and $vk -ne [Microsoft.Win32.RegistryValueKind]::None) {
          $v = $b.Value
          if ($vk -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $v = [byte[]]$v }
          [void](Set-Reg $b.Path $b.Name $v $vk)
        } else { [void](Remove-Reg $b.Path $b.Name) }
      }
      'regs' {
        foreach ($e in $u.data) {
          $vk = Resolve-RegKind $e.Kind
          if ($e.Existed -and $vk -ne [Microsoft.Win32.RegistryValueKind]::None) {
            $v = $e.Value
            if ($vk -eq [Microsoft.Win32.RegistryValueKind]::Binary) { $v = [byte[]]$v }
            [void](Set-Reg $e.Path $e.Name $v $vk)
          } else { [void](Remove-Reg $e.Path $e.Name) }
        }
      }
      'power' { & powercfg /setactive $u.data.guid | Out-Null }
      'service' {
        Set-Service -Name $u.data.name -StartupType $u.data.previous -ErrorAction SilentlyContinue
        if ($u.data.previous -eq 'Automatic' -or $u.data.previous -eq 'Manual') {
          Start-Service -Name $u.data.name -ErrorAction SilentlyContinue
        }
      }
      'hibernation' { if ($u.data.enabled) { & powercfg /h on | Out-Null } else { & powercfg /h off | Out-Null } }
      'dns' {
        foreach ($a in $u.data.adapters) {
          if ($a.previous -eq 'DHCP') {
            Set-DnsClientServerAddress -InterfaceIndex $a.index -ResetServerAddresses -ErrorAction SilentlyContinue
          } else {
            Set-DnsClientServerAddress -InterfaceIndex $a.index -ServerAddresses $a.previous -ErrorAction SilentlyContinue
          }
        }
      }
      default { $out.ok = $false; $out.detail = "Tipo de undo desconocido: $($u.kind)" }
    }
  } catch {
    $out.ok = $false
    $out.detail = $_.Exception.Message
  }
  return $out
}

# ── Punto de restauración ──────────────────────────────────────
function New-RestorePoint([string]$Desc) {
  # Windows permite crear máx. 1 punto/24 h por volumen; no es error si existe uno reciente.
  try {
    [System.ComponentModel.Win32Exception] | Out-Null
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue | Out-Null
    Checkpoint-Computer -Description $Desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    return [pscustomobject]@{ ok = $true; detail = "Punto de restauración creado: $Desc" }
  } catch {
    $msg = $_.Exception.Message
    if ($msg -match 'no se puede crear|recent|cannot') {
      return [pscustomobject]@{ ok = $false; detail = "Ya existe un punto reciente (límite de 1 al día) — se seguirá igual." }
    }
    return [pscustomobject]@{ ok = $false; detail = "No se pudo crear punto de restauración: $msg" }
  }
}

# ── Utilidades de tamaño / fecha ───────────────────────────────
function Get-Size([string]$Path) {
  $sum = [int64]0
  if (Test-Path -LiteralPath $Path) {
    Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
      ForEach-Object { if (-not $_.PSIsContainer) { $sum += $_.Length } }
  }
  return $sum
}

function Format-Bytes([int64]$Bytes) {
  if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
  if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
  if ($Bytes -ge 1KB) { return '{0:N1} KB' -f ($Bytes / 1KB) }
  return "$Bytes B"
}

function Sweep-Dir([string]$Path, [int]$MinAgeHours) {
  if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ count = 0; bytes = [int64]0 } }
  $count = 0; $bytes = [int64]0
  $cut = (Get-Date).AddHours(-$MinAgeHours)
  Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.LastWriteTime -lt $cut) {
      $bytes += (Get-Size $_.FullName)
      Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
      $count++
    }
  }
  return [pscustomobject]@{ count = $count; bytes = $bytes }
}

# ── Registro de cada ítem ──────────────────────────────────────
function Add-Result([string]$Id, [string]$Name, [bool]$Ok, [bool]$Applied, [string]$Status, [string]$Detail) {
  $undo = if ($script:Undos.Count -gt 0) {
    $pending = @($script:Undos | Where-Object { $_.item -eq $Id })
    $script:Undos = @($script:Undos | Where-Object { $_.item -ne $Id })
    if ($pending.Count -gt 0) {
      $last = $pending[$pending.Count - 1]
      [pscustomobject]@{ kind = $last.kind; data = $last.data }
    }
    else { $null }
  } else { $null }
  $script:Results += [pscustomobject]@{
    id = $Id; name = $Name; ok = $Ok; applied = $Applied; status = $Status; detail = $Detail; undo = $undo
  }
}

function Pretty([string]$s) { if ($s -and $s.Length -gt 0) { return $s } else { return 'ok' } }

# ── ITEMS ──────────────────────────────────────────────────────
# Cada función recibe $ctx (hashtable modo/runid) y escribe con Add-Result.

function Item-temp_user($ctx) {
  $c = Sweep-Dir $env:TEMP 24
  $cl = Sweep-Dir "$env:LOCALAPPDATA\Temp" 24
  $total = $c.bytes + $cl.bytes
  $msg = "$($c.count + $cl.count) elementos, $('{0:N1} MB' -f ($total / 1MB)) liberados"
  Add-Result 'temp_user' 'Limpiar temporales de usuario' $true $true 'ok' $msg
}

function Item-temp_system($ctx) {
  $c = Sweep-Dir 'C:\Windows\Temp' 24
  Add-Result 'temp_system' 'Limpiar temporales del sistema' $true $true 'ok' "$($c.count) elementos, $('{0:N1} MB' -f ($c.bytes / 1MB)) liberados"
}

function Item-update_cleanup($ctx) {
  $output = & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet 2>&1
  if ($LASTEXITCODE -ne 0) {
    $tail = ($output | Select-Object -Last 3 | Out-String).Trim()
    Add-Result 'update_cleanup' 'Limpiar actualizaciones viejas' $false $false 'error' "DISM falló: $tail"
  } else {
    Add-Result 'update_cleanup' 'Limpiar actualizaciones viejas' $true $true 'ok' 'Componentes obsoletos de Windows Update retirados'
  }
}

function Item-delivery_optimization($ctx) {
  # Prioridad 1: cmdlets oficiales de Delivery Optimization.
  if ((Get-Command Get-DeliveryOptimizationCacheStatus -ErrorAction SilentlyContinue) -and
      (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
    try {
      $pre = (Get-DeliveryOptimizationCacheStatus -ErrorAction SilentlyContinue | Measure-Object Size -Sum).Sum
      Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null
      Add-Result 'delivery_optimization' 'Vaciar caché de Delivery Optimization' $true $true 'ok' "Caché limpiada ($('{0:N0} MB' -f ($pre / 1MB)))"
      return
    } catch {
      Add-Result 'delivery_optimization' 'Vaciar caché de Delivery Optimization' $false $false 'error' "Error: $($_.Exception.Message)"
      return
    }
  }
  # Prioridad 2: borrar la carpeta de caché directamente (cmdlet ausente).
  $cacheDir = "$env:SystemDrive\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
  if (Test-Path -LiteralPath $cacheDir) {
    $pre = (Get-Size $cacheDir)
    Remove-Item -LiteralPath "$cacheDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    $still = (Get-Size $cacheDir)
    $freed = $pre - $still
    if ($freed -gt 0) {
      Add-Result 'delivery_optimization' 'Vaciar caché de Delivery Optimization' $true $true 'ok' "Caché limpiada ($('{0:N0} MB' -f ($freed / 1MB)))"
    } else {
      Add-Result 'delivery_optimization' 'Vaciar caché de Delivery Optimization' $true $true 'ok' 'Caché ya vacía'
    }
  } else {
    Add-Result 'delivery_optimization' 'Vaciar caché de Delivery Optimization' $true $false 'skipped' 'No hay caché de Delivery Optimization'
  }
}

function Item-browser_cache($ctx) {
  $bytes = [int64]0
  $count = 0
  $caches = @(
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
  )
  foreach ($d in $caches) {
    if (Test-Path -LiteralPath $d) {
      Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $bytes += (Get-Size $_.FullName)
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $_.FullName)) { $count++ }
      }
    }
  }
  if (Test-Path -LiteralPath "$env:APPDATA\Mozilla\Firefox\Profiles") {
    Get-ChildItem -LiteralPath "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      foreach ($sub in @('cache2','startupCache','thumbnails')) {
        $p = Join-Path $_.FullName $sub
        if (Test-Path -LiteralPath $p) {
          $bytes += (Get-Size $p)
          Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
          if (-not (Test-Path -LiteralPath $p)) { $count++ }
        }
      }
    }
  }
  if ($count -eq 0 -and $bytes -eq 0) {
    Add-Result 'browser_cache' 'Limpiar caché de navegadores' $true $false 'skipped' 'Cachés ya vacías o navegador abierto (ciérralo para liberar más)'
  } else {
    Add-Result 'browser_cache' 'Limpiar caché de navegadores' $true $true 'ok' "$count elementos, $('{0:N1} MB' -f ($bytes / 1MB)) liberados"
  }
}

function Item-recycle_bin($ctx) {
  $shell = New-Object -ComObject Shell.Application
  $rb = $shell.NameSpace(0xA)
  $n = $rb.Items().Count
  Clear-RecycleBin -Force -ErrorAction SilentlyContinue
  [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
  Add-Result 'recycle_bin' 'Vaciar papelera de reciclaje' $true $true 'ok' "$n elementos eliminados de la papelera"
}

function Item-old_restore_points($ctx) {
  try {
    $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object CreationTime -Descending)
    $toDel = $pts.Count - 1
    if ($toDel -gt 0) {
      for ($i = 0; $i -lt $toDel; $i++) {
        & vssadmin delete shadows /For=$env:SystemDrive /Oldest /Quiet 2>&1 | Out-Null
        Start-Sleep -Milliseconds 300
      }
      Add-Result 'old_restore_points' 'Borrar puntos de restauración viejos' $true $true 'ok' "$toDel puntos antiguos eliminados (queda el más reciente)"
    } else {
      Add-Result 'old_restore_points' 'Borrar puntos de restauración viejos' $true $false 'skipped' 'No hay puntos antiguos que borrar'
    }
  } catch {
    Add-Result 'old_restore_points' 'Borrar puntos de restauración viejos' $false $false 'error' "Error: $($_.Exception.Message)"
  }
}

function Get-AvailablePowerGuids {
  @(Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -ErrorAction SilentlyContinue |
    ForEach-Object { if ($_.InstanceID -match 'PowerPlan\{(.+)\}') { $Matches[1].ToLower() } })
}

function Item-power_plan($ctx) {
  $active = & powercfg /getactivescheme | Out-String
  # No depender del idioma: buscar el GUID hex directamente (8-4-4-4-12)
  $m = [regex]::Match($active, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
  if (-not $m.Success) { Add-Result 'power_plan' 'Plan de energía óptimo' $false $false 'error' "No se pudo leer el plan activo ($(($active -replace '\s+',' ').Trim()))"; return }
  $prev = $m.Value
  $guids = Get-AvailablePowerGuids
  $ult = 'e9a42b02-d5df-448d-aa00-03f14749eb61'   # Máximo rendimiento (Ultimate)
  $hp  = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # Alto rendimiento
  $bal = '381b4222-f694-41f0-9685-ff5bb260df2e'   # Equilibrado
  $isLaptop = $null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

  $target = $null
  $label = ''
  if ($isLaptop) {
    $target = $bal; $label = 'Equilibrado (portátil detectado)'
  } elseif ($ctx.mode -ge 3) {
    # Preferir Ultimate; si el GUID no existe, buscar por nombre (equipos customizados),
    # y si nada, crear el plan Ultimate con /duplicatescheme.
    if ($ult -in $guids) {
      $target = $ult; $label = 'Máximo rendimiento (Ultimate)'
    } else {
      $cand = Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -ErrorAction SilentlyContinue |
              Where-Object { $_.ElementName -in @('Máximo rendimiento', 'Ultimate Performance') } |
              Select-Object -First 1
      if ($cand) {
        $target = [regex]::Match($cand.InstanceID, '\{([0-9a-fA-F-]+)\}').Groups[1].Value
        $label = 'Máximo rendimiento'
      } elseif ($hp -in $guids) {
        $target = $hp; $label = 'Alto rendimiento'
      } else {
        $dupOut = & powercfg /duplicatescheme $ult 2>&1 | Out-String
        $g2 = [regex]::Match($dupOut, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
        if ($g2) { $target = $g2; $label = 'Máximo rendimiento (creado)' }
      }
    }
  } else {
    if ($hp -in $guids) { $target = $hp; $label = 'Alto rendimiento' }
    else { $target = $bal; $label = 'Equilibrado' }
  }

  if (-not $target) { Add-Result 'power_plan' 'Plan de energía óptimo' $false $false 'error' 'No se encontró ningún plan de alto rendimiento'; return }
  if ($prev.ToLower() -eq $target.ToLower()) {
    Add-Result 'power_plan' 'Plan de energía óptimo' $true $false 'skipped' "Ya estaba en $label"
    return
  }
  $r = & powercfg /setactive $target 2>&1
  if ($LASTEXITCODE -eq 0) {
    New-Undo 'power_plan' 'power' @{ guid = $prev }
    Add-Result 'power_plan' 'Plan de energía óptimo' $true $true 'ok' "Activado: $label (anterior: $prev)"
  } else {
    Add-Result 'power_plan' 'Plan de energía óptimo' $false $false 'error' "powercfg falló: $r"
  }
}

function Item-animations_off($ctx) {
  $b1 = Backup-Reg 'HKCU\Control Panel\Desktop\WindowMetrics' 'MinAnimate'
  $b2 = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
  $k1 = Set-Reg 'HKCU\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
  $k2 = Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2 'DWord'
  if ($k1 -and $k2) {
    New-Undo 'animations_off' 'regs' @($b1, $b2)
    Add-Result 'animations_off' 'Apagar animaciones y efectos' $true $true 'ok' 'Animaciones de ventanas y efectos ajustados para rendimiento'
  } else {
    Add-Result 'animations_off' 'Apagar animaciones y efectos' $false $false 'error' 'No se pudo escribir el registro'
  }
}

function Item-transparency_off($ctx) {
  $b = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency'
  if (Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 'DWord') {
    New-Undo 'transparency_off' 'reg' $b
    Add-Result 'transparency_off' 'Apagar transparencia de Windows' $true $true 'ok' 'Efecto de transparencia desactivado'
  } else { Add-Result 'transparency_off' 'Apagar transparencia de Windows' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-game_dvr($ctx) {
  $b1 = Backup-Reg 'HKCU\System\GameConfigStore' 'GameDVR_Enabled'
  $b2 = Backup-Reg 'HKCU\System\GameConfigStore' 'GameDVR_FSEBehaviorMode'
  $b3 = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
  [void](Set-Reg 'HKCU\System\GameConfigStore' 'GameDVR_Enabled' 1 'DWord')
  [void](Set-Reg 'HKCU\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2 'DWord')
  [void](Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1 'DWord')
  New-Undo 'game_dvr' 'regs' @($b1, $b2, $b3)
  Add-Result 'game_dvr' 'Modo juego / optimizar juego' $true $true 'ok' 'Game Mode y funciones de juego aseguradas'
}

function Item-background_apps($ctx) {
  $b = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled'
  if (Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1 'DWord') {
    New-Undo 'background_apps' 'reg' $b
    Add-Result 'background_apps' 'Bloquear ejecución en segundo plano' $true $true 'ok' 'Apps de Store no correrán en segundo plano'
  } else { Add-Result 'background_apps' 'Bloquear ejecución en segundo plano' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-sysmain_off($ctx) {
  try {
    $svc = Get-Service SysMain -ErrorAction Stop
    $prev = $svc.StartType.ToString()
    if ($prev -eq 'Disabled') {
      Add-Result 'sysmain_off' 'Apagar SysMain (Superfetch)' $true $false 'skipped' 'SysMain ya está desactivado'
      return
    }
    Set-Service -Name SysMain -StartupType Disabled -ErrorAction Stop
    Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue
    New-Undo 'sysmain_off' 'service' @{ name = 'SysMain'; previous = $prev }
    Add-Result 'sysmain_off' 'Apagar SysMain (Superfetch)' $true $true 'ok' "SysMain desactivado (era $prev)"
  } catch {
    Add-Result 'sysmain_off' 'Apagar SysMain (Superfetch)' $false $false 'error' "Error: $($_.Exception.Message)"
  }
}

function Item-hibernation_off($ctx) {
  $b = [pscustomobject]@{ enabled = $false }
  if (Test-Path "$env:SystemDrive\hiberfil.sys") { $b.enabled = $true }
  $r = & powercfg /h off 2>&1
  if ($LASTEXITCODE -eq 0) {
    New-Undo 'hibernation_off' 'hibernation' $b
    Add-Result 'hibernation_off' 'Desactivar hibernación' $true $true 'ok' 'Hibernación y arranque rápido apagados (hiberfil.sys liberado)'
  } else {
    Add-Result 'hibernation_off' 'Desactivar hibernación' $false $false 'error' "powercfg falló: $r"
  }
}

function Item-telemetry_off($ctx) {
  $b1 = Backup-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
  $b2 = Backup-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry'
  $b3 = Backup-Reg 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'AllowTelemetry'
  [void](Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0 'DWord')
  [void](Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0 'DWord')
  [void](Set-Reg 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack' 'AllowTelemetry' 0 'DWord')
  New-Undo 'telemetry_off' 'regs' @($b1, $b2, $b3)
  Add-Result 'telemetry_off' 'Reducir telemetría de diagnóstico' $true $true 'ok' 'Recopilación de diagnóstico en el mínimo'
}

function Item-advertising_id($ctx) {
  $b = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled'
  if (Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'DWord') {
    New-Undo 'advertising_id' 'reg' $b
    Add-Result 'advertising_id' 'Desactivar ID de publicidad' $true $true 'ok' 'ID de publicidad apagado'
  } else { Add-Result 'advertising_id' 'Desactivar ID de publicidad' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-tailored_experiences($ctx) {
  $b = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled'
  if (Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'DWord') {
    New-Undo 'tailored_experiences' 'reg' $b
    Add-Result 'tailored_experiences' 'Quitar contenido personalizado con datos' $true $true 'ok' 'Experiencias personalizadas desactivadas'
  } else { Add-Result 'tailored_experiences' 'Quitar contenido personalizado con datos' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-suggested_content($ctx) {
  $base = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
  $names = @(
    'SystemPaneSuggestionsEnabled',
    'SubscribedContent-310093Enabled',
    'SubscribedContent-338388Enabled',
    'SubscribedContent-338389Enabled',
    'SubscribedContent-338393Enabled',
    'SubscribedContent-353692Enabled',
    'SubscribedContent-353693Enabled',
    'SubscribedContent-353694Enabled',
    'SubscribedContent-353696Enabled'
  )
  $bk = @()
  foreach ($n in $names) {
    $bk += Backup-Reg $base $n
    [void](Set-Reg $base $n 0 'DWord')
  }
  New-Undo 'suggested_content' 'regs' $bk
  Add-Result 'suggested_content' 'Quitar sugerencias del menú Inicio' $true $true 'ok' 'Sugerencias y contenido promocionado apagados'
}

function Item-widgets_off($ctx) {
  $b1 = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa'
  $b2 = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn'
  [void](Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 'DWord')
  [void](Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0 'DWord')
  New-Undo 'widgets_off' 'regs' @($b1, $b2)
  Add-Result 'widgets_off' 'Quitar icono de Widgets y Chat' $true $true 'ok' 'Widgets y Chat escondidos de la barra de tareas'
}

function Item-welcome_experience($ctx) {
  $base = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
  $b1 = Backup-Reg $base 'RotatingLockScreenOverlayEnabled'
  $b2 = Backup-Reg $base 'SoftLandingEnabled'
  $b3 = Backup-Reg $base 'SubscribedContent-338387Enabled'
  $b4 = Backup-Reg $base 'SubscribedContent-310094Enabled'
  [void](Set-Reg $base 'RotatingLockScreenOverlayEnabled' 0 'DWord')
  [void](Set-Reg $base 'SoftLandingEnabled' 0 'DWord')
  [void](Set-Reg $base 'SubscribedContent-338387Enabled' 0 'DWord')
  [void](Set-Reg $base 'SubscribedContent-310094Enabled' 0 'DWord')
  New-Undo 'welcome_experience' 'regs' @($b1, $b2, $b3, $b4)
  Add-Result 'welcome_experience' 'Quitar bienvenidas y consejos' $true $true 'ok' 'Experiencia de bienvenida y tips apagados'
}

function Item-cortana_off($ctx) {
  $b1 = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent'
  $b2 = Backup-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana'
  [void](Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0 'DWord')
  [void](Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0 'DWord')
  New-Undo 'cortana_off' 'regs' @($b1, $b2)
  Add-Result 'cortana_off' 'Desactivar Cortana' $true $true 'ok' 'Cortana apagada (el buscador normal sigue activo)'
}

function Item-location_off($ctx) {
  $b1 = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value'
  $b2 = Backup-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value'
  [void](Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String')
  [void](Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String')
  New-Undo 'location_off' 'regs' @($b1, $b2)
  Add-Result 'location_off' 'Bloquear acceso a ubicación' $true $true 'ok' 'Acceso a ubicación denegado a las apps'
}

function Item-activity_history_off($ctx) {
  $b1 = Backup-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed'
  $b2 = Backup-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities'
  [void](Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0 'DWord')
  [void](Set-Reg 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0 'DWord')
  New-Undo 'activity_history_off' 'regs' @($b1, $b2)
  Add-Result 'activity_history_off' 'Apagar historial de actividad' $true $true 'ok' 'Historial de actividad deshabilitado'
}

function Item-timeline_tracking($ctx) {
  $b = Backup-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs'
  if (Set-Reg 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackDocs' 0 'DWord') {
    New-Undo 'timeline_tracking' 'reg' $b
    Add-Result 'timeline_tracking' 'No recordar documentos recientes' $true $true 'ok' 'Archivos recientes ya no se registran'
  } else { Add-Result 'timeline_tracking' 'No recordar documentos recientes' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-dns_set($ctx) {
  $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
  if ($adapters.Count -eq 0) { Add-Result 'dns_set' 'DNS rápido 1.1.1.1 / 1.0.0.1' $true $false 'skipped' 'No hay tarjetas de red físicas activas'; return }
  $b = @()
  foreach ($a in $adapters) {
    $dns = @(Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses.Count -gt 0 })
    $prev = if ($dns.Count -gt 0) { $dns[0].ServerAddresses } else { @('DHCP') }
    $b += [pscustomobject]@{ index = $a.InterfaceIndex; previous = @($prev) }
    if ($prev -contains 'DHCP') {
      Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses @('1.1.1.1','1.0.0.1') -ErrorAction SilentlyContinue
    }
  }
  New-Undo 'dns_set' 'dns' @{ adapters = $b }
  Add-Result 'dns_set' 'DNS rápido 1.1.1.1 / 1.0.0.1' $true $true 'ok' "DNS de Cloudflare aplicado en $($adapters.Count) adaptador(es)"
}

function Item-deliveryopt_peer($ctx) {
  $b = Backup-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode'
  if (Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 0 'DWord') {
    New-Undo 'deliveryopt_peer' 'reg' $b
    Add-Result 'deliveryopt_peer' 'Quitar P2P en descargas de Windows' $true $true 'ok' 'Descargas de Windows sin compartir a otros PCs'
  } else { Add-Result 'deliveryopt_peer' 'Quitar P2P en descargas de Windows' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-network_throttling($ctx) {
  $b = Backup-Reg 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'
  # DWord 0xFFFFFFFF: pasar -1 (Int32). 4294967295 (Int64) lo rechaza .NET SetValue.
  if (Set-Reg 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' -1 'DWord') {
    New-Undo 'network_throttling' 'reg' $b
    Add-Result 'network_throttling' 'Quitar límite de ancho de banda multimedia' $true $true 'ok' 'Reserva de red multimedia eliminada'
  } else { Add-Result 'network_throttling' 'Quitar límite de ancho de banda multimedia' $false $false 'error' 'No se pudo escribir el registro' }
}

function Item-nagle_off($ctx) {
  $ifacesKey = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
  $guids = @()
  try {
    $r = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces')
    if ($null -eq $r) {
      Add-Result 'nagle_off' 'Reducir latencia TCP (Nagle)' $false $false 'error' 'No se pudo abrir la clave TCP/IP'
      return
    }
    $guids = $r.GetSubKeyNames()
    $r.Close()
  } catch {
    Add-Result 'nagle_off' 'Reducir latencia TCP (Nagle)' $false $false 'error' $_.Exception.Message
    return
  }
  if ($guids.Count -eq 0) {
    Add-Result 'nagle_off' 'Reducir latencia TCP (Nagle)' $true $false 'skipped' 'Sin interfaces TCP/IP'
    return
  }
  $bk = @(); $changes = 0
  foreach ($g in $guids) {
    $p = "$ifacesKey\$g"
    $b1 = Backup-Reg $p 'TcpAckFrequency'
    $b2 = Backup-Reg $p 'TCPNoDelay'
    if (Set-Reg $p 'TcpAckFrequency' 1 'DWord') { $changes++ }
    if (Set-Reg $p 'TCPNoDelay' 1 'DWord') { $changes++ }
    $bk += $b1
    $bk += $b2
  }
  if ($changes -gt 0) {
    New-Undo 'nagle_off' 'regs' $bk
    Add-Result 'nagle_off' 'Reducir latencia TCP (Nagle)' $true $true 'ok' "TCP configurado para baja latencia ($changes valores)"
  } else {
    Add-Result 'nagle_off' 'Reducir latencia TCP (Nagle)' $false $false 'error' 'No se escribieron valores TCP'
  }
}

$script:ItemNames = @{}
# ── Despachador de ítems ───────────────────────────────────────
$script:ItemFuncs = @{
  'temp_user' = 'Item-temp_user'
  'temp_system' = 'Item-temp_system'
  'update_cleanup' = 'Item-update_cleanup'
  'delivery_optimization' = 'Item-delivery_optimization'
  'browser_cache' = 'Item-browser_cache'
  'recycle_bin' = 'Item-recycle_bin'
  'old_restore_points' = 'Item-old_restore_points'
  'power_plan' = 'Item-power_plan'
  'animations_off' = 'Item-animations_off'
  'transparency_off' = 'Item-transparency_off'
  'game_dvr' = 'Item-game_dvr'
  'background_apps' = 'Item-background_apps'
  'sysmain_off' = 'Item-sysmain_off'
  'hibernation_off' = 'Item-hibernation_off'
  'telemetry_off' = 'Item-telemetry_off'
  'advertising_id' = 'Item-advertising_id'
  'tailored_experiences' = 'Item-tailored_experiences'
  'suggested_content' = 'Item-suggested_content'
  'widgets_off' = 'Item-widgets_off'
  'welcome_experience' = 'Item-welcome_experience'
  'cortana_off' = 'Item-cortana_off'
  'location_off' = 'Item-location_off'
  'activity_history_off' = 'Item-activity_history_off'
  'timeline_tracking' = 'Item-timeline_tracking'
  'dns_set' = 'Item-dns_set'
  'deliveryopt_peer' = 'Item-deliveryopt_peer'
  'network_throttling' = 'Item-network_throttling'
  'nagle_off' = 'Item-nagle_off'
}

# ── RUN / UNDO ─────────────────────────────────────────────────
function Out-JsonNoBom([object]$Obj, [string]$Path) {
  # PS 5.1: Set-Content -Encoding UTF8 añade BOM; serde_json no lo tolera.
  # UTF-8 sin BOM (UTF8Encoding($false)).
  $json = $Obj | ConvertTo-Json -Depth 12
  [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

if ($UndoPath) {
  $steps = (Get-Content -LiteralPath $UndoPath -Raw | ConvertFrom-Json).steps
  $outs = @()
  foreach ($st in $steps) {
    $r = Undo-Step $st
    $outs += [pscustomobject]@{ id = $r.id; ok = $r.ok; detail = $r.detail }
  }
  $res = [pscustomobject]@{ ok = $true; message = 'Undo completado'; restore_point_created = $false; results = $outs }
  Out-JsonNoBom $res $OutputPath
  exit 0
}

$ctx = @{ mode = 1 }
if ($PlanPath) {
  $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
  $ctx.mode = [int]$plan.mode
  if ($plan.restore_point) {
    $rp = New-RestorePoint "WinOpt $RunId"
    $script:RestorePointCreated = $rp.ok
  }
  $ids = @($plan.items)
  foreach ($it in $ids) {
    $id = if ($it -is [string]) { $it } else { $it.id }
    $nm = if ($it -is [string]) { $id } else { [string]$it.name }
    $script:ItemNames[$id] = $nm
    $fn = $script:ItemFuncs[$id]
    if (-not $fn) { continue }
    try {
      & $fn $ctx
    } catch {
      $disp = if ($script:ItemNames.ContainsKey($id)) { $script:ItemNames[$id] } else { $id }
      Add-Result $id $disp $false $false 'error' $_.Exception.Message
    }
  }
  $message = "$($script:Results.Count) acciones evaluadas"
} else {
  $message = 'Sin plan'
}

$engineOut = [pscustomobject]@{
  ok = $true
  message = $message
  restore_point_created = $script:RestorePointCreated
  results = $script:Results
}
Out-JsonNoBom $engineOut $OutputPath
exit 0