# ============================================================
# import.ps1 â€” Aplica o estado do HD neste notebook
# Uso:  powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\import.ps1
#       (acrescente -SemBackup para pular a copia de seguranca pre-import)
# Rode SEMPRE antes de comecar a trabalhar na maquina que estava parada.
# ============================================================
param([switch]$SemBackup)

$ErrorActionPreference = 'Continue'
$sync   = Split-Path -Parent $MyInvocation.MyCommand.Path
$mirror = Join-Path $sync 'mirror'
$logDir = Join-Path $sync 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp  = Get-Date -Format 'yyyy-MM-dd_HHmm'
$log    = Join-Path $logDir "import_${env:COMPUTERNAME}_$stamp.log"
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

if (-not (Test-Path $mirror)) { Write-Error "Espelho nao encontrado em $mirror - rode export.ps1 na outra maquina primeiro."; exit 1 }

# alvos: origem no espelho -> destino local
$alvos = @(
    @{ de = (Join-Path $mirror 'Workspace');                    para = 'C:\Workspace' },
    @{ de = (Join-Path $mirror 'Dev\inner-guru-design-system'); para = 'C:\Dev\inner-guru-design-system' },
    @{ de = (Join-Path $mirror 'claude-home');                  para = 'C:\Users\dpfre\.claude'; xd = @('projects','session-env','.in_use') },
    @{ de = (Join-Path $mirror 'claude-instagram');             para = 'C:\Users\dpfre\claude-instagram' },
    @{ de = (Join-Path $mirror 'plugins');                      para = 'C:\Users\dpfre\plugins' }
)

Write-Host "=== IMPORT $stamp em $env:COMPUTERNAME ===" -ForegroundColor Cyan

# --- 0. Copia de seguranca do estado local atual --------------
if (-not $SemBackup) {
    $pre = Join-Path $sync "snapshots\pre-import_${env:COMPUTERNAME}_$stamp"
    New-Item -ItemType Directory -Force $pre | Out-Null
    foreach ($a in $alvos) {
        if (Test-Path $a.para) {
            $dst = Join-Path $pre (Split-Path $a.para -Leaf)
            robocopy $a.para $dst /E /XJ /R:1 /W:1 /NFL /NDL /NP /XD node_modules .next __pycache__ .venv projects session-env shell-snapshots tasks worktrees "/LOG+:$log" | Out-Null
            if ($LASTEXITCODE -ge 8) { Write-Warning "Backup pre-import FALHOU: $($a.para) (robocopy exit $LASTEXITCODE)"; $falhas += "backup pre-import $($a.para) (robocopy exit $LASTEXITCODE)" }
        }
    }
    # 'projects' fica de fora do backup acima (sessoes ocupam GBs), mas a memoria do
    # Claude precisa de rede de seguranca: copia apenas as pastas projects\*\memory\.
    $projLocal = 'C:\Users\dpfre\.claude\projects'
    if (Test-Path $projLocal) {
        Get-ChildItem $projLocal -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $srcMem = Join-Path $_.FullName 'memory'
            if (Test-Path $srcMem) {
                $dstMemBk = Join-Path $pre ".claude\projects\$($_.Name)\memory"
                robocopy $srcMem $dstMemBk /E /R:1 /W:1 /NFL /NDL /NP "/LOG+:$log" | Out-Null
                if ($LASTEXITCODE -ge 8) { Write-Warning "Backup pre-import da memoria FALHOU: $($_.Name) (robocopy exit $LASTEXITCODE)"; $falhas += "backup memory $($_.Name) (robocopy exit $LASTEXITCODE)" }
            }
        }
    }
    Write-Host "Seguranca pre-import salva em: $pre"
    # limpeza de husks: remove QUALQUER snapshot pre-import vazio (0 arquivos), de
    # qualquer maquina. Sao restos de backup que falhou (robocopy exit>=8 por FS/ACL)
    # ou de remocao incompleta. Um husk vazio NAO e backup e, contado como "recente",
    # empurra um backup bom para fora do skip-2 - por isso some ele ANTES da retencao.
    # (Roda em todas as maquinas porque a retencao abaixo so olha a maquina atual.)
    Get-ChildItem (Join-Path $sync 'snapshots') -Directory -Filter 'pre-import_*' -ErrorAction SilentlyContinue |
        Where-Object { -not (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
        ForEach-Object {
            if (Remove-TreeRobust $_.FullName) { Write-Host "Snapshot vazio (husk) removido: $($_.Name)" }
            else { Write-Warning "Husk vazio NAO removido: $($_.Name)"; $falhas += "husk snapshot ($($_.Name))" }
        }
    # retencao: manter as 2 mais recentes desta maquina. So conta snapshots NAO-VAZIOS:
    # se um husk corrompido no NTFS resistir a exclusao acima (precisa de chkdsk), ele
    # nao entra na contagem e portanto nunca derruba um backup real do corte do skip-2.
    Get-ChildItem (Join-Path $sync 'snapshots') -Directory -Filter "pre-import_${env:COMPUTERNAME}_*" |
        Where-Object { Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1 } |
        Sort-Object Name -Descending | Select-Object -Skip 2 |
        ForEach-Object {
            if (Remove-TreeRobust $_.FullName) { Write-Host "Snapshot antigo removido: $($_.Name)" }
            else { Write-Warning "Snapshot antigo NAO removido por completo (possivel corrupcao de FS - rode chkdsk $((Split-Path $sync -Qualifier)) /f): $($_.Name)"; $falhas += "retencao snapshot ($($_.Name))" }
        }
}

# --- 1. Git: inner-guru --------------------------------------
$repo = 'C:\Dev\inner-guru'
$bare = Join-Path $sync 'git-remotes\inner-guru.git'
if (Test-Path $bare) {
    if (-not (Test-Path $repo)) {
        New-Item -ItemType Directory -Force 'C:\Dev' | Out-Null
        git clone $bare $repo
        git -C $repo remote rename origin hd
        Write-Host "OK  clone inicial do inner-guru (lembre: npm install em apps\frontend)"
    } else {
        $dirty = git -C $repo status --porcelain
        if ($dirty) { Write-Warning "inner-guru tem mudancas locais nao commitadas - pull NAO sera feito. Resolva manualmente (commit/stash) e rode: git pull hd <branch>"; $falhas += 'git pull inner-guru (working tree sujo)' }
        else {
            git -C $repo fetch hd
            git -C $repo merge --ff-only "hd/$(git -C $repo rev-parse --abbrev-ref HEAD)"
            if ($LASTEXITCODE -ne 0) { Write-Warning "Merge nao foi fast-forward - historico divergiu entre as maquinas. Resolva manualmente."; $falhas += 'git merge inner-guru' }
            else { Write-Host "OK  inner-guru atualizado via git" }
        }
    }
} else { Write-Warning "Repo bare nao existe no HD - rode export.ps1 na outra maquina." }

# --- 2. Espelhos -> local -------------------------------------
foreach ($a in $alvos) {
    if (-not (Test-Path $a.de)) { Write-Warning "PULADO (nao esta no espelho): $($a.de)"; continue }
    $rcArgs = @($a.de, $a.para, '/MIR', '/XJ', '/R:2', '/W:2', '/NFL', '/NDL', '/NP', "/LOG+:$log")
    if ($a.xd) { $rcArgs += '/XD'; $rcArgs += $a.xd }   # /MIR nunca apaga estas subpastas locais
    $saida = robocopy @rcArgs
    if ($LASTEXITCODE -ge 8) {
        $falhas += "$($a.para) (robocopy exit $LASTEXITCODE)"
        # exit >= 8 = algo NAO viajou. Mostra o caminho exato que falhou (licao de 11/08:
        # husk com ACL quebrada em mirror\...\video-vox\assets\cin-vox travou a subarvore
        # inteira do video-vox e os videos do Reiki nao chegaram - o unico rastro era um
        # "FALHA 1" mudo na tabela do log).
        $erros = $saida | Select-String 'ERRO|0x0' | ForEach-Object { $_.Line.Trim() } | Select-Object -Unique
        if ($erros) { $erros | ForEach-Object { Write-Host "  >> $_" -ForegroundColor Red } }
        Write-Warning "FALHA no espelho para $($a.para) - parte da arvore NAO veio. Ver resumo FALHA no log: $log"
    }
    else { Write-Host ("OK  {0}  ->  {1}" -f $a.de, $a.para) }
}

# --- 2b. Restaura memoria do Claude Code SEM destruir a local -------
# O /MIR do claude-home NAO toca em 'projects' (excluido acima) para nunca apagar
# sessoes/memoria locais. Aqui trazemos de volta as pastas memory\ do espelho de
# forma ADITIVA (/E, sem delete): o HD adiciona/atualiza, os locais que nao estao no
# HD permanecem. /XO impede que uma versao mais antiga do HD sobrescreva uma memoria
# local mais nova. Evita o bug de o import zerar a memoria do Claude.
$memRoot = Join-Path $mirror 'claude-home\projects'
if (Test-Path $memRoot) {
    Get-ChildItem $memRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $srcMem = Join-Path $_.FullName 'memory'
        if (Test-Path $srcMem) {
            $dstMem = "C:\Users\dpfre\.claude\projects\$($_.Name)\memory"
            robocopy $srcMem $dstMem /E /XO /R:2 /W:2 /NFL /NDL /NP "/LOG+:$log" | Out-Null
            if ($LASTEXITCODE -ge 8) { $falhas += "restore memory $($_.Name) (robocopy exit $LASTEXITCODE)" }
            else { Write-Host "OK  memory restaurada: $($_.Name)" }
        }
    }
}

# --- 3. Config do Claude Desktop (so no primeiro setup) -------
$vcfgRef = Join-Path $mirror 'configs\claude_desktop_config.virtualizado.json'
$pkg = Get-ChildItem 'C:\Users\dpfre\AppData\Local\Packages' -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pkg -and (Test-Path $vcfgRef)) {
    $vcfgLocal = Join-Path $pkg.FullName 'LocalCache\Roaming\Claude\claude_desktop_config.json'
    if (-not (Test-Path $vcfgLocal)) {
        New-Item -ItemType Directory -Force (Split-Path $vcfgLocal) | Out-Null
        Copy-Item $vcfgRef $vcfgLocal
        Write-Host "OK  config do Claude Desktop aplicado (primeiro setup)"
    } else {
        Write-Host "AVISO: Claude Desktop ja tem config nesta maquina - NAO sobrescrito. Se faltar MCP servers, copie so o bloco 'mcpServers' de: $vcfgRef"
    }
}

# --- Marcador de reparo: se houve sintoma de corrupcao de FS (husk/retencao que nao
# apagou, ou robocopy exit 15/16), deixa um flag que o sync.ps1 le para rodar chkdsk
# automaticamente na proxima vez - sem voce ter que lembrar. Erros comuns (ex.: exit 11
# do automacao-reiki) NAO acionam chkdsk.
if ($falhas -match 'husk snapshot|retencao snapshot|exit 1[56]') {
    Set-Content -LiteralPath (Join-Path $sync '.needs-chkdsk') -Value $stamp -Encoding ASCII -ErrorAction SilentlyContinue
    Write-Warning "Sinal de corrupcao de FS detectado - chkdsk sera proposto/rodado no proximo sync (marcador .needs-chkdsk criado)."
}

# --- Resumo ----------------------------------------------------
Write-Host ''
Write-Host 'Lembretes pos-import: npm install (se package.json mudou), Docker/Claude Desktop fechados durante o import, reabrir apps.'
if ($falhas) { Write-Warning "IMPORT COM PENDENCIAS: $($falhas -join '; ')  (ver log: $log)"; exit 1 }
else { Write-Host "IMPORT CONCLUIDO SEM FALHAS. Log: $log" -ForegroundColor Green }
