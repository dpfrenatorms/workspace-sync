# ============================================================
# import.ps1 — Aplica o estado do HD neste notebook
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
    # 1) arquivos (LiteralPath evita glob; \\?\ cobre caminho longo)
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        $fp = $_.FullName
        try { [System.IO.File]::Delete($fp) } catch { try { [System.IO.File]::Delete('\\?\' + $fp) } catch {} }
    }
    # 2) diretorios do mais profundo para o mais raso
    Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            $dp = $_.FullName
            try { [System.IO.Directory]::Delete($dp, $false) } catch { try { [System.IO.Directory]::Delete('\\?\' + $dp, $false) } catch {} }
        }
    # 3) raiz
    try { [System.IO.Directory]::Delete($Path, $true) } catch { try { [System.IO.Directory]::Delete('\\?\' + $Path, $true) } catch {} }
    return (-not (Test-Path -LiteralPath $Path))
}

if (-not (Test-Path $mirror)) { Write-Error "Espelho nao encontrado em $mirror - rode export.ps1 na outra maquina primeiro."; exit 1 }

# alvos: origem no espelho -> destino local
$alvos = @(
    @{ de = (Join-Path $mirror 'Workspace');                    para = 'C:\Workspace' },
    @{ de = (Join-Path $mirror 'Dev\inner-guru-design-system'); para = 'C:\Dev\inner-guru-design-system' },
    @{ de = (Join-Path $mirror 'claude-home');                  para = 'C:\Users\dpfre\.claude'; xd = @('projects') },
    @{ de = (Join-Path $mirror 'claude-instagram');             para = 'C:\Users\dpfre\claude-instagram' },
    @{ de = (Join-Path $mirror 'plugins');                      para = 'C:\Users\dpfre\plugins' }
)

Write-Host "=== IMPORT $stamp em $env:COMPUTERNAME ===" -ForegroundColor Cyan

# --- 0. Copia de seguranca do estado local atual --------------
if (-not $SemBackup) {
    $pre = Join-Path $sync "snapshots\pre-import_${env:COMPUTERNAME}_$stamp"
    foreach ($a in $alvos) {
        if (Test-Path $a.para) {
            $dst = Join-Path $pre (Split-Path $a.para -Leaf)
            robocopy $a.para $dst /E /XJ /R:1 /W:1 /NFL /NDL /NP /XD node_modules .next __pycache__ .venv projects "/LOG+:$log" | Out-Null
        }
    }
    Write-Host "Seguranca pre-import salva em: $pre"
    # retencao: manter as 2 mais recentes desta maquina
    Get-ChildItem (Join-Path $sync 'snapshots') -Directory -Filter "pre-import_${env:COMPUTERNAME}_*" |
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
    robocopy @rcArgs | Out-Null
    if ($LASTEXITCODE -ge 8) { $falhas += "$($a.para) (robocopy exit $LASTEXITCODE)" }
    else { Write-Host ("OK  {0}  ->  {1}" -f $a.de, $a.para) }
}

# --- 2b. Restaura memoria do Claude Code SEM destruir a local -------
# O /MIR do claude-home NAO toca em 'projects' (excluido acima) para nunca apagar
# sessoes/memoria locais. Aqui trazemos de volta as pastas memory\ do espelho de
# forma ADITIVA (/E, sem delete): arquivos do HD sobrescrevem/adicionam, os locais
# que nao estao no HD permanecem. Evita o bug de o import zerar a memoria do Claude.
$memRoot = Join-Path $mirror 'claude-home\projects'
if (Test-Path $memRoot) {
    Get-ChildItem $memRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $srcMem = Join-Path $_.FullName 'memory'
        if (Test-Path $srcMem) {
            $dstMem = "C:\Users\dpfre\.claude\projects\$($_.Name)\memory"
            robocopy $srcMem $dstMem /E /R:2 /W:2 /NFL /NDL /NP "/LOG+:$log" | Out-Null
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

# --- Resumo ----------------------------------------------------
Write-Host ''
Write-Host 'Lembretes pos-import: npm install (se package.json mudou), Docker/Claude Desktop fechados durante o import, reabrir apps.'
if ($falhas) { Write-Warning "IMPORT COM PENDENCIAS: $($falhas -join '; ')  (ver log: $log)"; exit 1 }
else { Write-Host "IMPORT CONCLUIDO SEM FALHAS. Log: $log" -ForegroundColor Green }
