# ============================================================
# aliases.ps1 — Atalhos de sincronizacao do workspace
# Carregado pelo $PROFILE de cada maquina (linha unica que da dot-source aqui).
# Como as definicoes moram no HD, atualizar este arquivo atualiza as duas maquinas.
# ============================================================

# Todos passam pelo sync.ps1 (ponto unico): ele faz chkdsk automatico SO quando o HD
# esta marcado como corrompido e depois roda o import/export. Sem retrabalho manual.
function ws-import { powershell -ExecutionPolicy Bypass -File 'F:\WorkspaceSync\sync.ps1' -Mode import @args }        # importar o estado do HD
function ws-export { powershell -ExecutionPolicy Bypass -File 'F:\WorkspaceSync\sync.ps1' -Mode export @args }        # exportar este notebook para o HD
function ws-snap   { powershell -ExecutionPolicy Bypass -File 'F:\WorkspaceSync\sync.ps1' -Mode export-snap @args }   # export + snapshot datado
function ws-repair { powershell -ExecutionPolicy Bypass -File 'F:\WorkspaceSync\sync.ps1' -Mode import -ForceRepair @args }  # forca chkdsk + import

Set-Alias wsi ws-import
Set-Alias wse ws-export

Write-Host "Atalhos workspace-sync: ws-import (wsi) | ws-export (wse) | ws-snap | ws-repair" -ForegroundColor DarkGray
