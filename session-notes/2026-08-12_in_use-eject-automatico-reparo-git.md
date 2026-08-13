# Memória de Sessão — Fix `.in_use`, auto-eject no export e reparo do repo git

- **Data:** 2026-08-12
- **Máquina:** `DESKTOP-CQRID29` (nt2), HD SSD SanDisk `Data` em `F:`
- **Escopo:** import de rotina que expôs três problemas encadeados — todos resolvidos ou com prevenção implantada.

## Setup feito nesta máquina

- Criado `C:\Users\dpfre\Documents\WindowsPowerShell\profile.ps1` com dot-source guardado
  (`Test-Path`) do `F:\WorkspaceSync\aliases.ps1` → atalhos `wsi`/`wse`/`ws-snap`/`ws-repair`
  disponíveis em qualquer terminal novo, sem erro quando o HD está desconectado.
- `export.ps1` estava deletado do HD (aparecia `D export.ps1` no git) — restaurado via
  `git checkout`. Sem ele o `wse` quebrava (o `sync.ps1` o chama no modo export).

## 1. A falha "de rotina" do import (`robocopy exit 11` no `.claude`)

Todo import falhava no mesmo ponto: `ERRO 2` em
`mirror\claude-home\plugins\cache\contador-irpf-2026-marketplace\...\.in_use\12212`.

- **O que é:** `.in_use\<PID>` é marcador de lock que o Claude Code cria em runtime no
  cache de plugins. É volátil e específico da máquina — **nunca deveria viajar pelo HD**.
  No espelho ele virou entrada de diretório órfã (ilegível), quebrando todo import.
- **Correção (feita):**
  1. Removido o `.in_use` órfão do espelho (`cmd /c rmdir`).
  2. `export.ps1`: `.in_use` adicionado ao `/XD` do espelho `.claude`.
  3. `import.ps1`: `.in_use` adicionado ao `xd` do alvo `claude-home`.

## 2. Corrupção NTFS recorrente — NÃO é hardware (confirmado)

A mídia foi trocada por SSD novo e as falhas continuaram. Evidência coletada:

- Disco físico: `Healthy`. Volume NTFS: `HealthStatus Warning`, **`Full Repair Needed`**.
- Event log: dezenas de `Ntfs 55` (corrupção detectada) durante o import; `Ntfs 131`
  ("estrutura não pode ser corrigida") = auto-reparo online desistiu, só chkdsk offline.
- **Causa raiz:** o SSD USB monta como disco **"Fixo"** → Windows usa cache de escrita.
  Desconectar o cabo sem ejetar deixa metadados NTFS pela metade. Agravante: a bandeja
  "Remover hardware com segurança" **nem lista** esses SSDs — nunca houve como ejetar.
- Marcador `.needs-chkdsk` criado (o próximo `wsi`/`wse` roda `chkdsk F: /f /x` sozinho).

### Prevenção implantada (para o chkdsk parar de reaparecer)

1. **Auto-eject:** `export.ps1` agora ejeta o HD com segurança ao terminar **sem falhas**
   (flush do cache + desmonta; ao reconectar monta sozinho — zero retrabalho, diferente
   da sugestão de deixar o disco offline, que exige montagem manual a cada uso).
   Opt-out: `wse -NoEject` (repassado pelo `sync.ps1`, inclusive no caminho elevado).
2. **Remoção rápida (pendente, 1x por notebook):** `devmgmt.msc` → Unidades de disco →
   SanDisk Portable SSD → aba Diretivas → "Remoção rápida" (desliga o cache de escrita).
3. LEIA-ME: nova seção "Integridade do HD (evitar chkdsk recorrente)".

## 3. Repo git do HD corrompido de novo (reincidência do episódio 11/08)

`git log` falhava: commit `234281e` (pai do HEAD) e 2 blobs **ausentes** + reflogs inválidos.

- **Reparo:** `origin/main` (GitHub `dpfrenatorms/workspace-sync`) estava íntegro e no
  MESMO hash do HEAD local (`5929fc3`) → nada não-pushado em risco. Feito
  `git clone --mirror` para pasta temporária e **copiado o pack** para
  `F:\WorkspaceSync\.git\objects\pack\`; `git reflog expire --expire=now --all`;
  `fsck --full` limpo (só dangling commits inofensivos).
- **Padrão do reparo** (vale para a próxima): enxertar pack do GitHub é aditivo e seguro;
  só funciona porque o repo vive espelhado no GitHub — **manter o hábito do push**.

## Pendências

- [x] Rodar `wsi` uma vez → chkdsk F: /f /x automático (UAC) + import de verificação limpo. *(feito 12/08 ~08:44 — "IMPORT CONCLUIDO SEM FALHAS"; volume voltou a `Healthy/OK`)*
- [ ] Ativar "Remoção rápida" nos DOIS notebooks (nt2 e vivobook).
- [x] `git push` deste commit para o GitHub. *(feito — e salvou o repo DUAS vezes no mesmo dia, ver adendo)*
- [x] Confirmar um ciclo `wse` → `wsi` sem falhas e sem novo `Ntfs 55` no event log. *(export 08:58 "SEM FALHAS" + import 08:44 limpos; zero eventos Ntfs pós-chkdsk)*

## Adendo (mesma sessão, pós-chkdsk) — mais duas lições

1. **chkdsk descarta dados escritos durante a corrupção.** O reparo zerou `export.ps1`,
   `sync.ps1` e objetos git soltos (inclusive o pack enxertado de manhã) — todos
   arquivos ESCRITOS enquanto o volume estava corrompido (`found.000` criado no F:).
   Recuperação: mesmo procedimento do pack do GitHub + `git checkout`. **Regra: commit
   + push ANTES de rodar chkdsk; se escrever com o volume doente, considere perdido.**
2. **Splat de array não liga switch nomeado (PS 5.1).** No `sync.ps1`,
   `$rest = @('-NoEject'); & $target @rest` passava a string como argumento posicional
   morto — o `-NoEject` era ignorado e, pior, o `-Snapshot` do `ws-snap` NUNCA tinha
   chegado ao `export.ps1` (bug latente desde a criação: ws-snap rodava export comum).
   Correção: splat por **hashtable** (`$rest = @{}; $rest.NoEject = $true`).
   Também adicionados `exit 0` explícitos no fim de `export.ps1`/`import.ps1` — sem
   isso o `exit $rc` do sync herdava `robocopy exit 1` (= sucesso) como falso FALHA.
3. Auto-eject validado no caminho de falha: com VS Code aberto em `F:\WorkspaceSync`,
   a ejeção não conclui e o script avisa corretamente (fechar o VS Code do F: antes
   do export de fim de dia, ou usar `wse -NoEject`).

## Adendo 2 (12/08, vivobook) — auto-eject NUNCA funcionou; causa raiz e correção

O `wse` de hoje no nt2 terminou "SEM FALHAS" mas a ejeção "não concluiu". Diagnóstico
no vivobook mostrou que **não era handle preso**: o mecanismo era um no-op.

- **Causa raiz:** o SSD é UASP e enumera como `SCSI\DISK...` (disco **Fixo**). Para
  disco Fixo o Shell **não expõe o verbo Eject** (verificado: a lista `Verbs()` do F:
  não tem "Ejetar" — mesma razão pela qual a bandeja "Remover hardware" não lista o
  SSD, já anotada na seção 2). `InvokeVerb('Eject')` com verbo inexistente não dá
  erro: não faz nada. Agravante latente: `InvokeVerb` compara nome **localizado**
  ("Ejetar" em pt-BR), então nem em drive removível o literal `'Eject'` funcionaria.
  O aviso "algo segura o F:" era falso — o `Test-Path` pós-eject sempre acusa volume
  montado porque a ejeção nunca é tentada. A "validação" do adendo item 3 só validou
  o branch do aviso (que disparava sempre).
- **Correção (feita no `export.ps1`):** ejeção via API `CM_Request_Device_EjectW`
  (cfgmgr32, P/Invoke — a mesma via do RemoveDrive): flush + desmonta + remove o
  devnode; ao reconectar o cabo remonta sozinho. O script localiza o devnode do disco
  pelo `PNPDeviceID` e, se o nó não for ejetável (UASP: o nó removível é o pai
  `USB\VID_0781&PID_55BB`), sobe até 3 pais. Veto real (handle aberto) agora é
  reportado com o **nome de quem segura** (`vetoName`). Também faz
  `Set-Location C:\` antes, para o próprio processo não segurar CWD no F:.
  Cadeia validada no vivobook: `SCSI\DISK` → `USB\VID_0781&PID_55BB` (SanDisk) → hubs.
- **"Remoção rápida" ATIVADA no vivobook** via registro (elevado):
  `HKLM\SYSTEM\CurrentControlSet\Enum\SCSI\DISK&VEN_SANDISK&PROD_PORTABLE_SSD\<inst>\Device Parameters\Partmgr`
  → `UserRemovalPolicy=3` (ExpectSurpriseRemoval). **Vale a partir da próxima
  reconexão do HD.** Desliga o cache de escrita → puxar o cabo vira operação segura
  mesmo sem ejetar; o eject passa a ser cinto-e-suspensório.
- **Pendente:** ativar "Remoção rápida" no **nt2** (mesmo registro — o `<inst>` do
  devnode pode diferir lá; ou `devmgmt.msc` → SanDisk → Diretivas → Remoção rápida).
- **Atenção no próximo `wse`:** a ejeção agora é real — se VS Code/terminal/sessão do
  Claude estiver com CWD no F:, ela será **vetada com nome do processo**. Fechar antes
  ou usar `wse -NoEject`.

## Adendo 3 (13/08, nt2) — erro do auto-eject no vivobook: causa e fix definitivo

O `wse` de 12/08 no vivobook terminou SEM FALHAS mas o auto-eject deu mensagem de
erro (qual, não se sabe — o desfecho não ia para o log). Diagnóstico no nt2:

- **Sem dano:** `fsutil dirty query F:` limpo, volume Healthy, `wsi` de 13/08 normal,
  sem `.needs-chkdsk`. Com a Remoção rápida ativa, o eject é cinto-e-suspensório.
- **Bug real (não transitório):** o loop tentava `CM_Request_Device_EjectW` primeiro
  no nó do **disco** (`SCSI\DISK...`, caps 0xE0 — sem EJECTSUPPORTED/REMOVABLE, ou
  seja, não-ejetável) e fazia `break` em **qualquer** `vetoType != 0`. Um veto
  "ilegal" nessa primeira chamada abortava o loop **antes de subir ao nó pai USB**
  (`USB\VID_0781&PID_55BB`, UAS — REMOVABLE, o ejetável de verdade), reportando
  "Ejecao VETADA" falso.
- **Fix (export.ps1, seção 5):** ① o devnode ejetável agora é escolhido ANTES, por
  capability (`CM_DRP_CAPABILITIES` 0x10, primeiro ancestral com REMOVABLE 0x4 ou
  EJECTSUPPORTED 0x2); ② veto só é terminal quando vem com `vetoName` (processo
  segurando o F:) — sem nome, 1 retry após 1s; ③ o desfecho é gravado no log do
  export: `EJECT: ok (<devnode>)` / `vetada tipo=N por=<processo>` / `rc=N` /
  `exception: ...` — dúvida futura se resolve lendo `logs\export_*.log`.
- **Validado no nt2 (13/08):** teste isolado ejetou pelo nó USB
  (`EJECT: ok (USB\VID_0781&PID_55BB\...)`), F: desmontou; após replug do cabo o
  disco remontou sozinho e o dirty bit continuou limpo (volume Healthy).
  ⚠️ Pós-eject o devnode fica `CM_PROB_HELD_FOR_EJECT`: rescan (`pnputil
  /scan-devices` ou `CM_Reenumerate_DevNode`) NÃO remonta — e exige admin de
  qualquer forma. Voltar sem replug físico só com `Enable-PnpDevice` elevado;
  na prática, **reconectar o cabo é o caminho normal**.
- **RemovalPolicy=3 já ativa no nt2** (diagnóstico da cadeia mostrou policy 3 no nó
  do disco) — a pendência do Adendo 2 estava fechada sem sabermos; nada a fazer.
