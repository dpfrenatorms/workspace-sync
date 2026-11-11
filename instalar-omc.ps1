# ============================================================
# instalar-omc.ps1 — Finaliza a instalacao do plugin oh-my-claudecode
# Uso:  powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\instalar-omc.ps1
#       (ou o atalho  ws-omc  definido em aliases.ps1)
#
# POR QUE ESTE SCRIPT EXISTE
# O "/plugin install oh-my-claudecode" clona o repositorio e roda npm install,
# mas NAO roda o build. Os 6 artefatos de bridge/ sao gerados no empacotamento
# do npm e nao existem no Git. Sem eles o servidor MCP "t" do plugin morre com
# CONNECTION_CLOSED e as 50 ferramentas dele (LSP, ast-grep, python_repl,
# state_*, notepad_*, wiki_*, project_memory_*) ficam indisponiveis - as skills
# carregam, mas o maquinario por tras delas nao.
#
# PRE-REQUISITO: rodar antes, DENTRO do Claude Code:
#   /plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode
#   /plugin install oh-my-claudecode
# Depois deste script: reiniciar o Claude Code e rodar /omc-setup.
# ============================================================
param([switch]$SkipVerify)

$ErrorActionPreference = 'Continue'

Write-Host "=== INSTALAR OMC ===" -ForegroundColor Cyan

# --- 1. Localiza a instalacao (a maior versao presente) ------
$cacheRoot = Join-Path $env:USERPROFILE '.claude\plugins\cache\omc\oh-my-claudecode'
if (-not (Test-Path $cacheRoot)) {
    Write-Warning "Plugin nao encontrado em: $cacheRoot"
    Write-Host   "Rode primeiro, dentro do Claude Code:" -ForegroundColor Yellow
    Write-Host   "  /plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode"
    Write-Host   "  /plugin install oh-my-claudecode"
    exit 1
}
$alvo = Get-ChildItem $cacheRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
if (-not $alvo) { Write-Warning "Nenhuma pasta de versao em $cacheRoot"; exit 1 }
$P = $alvo.FullName
Write-Host "Plugin: $P" -ForegroundColor Cyan

# --- 2. Node presente? ---------------------------------------
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Write-Warning "node nao esta no PATH. Instale o Node.js (v20 a v26)."; exit 1 }
Write-Host ("Node: {0}" -f (& node -v))

# --- 3. Dependencias (o /plugin install normalmente ja fez) ---
# node_modules tem binarios nativos (.node) especificos de plataforma. Se o
# espelho do HD trouxe node_modules de uma maquina de arquitetura diferente,
# apague a pasta e rode este script de novo para refazer o npm install.
if (-not (Test-Path (Join-Path $P 'node_modules'))) {
    Write-Host "node_modules ausente - rodando npm install (demora)..." -ForegroundColor Yellow
    Push-Location $P
    & npm install
    $rc = $LASTEXITCODE
    Pop-Location
    if ($rc -ne 0) { Write-Warning "npm install falhou (exit $rc)"; exit 1 }
}

# --- 4. Build dos 6 artefatos de bridge/ ----------------------
$scripts = @(
    'build-mcp-server.mjs',
    'build-cli.mjs',
    'build-team-server.mjs',
    'build-claude-md-coordinator.mjs',
    'build-runtime-cli.mjs'
)
$falhas = @()
Push-Location $P
foreach ($s in $scripts) {
    $caminho = Join-Path $P "scripts\$s"
    if (-not (Test-Path $caminho)) { $falhas += "$s (script ausente)"; Write-Warning "AUSENTE  $s"; continue }
    & node $caminho
    if ($LASTEXITCODE -ne 0) { $falhas += "$s (exit $LASTEXITCODE)"; Write-Warning "FALHA  $s" }
    else { Write-Host "OK  $s" -ForegroundColor Green }
}
Pop-Location

# --- 5. Verificacao ------------------------------------------
if (-not $SkipVerify) {
    Write-Host "--- verificacao ---" -ForegroundColor Cyan
    $esperados = @('mcp-server.cjs','cli.cjs','team.js','team-mcp.cjs','claude-md-coordinator.cjs','runtime-cli.cjs')
    foreach ($f in $esperados) {
        if (Test-Path (Join-Path $P "bridge\$f")) { Write-Host "OK     bridge\$f" -ForegroundColor Green }
        else { $falhas += "bridge\$f ausente"; Write-Warning "FALTA  bridge\$f" }
    }

    # CLI: prova funcional de que o bundle carrega
    $ver = & node (Join-Path $P 'bin\oh-my-claudecode.js') --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $ver) { Write-Host "OK     CLI omc responde: $ver" -ForegroundColor Green }
    else { $falhas += 'CLI omc nao responde'; Write-Warning "FALHA  CLI omc nao responde" }

    # Servidor MCP "t": handshake JSON-RPC com timeout (nao deixa pendurar)
    $job = Start-Job -ScriptBlock {
        param($dir)
        $req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}'
        Set-Location $dir
        $req | & node (Join-Path $dir 'bridge\mcp-server.cjs') 2>$null
    } -ArgumentList $P
    if (Wait-Job $job -Timeout 60) {
        $saida = Receive-Job $job -ErrorAction SilentlyContinue
        if ($saida -match 'serverInfo') { Write-Host "OK     servidor MCP 't' responde o handshake" -ForegroundColor Green }
        else { $falhas += "servidor MCP 't' nao respondeu"; Write-Warning "FALHA  servidor MCP 't' nao respondeu" }
    } else {
        Write-Warning "INCONCLUSIVO  handshake do MCP estourou 60s (nao e necessariamente erro)"
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

# --- 6. Resumo -----------------------------------------------
Write-Host ""
if ($falhas.Count -gt 0) {
    Write-Host "=== FALHAS ===" -ForegroundColor Red
    $falhas | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "=== OK: build completo ===" -ForegroundColor Green
Write-Host "Proximos passos: reinicie o Claude Code e rode /omc-setup" -ForegroundColor Yellow
