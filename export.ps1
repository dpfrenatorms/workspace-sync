# ============================================================
# export.ps1 — Exporta o workspace deste notebook para o HD
# Uso:  powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\export.ps1
#       (acrescente -Snapshot para gerar uma copia datada congelada)
# ============================================================
param([switch]$Snapshot)

$ErrorActionPreference = 'Continue'
$sync   = Split-Path -Parent $MyInvocation.MyCommand.Path
$mirror = Join-Path $sync 'mirror'
$logDir = Join-Path $sync 'logs'
New-Item -ItemType Directory -Force $mirror, $logDir, (Join-Path $sync 'git-remotes'), (Join-Path $sync 'snapshots') | Out-Null
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmm'
$log    = Join-Path $logDir "export_$stamp.log"
$falhas = @()

function Mirror($origem, $destino, $extras) {
    if (-not (Test-Path $origem)) { Write-Warning "PULADO (nao existe): $origem"; return }
    $args = @($origem, $destino, '/MIR', '/XJ', '/R:2', '/W:2', '/NFL', '/NDL', '/NP', "/LOG+:$log") + $extras
    robocopy @args | Out-Null
    if ($LASTEXITCODE -ge 8) { $script:falhas += "$origem (robocopy exit $LASTEXITCODE)" }
    else { Write-Host ("OK  {0}  ->  {1}" -f $origem, $destino) }
}

Write-Host "=== EXPORT $stamp ===" -ForegroundColor Cyan

# --- 1. Git: inner-guru -> repo bare no HD -------------------
$repo = 'C:\Dev\inner-guru'
$bare = Join-Path $sync 'git-remotes\inner-guru.git'
if (Test-Path $repo) {
    if (-not (Test-Path $bare)) { git init --bare $bare | Out-Null; Write-Host "Criado repo bare: $bare" }
    $remotes = git -C $repo remote
    if ($remotes -notcontains 'hd') { git -C $repo remote add hd $bare }
    git -C $repo push hd --all
    git -C $repo push hd --tags
    if ($LASTEXITCODE -ne 0) { $falhas += 'git push inner-guru' } else { Write-Host "OK  git push inner-guru -> hd" }
    $dirty = git -C $repo status --porcelain
    if ($dirty) { Write-Warning "ATENCAO: inner-guru tem mudancas NAO COMMITADAS - elas NAO viajam pelo git. Commit antes do export." }
} else { Write-Warning "PULADO: $repo nao existe" }

# --- 2. Espelhos robocopy ------------------------------------
Mirror 'C:\Workspace'                      (Join-Path $mirror 'Workspace')                  @('/XD','node_modules','.next','__pycache__','.venv')
Mirror 'C:\Dev\inner-guru-design-system'   (Join-Path $mirror 'Dev\inner-guru-design-system') @('/XD','node_modules','.next')
Mirror 'C:\Users\dpfre\.claude'            (Join-Path $mirror 'claude-home')                @('/XD','projects','shell-snapshots','tasks','worktrees','__pycache__')
Mirror 'C:\Users\dpfre\claude-instagram'   (Join-Path $mirror 'claude-instagram')           @('/XD','__pycache__')
Mirror 'C:\Users\dpfre\plugins'            (Join-Path $mirror 'plugins')                    @('/XD','node_modules','__pycache__')

# memoria do Claude Code (so as pastas memory\ de cada projeto)
$projRoot = 'C:\Users\dpfre\.claude\projects'
if (Test-Path $projRoot) {
    Get-ChildItem $projRoot -Directory | ForEach-Object {
        $mem = Join-Path $_.FullName 'memory'
        if (Test-Path $mem) { Mirror $mem (Join-Path $mirror "claude-home\projects\$($_.Name)\memory") @() }
    }
}

# config virtualizado do Claude Desktop (referencia p/ notebook novo)
$cfgDir = Join-Path $mirror 'configs'
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$vcfg = 'C:\Users\dpfre\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json'
if (Test-Path $vcfg) { Copy-Item $vcfg (Join-Path $cfgDir 'claude_desktop_config.virtualizado.json') -Force; Write-Host "OK  config virtualizado copiado" }

# --- 3. Snapshot datado (opcional) ---------------------------
if ($Snapshot) {
    $snapDir = Join-Path $sync "snapshots\$(Get-Date -Format 'yyyy-MM-dd')"
    robocopy $mirror $snapDir /E /R:2 /W:2 /NFL /NDL /NP "/LOG+:$log" | Out-Null
    if ($LASTEXITCODE -ge 8) { $falhas += 'snapshot' } else { Write-Host "OK  snapshot: $snapDir" }
    # retencao: manter os 3 mais recentes (apenas snapshots regulares AAAA-MM-DD)
    Get-ChildItem (Join-Path $sync 'snapshots') -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } |
        Sort-Object Name -Descending | Select-Object -Skip 3 |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force; Write-Host "Snapshot antigo removido: $($_.Name)" }
}

# --- Resumo ---------------------------------------------------
Write-Host ''
if ($falhas) { Write-Warning "EXPORT COM FALHAS: $($falhas -join '; ')  (ver log: $log)" ; exit 1 }
else { Write-Host "EXPORT CONCLUIDO SEM FALHAS. Log: $log" -ForegroundColor Green }
