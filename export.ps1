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
# Causa raiz dos chkdsk recorrentes: o SSD USB e UASP (enumera como SCSI\DISK, disco
# "Fixo") e o Windows usa cache de escrita; puxar o cabo sem desmontar deixa metadados
# NTFS pela metade (Ntfs 55/131). Licao de 12/08: em disco Fixo o Shell NAO expoe o
# verbo Eject (mesma razao pela qual a bandeja "Remover hardware" nao lista o SSD) -
# o InvokeVerb('Eject') antigo era um no-op silencioso. A via que funciona e a API
# CM_Request_Device_Eject (cfgmgr32, a mesma do RemoveDrive): flush + desmonta +
# remove o devnode; ao reconectar o cabo o disco remonta sozinho. So ejeta com export
# 100% OK (com falhas o HD fica montado para diagnostico). Use -NoEject para manter.
# Licao de 13/08: chamar Eject no no do disco (nao-ejetavel) pode voltar VETO
# "ilegal" antes de subirmos ao pai - agora escolhemos ANTES, por capability, o
# primeiro ancestral REMOVABLE/EJECTSUPPORTED (no UAS USB\VID_...) e ejetamos ele.
# O desfecho vai para o log ("EJECT: ...") para diagnostico entre maquinas.
if (-not $NoEject) {
    Set-Location "$env:SystemDrive\"   # nao segurar CWD no volume que vai ser ejetado
    $ejectLog = { param($msg) Add-Content -LiteralPath $log -Value "EJECT: $msg" -Encoding UTF8 -ErrorAction SilentlyContinue }
    try {
        Add-Type -Namespace WsSync -Name CfgMgr -MemberDefinition @'
[DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
public static extern int CM_Locate_DevNodeW(out uint devInst, string deviceId, uint flags);
[DllImport("cfgmgr32.dll")]
public static extern int CM_Get_Parent(out uint parent, uint devInst, uint flags);
[DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
public static extern int CM_Get_Device_IDW(uint devInst, System.Text.StringBuilder buffer, uint len, uint flags);
[DllImport("cfgmgr32.dll")]
public static extern int CM_Get_DevNode_Registry_PropertyW(uint devInst, uint prop, out uint regType, byte[] buffer, ref uint len, uint flags);
[DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
public static extern int CM_Request_Device_EjectW(uint devInst, out int vetoType, System.Text.StringBuilder vetoName, uint nameLen, uint flags);
'@ -ErrorAction Stop
        $letra   = $drv.TrimEnd(':')
        $diskNum = (Get-Partition -DriveLetter $letra -ErrorAction Stop | Select-Object -First 1).DiskNumber
        $pnpId   = (Get-CimInstance Win32_DiskDrive -Filter "Index=$diskNum" -ErrorAction Stop).PNPDeviceID
        [uint32]$dev = 0
        if ([WsSync.CfgMgr]::CM_Locate_DevNodeW([ref]$dev, $pnpId, 0) -ne 0) { throw "CM_Locate_DevNode falhou para $pnpId" }
        # Seleciona por capability (CM_DRP_CAPABILITIES=0x10) o primeiro no da cadeia
        # com REMOVABLE (0x4) ou EJECTSUPPORTED (0x2). No UASP o no do disco SCSI\DISK
        # NAO e ejetavel; o ejetavel e o pai USB\VID_... (armazenamento UAS).
        $alvoDev = 0; $alvoId = ''
        for ($i = 0; $i -lt 5; $i++) {
            $buf = New-Object byte[] 4; [uint32]$len = 4; [uint32]$rt = 0
            $caps = 0
            if ([WsSync.CfgMgr]::CM_Get_DevNode_Registry_PropertyW($dev, 0x10, [ref]$rt, $buf, [ref]$len, 0) -eq 0) {
                $caps = [BitConverter]::ToUInt32($buf, 0)
            }
            if ($caps -band 0x6) {
                $sbId = New-Object System.Text.StringBuilder 512
                [void][WsSync.CfgMgr]::CM_Get_Device_IDW($dev, $sbId, 512, 0)
                $alvoDev = $dev; $alvoId = $sbId.ToString(); break
            }
            [uint32]$pai = 0
            if ([WsSync.CfgMgr]::CM_Get_Parent([ref]$pai, $dev, 0) -ne 0) { break }
            $dev = $pai
        }
        if (-not $alvoDev) { throw "nenhum devnode ejetavel (REMOVABLE/EJECTSUPPORTED) na cadeia de $pnpId" }
        # Ejeta o no escolhido; 1 retry apos 1s se falhar sem veto nomeado (transiente).
        $ejetado = $false; $vetoNome = ''; [int]$vetoTipo = 0; $rc = -1
        for ($tent = 1; $tent -le 2; $tent++) {
            $sb = New-Object System.Text.StringBuilder 260
            $vetoTipo = 0
            $rc = [WsSync.CfgMgr]::CM_Request_Device_EjectW($alvoDev, [ref]$vetoTipo, $sb, 260, 0)
            $vetoNome = $sb.ToString()
            if ($rc -eq 0 -and $vetoTipo -eq 0) { $ejetado = $true; break }
            if ($vetoNome) { break }   # veto real (handle/app segurando) - retry nao resolve
            Start-Sleep -Seconds 1
        }
        Start-Sleep -Seconds 2
        if ($ejetado -and -not (Test-Path -LiteralPath $sync)) {
            Write-Host "HD ejetado com seguranca - pode desconectar o cabo." -ForegroundColor Green
            & $ejectLog "ok ($alvoId)"
        } elseif ($vetoNome) {
            Write-Warning "Ejecao VETADA (tipo $vetoTipo) por: $vetoNome - feche Explorer/terminal/VS Code abertos no $drv e rode 'wse' de novo, ou desmonte manualmente."
            & $ejectLog "vetada tipo=$vetoTipo por=$vetoNome (no $alvoId)"
        } elseif ($ejetado) {
            # CM disse ok mas o volume ainda responde - remontagem instantanea? reportar.
            Write-Warning "CM reportou ejecao OK mas $drv ainda esta montado - desmonte manualmente antes de desconectar o cabo."
            & $ejectLog "cm-ok-mas-montado (no $alvoId)"
        } else {
            Write-Warning "Ejecao automatica nao concluiu (CM retorno $rc, veto tipo $vetoTipo, no $alvoId). Desmonte manualmente antes de desconectar o cabo."
            & $ejectLog "rc=$rc vetoTipo=$vetoTipo (no $alvoId)"
        }
    } catch {
        Write-Warning "Ejecao automatica falhou: $($_.Exception.Message). Desmonte manualmente antes de desconectar o cabo."
        & $ejectLog "exception: $($_.Exception.Message)"
    }
}
# exit explicito: sem ele o "exit $rc" do sync.ps1 herda o codigo do ultimo comando
# nativo (robocopy exit 1 = sucesso) e reporta falso FALHA num export 100% OK.
exit 0
