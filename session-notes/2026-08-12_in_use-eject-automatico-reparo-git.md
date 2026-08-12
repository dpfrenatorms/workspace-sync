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

- [ ] Rodar `wsi` uma vez → chkdsk F: /f /x automático (UAC) + import de verificação limpo.
- [ ] Ativar "Remoção rápida" nos DOIS notebooks (nt2 e vivobook).
- [ ] `git push` deste commit para o GitHub (proteção contra a próxima corrupção do HD).
- [ ] Confirmar um ciclo `wse` → `wsi` sem falhas e sem novo `Ntfs 55` no event log.
