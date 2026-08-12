# ============================================================
# export.ps1 — Exporta o workspace deste notebook para o HD
# Uso:  powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\export.ps1
#       (acrescente -Snapshot para gerar uma copia datada congelada)
# ============================================================
param([switch]$Snapshot, [switch]$NoEject)

$ErrorActionPreference = 'Continue'
$sync   = Split-Path -Parent $MyInvocation.MyCommand.Path
$mirror = Join-Path $sync 'mirror'
$logDir = Join-Path $sync 'logs'
New-Item -ItemType Directory -Force $mirror, $logDir, (Join-Path $sync 'git-remotes'), (Join-Path $sync 'snapshots') | Out-Null
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmm'
$log    = Join-Path $logDir "export_$stamp.log"
$falhas = @()

# --- helper: remocao robusta de arvore (nomes com [ ] @, caminhos > 260 chars) --
# Remove-Item -Recurse quebra com globs [ ] @ e com caminhos > MAX_PATH; esta versao
# apaga arquivo-a-arquivo via LiteralPath e usa o prefixo \\?\ como fallback.
function Remove-TreeRobust {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    # Metodo 1 - rmdir do cmd: rapido e ja remove arquivos somente-leitura.
    cmd /c rmdir /s /q "$Path" 2>$null
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    # Metodo 2 (fallback definitivo) - espelhar uma pasta VAZIA com robocopy.
    # robocopy lida nativamente com caminhos > 260 chars E apaga arquivos read-only
    # (objetos .git em subpastas profundas), que era o que travava a exclusao dos snapshots.
    $empty = Join-Path ([System.IO.Path]::GetTempPath()) ('_wsempty_' + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force $empty | Out-Null
    robocopy $empty "$Path" /MIR /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
    cmd /c rmdir /s /q "$Path" 2>$null
    if (Test-Path -LiteralPath $Path) {
        # Metodo 3 - ACL: "Acesso Negado" (Exit 5), tipico das pastas session-env do
        # Claude com ACL restritiva. Assume posse e libera permissao total, depois apaga.
        # So tem efeito com elevacao (admin); sem admin falha silenciosamente e o husk
        # fica (inofensivo - a retencao passou a ignorar pastas vazias).
        # icacls /setowner e /grant por SID well-known (independente de idioma):
        # S-1-5-32-544 = Administradores; S-1-1-0 = Todos.
        icacls "$Path" /setowner "*S-1-5-32-544" /T /C /Q 2>$null | Out-Null
        icacls "$Path" /grant "*S-1-1-0:(OI)(CI)F" /T /C /Q 2>$null | Out-Null
        cmd /c rmdir /s /q "$Path" 2>$null
    }
    Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue
    return (-not (Test-Path -LiteralPath $Path))
}

function Mirror($origem, $destino, $extras) {
    if (-not (Test-Path $origem)) { Write-Warning "PULADO (nao existe): $origem"; return }
    $args = @($origem, $destino, '/MIR', '/XJ', '/R:2', '/W:2', '/NFL', '/NDL', '/NP', "/LOG+:$log") + $extras
    $saida = robocopy @args
    if ($LASTEXITCODE -ge 8) {
        $script:falhas += "$origem (robocopy exit $LASTEXITCODE)"
        # exit >= 8 = algo NAO viajou. Mostra o caminho exato que falhou (licao de 11/08:
        # um husk com ACL quebrada no espelho travou a subarvore inteira do video-vox e o
        # unico rastro era um "FALHA 1" mudo na tabela do log).
        $erros = $saida | Select-String 'ERRO|0x0' | ForEach-Object { $_.Line.Trim() } | Select-Object -Unique
        if ($erros) { $erros | ForEach-Object { Write-Host "  >> $_" -ForegroundColor Red } }
        Write-Warning "FALHA no espelho de $origem - parte da arvore NAO viajou. Ver resumo FALHA no log: $log"
    }
    else { Write-Host ("OK  {0}  ->  {1}" -f $origem, $destino) }
}

Write-Host "=== EXPORT $stamp ===" -ForegroundColor Cyan
# destino resolvido (letra + rotulo do volume) - deixa visivel se caiu no HD certo
$drv  = (Split-Path $sync -Qualifier)                                   # ex.: "F:"
$vol  = Get-Volume -DriveLetter ($drv.TrimEnd(':')) -ErrorAction SilentlyContinue
$alvo = if ($vol) { "[$($vol.FileSystemLabel)] $drv  ->  $mirror" } else { "$drv  ->  $mirror" }
Write-Host "Destino do export: $alvo" -ForegroundColor Cyan

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
Mirror 'C:\Users\dpfre\.claude'            (Join-Path $mirror 'claude-home')                @('/XD','projects','shell-snapshots','tasks','worktrees','__pycache__','session-env','.in_use')
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
    # limpeza de husks: remove QUALQUER snapshot vazio (0 arquivos) - restos de
    # backup/remocao que falhou. Cobre tanto os diarios (AAAA-MM-DD) quanto os
    # pre-import; um husk vazio nunca e um backup util e distorce a retencao.
    Get-ChildItem (Join-Path $sync 'snapshots') -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
        ForEach-Object {
            if (Remove-TreeRobust $_.FullName) { Write-Host "Snapshot vazio (husk) removido: $($_.Name)" }
            else { Write-Warning "Husk vazio NAO removido: $($_.Name)"; $falhas += "husk snapshot ($($_.Name))" }
        }
    # retencao: manter os 3 mais recentes (apenas snapshots regulares AAAA-MM-DD e
    # NAO-VAZIOS - husk corrompido que resista a exclusao nao derruba backup real).
    Get-ChildItem (Join-Path $sync 'snapshots') -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
        Sort-Object Name -Descending | Select-Object -Skip 3 |
        ForEach-Object {
            if (Remove-TreeRobust $_.FullName) { Write-Host "Snapshot antigo removido: $($_.Name)" }
            else { Write-Warning "Snapshot antigo NAO removido por completo (possivel corrupcao de FS - rode chkdsk $drv /f): $($_.Name)"; $falhas += "retencao snapshot ($($_.Name))" }
        }
}

# --- 4. Verificacao pos-export: confirma que gravou MESMO no destino ----------
# Grava um carimbo no espelho e rele; pega o caso "SEM FALHAS" que na verdade
# escreveu no lugar errado / nao persistiu (falso positivo).
$stampFile = Join-Path $mirror ".last-export_${env:COMPUTERNAME}.txt"
$token     = "$stamp|$env:COMPUTERNAME"
try {
    Set-Content -LiteralPath $stampFile -Value $token -Encoding UTF8 -ErrorAction Stop
    $readBack = (Get-Content -LiteralPath $stampFile -Raw -ErrorAction Stop).Trim()
    if     ($readBack -ne $token)               { $falhas += "verificacao pos-export: carimbo nao confere (destino errado?)" }
    elseif (-not (Test-Path -LiteralPath $log)) { $falhas += "verificacao pos-export: log nao encontrado ($log)" }
    else   { Write-Host "OK  verificacao: gravacao confirmada em  $alvo" -ForegroundColor Green }
} catch {
    $falhas += "verificacao pos-export: nao consegui gravar/ler carimbo em $mirror ($($_.Exception.Message))"
}

# --- Marcador de reparo: sintoma de corrupcao de FS (husk/retencao que nao apagou,
# ou robocopy exit 15/16) deixa flag que o sync.ps1 le p/ rodar chkdsk automaticamente.
if ($falhas -match 'husk snapshot|retencao snapshot|exit 1[56]') {
    Set-Content -LiteralPath (Join-Path $sync '.needs-chkdsk') -Value $stamp -Encoding ASCII -ErrorAction SilentlyContinue
    Write-Warning "Sinal de corrupcao de FS detectado - chkdsk sera rodado no proximo sync (marcador .needs-chkdsk criado)."
}

# --- Resumo ---------------------------------------------------
Write-Host ''
if ($falhas) { Write-Warning "EXPORT COM FALHAS: $($falhas -join '; ')  (ver log: $log)" ; exit 1 }
else { Write-Host "EXPORT CONCLUIDO SEM FALHAS -> $alvo" -ForegroundColor Green }

# --- 5. Ejecao segura automatica -------------------------------
# Causa raiz dos chkdsk recorrentes: o Windows monta o SSD USB com cache de escrita
# (DriveType Fixed) e desconectar o cabo sem ejetar deixa metadados NTFS pela metade
# (eventos Ntfs 55/131). Ejetar aqui descarrega o cache e desmonta o volume - depois
# disso puxar o cabo e seguro. So ejeta com export 100% OK (com falhas o HD fica
# montado para diagnostico/re-execucao). Use -NoEject para manter montado.
if (-not $NoEject) {
    (New-Object -ComObject Shell.Application).Namespace(17).ParseName($drv).InvokeVerb('Eject')
    Start-Sleep -Seconds 4
    if (Test-Path -LiteralPath $sync) {
        Write-Warning "Ejecao automatica nao concluiu (algo segura o $drv - Explorer/terminal aberto nele?). Use 'Remover hardware com seguranca' antes de desconectar."
    } else {
        Write-Host "HD ejetado com seguranca - pode desconectar o cabo." -ForegroundColor Green
    }
}
# exit explicito: sem ele o "exit $rc" do sync.ps1 herda o codigo do ultimo comando
# nativo (robocopy exit 1 = sucesso) e reporta falso FALHA num export 100% OK.
exit 0
