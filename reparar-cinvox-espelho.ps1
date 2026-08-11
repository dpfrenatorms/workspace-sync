# ============================================================
# reparar-cinvox-espelho.ps1  (2026-08-11, sessao video-vox)
# Remove residuos com ACL quebrada no HD (ERRO 5 / acesso negado):
#   1. mirror\Workspace\Projetos\video-vox\assets\cin-vox   (husk que trava
#      a subarvore do video-vox no import/export - videos do Reiki nao viajaram)
#   2. snapshots\pre-import_DESKTOP-CQRID29_2026-08-08_2009 (husk vazio que a
#      retencao nao consegue remover)
# A ORIGEM em C: NAO e tocada. Roda de qualquer maquina.
# ============================================================

$alvos = @(
    'F:\WorkspaceSync\mirror\Workspace\Projetos\video-vox\assets\cin-vox',
    'F:\WorkspaceSync\snapshots\pre-import_DESKTOP-CQRID29_2026-08-08_2009'
)

function Nuke($d) {
    if (-not (Test-Path -LiteralPath $d)) { Write-Host "Ja nao existe: $d" -ForegroundColor Green; return $true }

    # 1) Metodo robusto: robocopy espelha pasta vazia (read-only + caminho longo)
    $e = Join-Path $env:TEMP ('_wsempty_' + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force $e | Out-Null
    robocopy $e $d /MIR /R:0 /W:0 /MT:32 /NFL /NDL /NP /NJH /NJS | Out-Null
    Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $e -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $d)) { Write-Host "Removido (nuke): $d" -ForegroundColor Green; return $true }

    # 2) ACL quebrada: takeown + icacls (ja estamos elevados neste ponto)
    takeown /f "$d" /r /d s | Out-Null
    icacls "$d" /grant "*S-1-5-32-544:(OI)(CI)F" /t /c | Out-Null
    icacls "$d" /grant "$($env:USERNAME):(OI)(CI)F" /t /c | Out-Null
    cmd /c rmdir /s /q "$d"
    if (-not (Test-Path -LiteralPath $d)) { Write-Host "Removido (takeown): $d" -ForegroundColor Green; return $true }

    Write-Warning "AINDA EXISTE: $d - rode chkdsk F: /f e execute este script de novo."
    return $false
}

# auto-elevacao (takeown/icacls precisam de admin quando a ACL nega ate leitura)
$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Solicitando elevacao (UAC)..." -ForegroundColor Yellow
    Start-Process powershell.exe "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$ok = $true
foreach ($a in $alvos) { if (-not (Nuke $a)) { $ok = $false } }

if ($ok) {
    Write-Host ""
    Write-Host "Tudo limpo. PROXIMOS PASSOS (nesta ordem, no VIVOBOOK):" -ForegroundColor Cyan
    Write-Host "  1. wsi   (import: traz o que ficou pendente do desktop - mensageria-reiki etc.)"
    Write-Host "     - o import reverte o repo video-vox ao estado do desktop; em seguida:"
    Write-Host "  2. cd C:\Workspace\Projetos\video-vox ; git pull origin main"
    Write-Host "     (restaura os commits de hoje: reiki-vox, skill Passo 7, style-reference)"
    Write-Host "  3. wse   (export: atualiza o espelho com o estado novo desta maquina)"
}
Read-Host 'Enter para sair'
