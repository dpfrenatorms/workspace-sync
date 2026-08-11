# ============================================================
# reparar-cinvox-espelho.ps1  (2026-08-11, sessao video-vox)
# Remove o husk corrompido do ESPELHO (ERRO 5 / ACL quebrada):
#   F:\WorkspaceSync\mirror\Workspace\Projetos\video-vox\assets\cin-vox
# Esse husk faz o robocopy do import/export FALHAR SILENCIOSAMENTE
# na subarvore inteira do video-vox ("Diretorios FALHA: 1" no log,
# sem linha de erro) - foi por isso que output\Reiki_Ansiedade_*.mp4
# nao viajou do desktop para o vivobook em 11/08.
# A ORIGEM em C: NAO e tocada. Roda de qualquer maquina.
# ============================================================

$d = 'F:\WorkspaceSync\mirror\Workspace\Projetos\video-vox\assets\cin-vox'

if (-not (Test-Path -LiteralPath $d)) { Write-Host "Ja nao existe - nada a fazer." -ForegroundColor Green; Read-Host 'Enter para sair'; exit 0 }

# 1) Metodo robusto (mesmo padrao da retencao corrigida): robocopy espelha pasta vazia
Write-Host "=== 1/3 Nuke via robocopy (lida com read-only e caminho longo) ===" -ForegroundColor Cyan
$e = Join-Path $env:TEMP ('_wsempty_' + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force $e | Out-Null
robocopy $e $d /MIR /R:0 /W:0 /MT:32 /NFL /NDL /NP /NJH /NJS | Out-Null
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $e -Recurse -Force -ErrorAction SilentlyContinue

# 2) Se resistiu, e ACL quebrada: takeown + icacls (pede UAC se preciso)
if (Test-Path -LiteralPath $d) {
    Write-Host "=== 2/3 ACL quebrada - takeown/icacls ===" -ForegroundColor Yellow
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Solicitando elevacao (UAC)..." -ForegroundColor Yellow
        Start-Process powershell.exe "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
    takeown /f "$d" /r /d s | Out-Null
    icacls "$d" /grant "*S-1-5-32-544:(OI)(CI)F" /t /c | Out-Null
    icacls "$d" /grant "$($env:USERNAME):(OI)(CI)F" /t /c | Out-Null
    cmd /c rmdir /s /q "$d"
}

# 3) Verificacao
if (Test-Path -LiteralPath $d) {
    Write-Warning "AINDA EXISTE. Rode: chkdsk F: /f  (corrupcao de metadados NTFS) e execute este script de novo."
    Read-Host 'Enter para sair'; exit 1
}
Write-Host "=== 3/3 Husk removido com sucesso. ===" -ForegroundColor Green
Write-Host ""
Write-Host "PROXIMOS PASSOS (nesta ordem, no VIVOBOOK):" -ForegroundColor Cyan
Write-Host "  1. Rode o IMPORT  (traz o que ficou pendente do desktop: mensageria-reiki etc.)"
Write-Host "     - o import vai reverter o repo video-vox ao estado do desktop; em seguida:"
Write-Host "  2. cd C:\Workspace\Projetos\video-vox ; git pull origin main   (restaura os commits de hoje: reiki-vox, skill Passo 7)"
Write-Host "  3. Rode o EXPORT  (atualiza o espelho com o estado novo desta maquina)"
Read-Host 'Enter para sair'
