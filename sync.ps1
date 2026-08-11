# ============================================================
# sync.ps1 — Ponto UNICO de entrada do workspace-sync
# Faz o reparo do FS (chkdsk) AUTOMATICAMENTE e so quando necessario, depois
# roda o import ou o export. Voce nunca mais precisa lembrar do chkdsk.
#
# Uso (normalmente via atalho ws-import / ws-export / ws-snap):
#   powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\sync.ps1 -Mode import
#   ... -Mode export | -Mode export-snap
#   ... -ForceRepair   (forca chkdsk mesmo sem marcador)
# ============================================================
param(
    [ValidateSet('import','export','export-snap')][string]$Mode = 'import',
    [switch]$ForceRepair,
    [switch]$Elevated   # interno: sinaliza que ja e a instancia elevada
)
$ErrorActionPreference = 'Continue'
$syncDir = 'F:\WorkspaceSync'
$drive   = 'F:'
$chkFlag = Join-Path $syncDir '.needs-chkdsk'

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
function Pause-IfElevated { if ($Elevated) { Write-Host ''; Read-Host 'Concluido. Pressione Enter para fechar' | Out-Null } }

# 0. HD montado como F:? (todo o fluxo depende disso)
if (-not (Test-Path $syncDir)) {
    Write-Host "HD nao encontrado em $drive\WorkspaceSync." -ForegroundColor Red
    Write-Host "Conecte o HD 'Data' e garanta que ele monte como $drive (Gerenciamento de Disco > Alterar letra)." -ForegroundColor Yellow
    Pause-IfElevated; exit 1
}

$needRepair = $ForceRepair -or (Test-Path $chkFlag)

# 1. Precisa reparar e ainda NAO esta elevado -> relanca elevado a partir de uma COPIA
#    LOCAL do script. (O chkdsk precisa desmontar o F:; nao podemos segurar handle
#    no volume rodando o proprio script de dentro dele.)
if ($needRepair -and -not (Test-Admin)) {
    $selfLocal = Join-Path $env:TEMP 'ws-sync.ps1'
    Copy-Item $PSCommandPath $selfLocal -Force
    Write-Host "Marcador de corrupcao de FS presente -> vou pedir elevacao para rodar chkdsk $drive antes do $Mode." -ForegroundColor Yellow
    $spArgs = @('-ExecutionPolicy','Bypass','-File',"`"$selfLocal`"",'-Mode',$Mode,'-Elevated')
    if ($ForceRepair) { $spArgs += '-ForceRepair' }
    Start-Process powershell -Verb RunAs -ArgumentList $spArgs
    exit 0
}

# 2. Reparo automatico (so quando elevado E necessario).
if ($needRepair -and (Test-Admin)) {
    Set-Location "$env:SystemDrive\"   # libera qualquer handle de CWD sobre o F:
    Write-Host "=== Reparo automatico: chkdsk $drive /f /x ===" -ForegroundColor Cyan
    Write-Host "(feche janelas do Explorer/terminais abertos no $drive; /x forca a desmontagem)" -ForegroundColor DarkGray
    cmd /c "chkdsk $drive /f /x"
    if ($LASTEXITCODE -le 1) {
        Remove-Item -LiteralPath $chkFlag -Force -ErrorAction SilentlyContinue
        Write-Host "OK  FS reparado; marcador limpo." -ForegroundColor Green
    } else {
        Write-Warning "chkdsk retornou codigo $LASTEXITCODE - o marcador foi mantido para tentar de novo no proximo sync."
    }
}

# 3. Executa o import/export de verdade.
$target = if ($Mode -eq 'import') { Join-Path $syncDir 'import.ps1' } else { Join-Path $syncDir 'export.ps1' }
$rest   = @(); if ($Mode -eq 'export-snap') { $rest += '-Snapshot' }
Write-Host "=== Rodando: $Mode ===" -ForegroundColor Cyan
& $target @rest
$rc = $LASTEXITCODE

Pause-IfElevated
exit $rc
