# Memória de Sessão — Correção DEFINITIVA da retenção de snapshots (workspace-sync)

- **Data:** 2026-08-11
- **Máquina:** `DESKTOP-CQRID29` (HD `Data` montado em `F:`)
- **Escopo:** Bug recorrente de retenção de snapshots no `import.ps1` / `export.ps1` — resolvido de vez.
- **Regra de ouro do fluxo:** o HD sempre carrega o estado mais recente; a letra do drive **precisa ser `F:`**.

## O problema (reincidia em TODA import/export)

A retenção de snapshots falhava sempre, com a mensagem:
`AVISO: Snapshot antigo NAO removido por completo (possivel corrupcao de FS - rode chkdsk F: /f)`.
Persistiu **mesmo depois de trocar a mídia física** — logo, não era o HD.

## Causa raiz (confirmada)

Os snapshots pré-import guardam cópias de `C:\Workspace`, `.claude` etc., que contêm vários repositórios `.git`. O git marca os objetos em `.git\objects\` como **somente-leitura**. A antiga `Remove-TreeRobust`:

1. tentava limpar o read-only via `$_.Attributes`, mas essa API **falha em caminhos > 260 caracteres** (e os `.git` ficam em subpastas muito profundas); e
2. apagava com `[System.IO.File]::Delete()`, que **se recusa a apagar arquivo read-only** — mesmo com o prefixo `\\?\`.

Resultado: nos arquivos que eram read-only **e** de caminho longo (objetos `.git`), nada era apagado → a exclusão da árvore travava → retenção falhava.

## A correção definitiva

`Remove-TreeRobust` reescrita nos DOIS scripts (`import.ps1` e `export.ps1`) para:

1. `cmd /c rmdir /s /q "$Path"` (rápido; já remove somente-leitura); e se sobrar algo,
2. **fallback com robocopy espelhando uma pasta vazia** — `robocopy <vazia> "$Path" /MIR` — que lida nativamente com caminhos > 260 chars E apaga arquivos read-only; depois `rmdir` na pasta já vazia.

Esse é o padrão robusto de zerar árvore no Windows. A partir do próximo import/export a retenção se limpa sozinha.

## Replicação no ntb1 (VIVOBOOK_PRO_15) — automática

**Não precisa instalar nada no vivobook.** Os scripts moram no HD (`F:\WorkspaceSync\import.ps1` / `export.ps1`) e as duas máquinas rodam direto de lá — o vivobook já usa a versão corrigida assim que rodar do `F:`. Requisitos por máquina:

- O HD **precisa montar como `F:`** (Gerenciamento de Disco → Alterar letra). O remote git `hd` do `C:\Dev\inner-guru` aponta para `F:\...` nas duas máquinas.
- Os snapshots antigos do vivobook são limpos pela retenção corrigida no próximo import/export lá — ou pela rotina de limpeza abaixo (que já cobre as duas máquinas, pois todos os snapshots ficam no mesmo HD).

## Rotina de limpeza pontual do acúmulo (roda de qualquer máquina)

Mantém os 2 snapshots mais recentes de cada máquina e remove o resto, com o método robusto:

```powershell
function Nuke($Path){
  if(-not(Test-Path -LiteralPath $Path)){return}
  $e=Join-Path $env:TEMP ('_wsempty_'+[System.IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Force $e | Out-Null
  robocopy $e "$Path" /MIR /R:0 /W:0 /MT:32 /NFL /NDL /NP /NJH /NJS | Out-Null
  Remove-Item -LiteralPath $Path -Recurse -Force -EA SilentlyContinue
  Remove-Item -LiteralPath $e -Recurse -Force -EA SilentlyContinue
}
Get-ChildItem 'F:\WorkspaceSync\snapshots' -Directory -Filter 'pre-import_*' |
  Group-Object { ($_.Name -split '_\d{4}-\d{2}-\d{2}_')[0] } |
  ForEach-Object { $_.Group | Sort-Object Name -Descending | Select-Object -Skip 2 |
    ForEach-Object { Nuke $_.FullName;
      if(Test-Path -LiteralPath $_.FullName){"AINDA: $($_.Name)"}else{"removido: $($_.Name)"} } }
```

## Outras correções feitas nesta série de sessões

1. **Corrupção de FS do HD** (causava `robocopy exit 16` em tudo): reparada com `chkdsk F: /f`. Sem setores defeituosos — era corrupção de metadados NTFS (provável remoção sem "ejetar com segurança"). **Sempre ejetar com segurança.**
2. **Troca de mídia caiu em `D:`**: remontado como `F:` no Gerenciamento de Disco (o fluxo inteiro depende de `F:`).
3. **Objeto git corrompido** no próprio repo workspace-sync: `.git/objects/01/b19a64…` estava zerado (0 byte). Restaurado do GitHub (`dpfrenatorms/workspace-sync`) com hash idêntico; `git fsck --full` limpo.

## Export/Import com `robocopy exit 11` — causas reais e correção

O `exit 11` em `C:\Workspace` e `C:\Users\dpfre\.claude` **NÃO era "arquivo em uso"** (essa foi uma hipótese inicial errada). Lendo o log (`export_2026-08-11_1252.log`), são dois erros distintos, ambos no lado do espelho no HD:

1. **ERRO 5 (Acesso negado)** em `mirror\claude-home\session-env\<uuid>\`. São pastas de **sessão efêmera** do Claude, com ACL restritiva, que nem deviam ser sincronizadas.
   - **Correção (feita):** adicionado `session-env` à exclusão `/XD` do espelho `.claude` **nos dois scripts** (`export.ps1` linha do Mirror do `.claude`; `import.ps1` no alvo `claude-home`, `xd = @('projects','session-env')`). Mata o ERRO 5. A pasta velha `session-env` fica no HD, ignorada.

2. **ERRO 2 (arquivo não encontrado ao excluir)** em `mirror\Workspace\Projetos\mensageria-reiki\automacao-reiki\automacao-reiki\.git\objects\...`. Causa: a pasta **`automacao-reiki` está aninhada duas vezes** (um projeto real dentro de um wrapper de mesmo nome). O caminho longo faz o robocopy falhar ao purgar objetos `.git` antigos. **NÃO é lixo — é projeto ativo.**
   - **Correção (des-aninhar, quando puder — projeto fechado):**
     ```powershell
     $base = 'C:\Workspace\Projetos\mensageria-reiki\automacao-reiki'
     Rename-Item $base "$base-old"
     Move-Item "$base-old\automacao-reiki" $base
     Remove-Item "$base-old" -Recurse -Force
     # limpar a copia duplicada/velha no espelho do HD:
     $m = 'F:\WorkspaceSync\mirror\Workspace\Projetos\mensageria-reiki\automacao-reiki\automacao-reiki'
     $e = "$env:TEMP\_wsempty"; New-Item -ItemType Directory -Force $e | Out-Null
     robocopy $e $m /MIR /R:0 /W:0 /MT:32
     Remove-Item -LiteralPath $m -Recurse -Force -EA SilentlyContinue
     ```
   - `Move-Item` no mesmo disco é renomeação (não mexe no `.git`). Enquanto não des-aninhar, o export funciona e faz backup normal — só reporta o ERRO 2 (inofensivo).

> Nota de método: o robocopy da limpeza usa `/R:0 /W:0 /MT:32` — sem retry (não trava) e multithread (rápido). Com a saída suprimida ele fica minutos calado e **parece congelado, mas está trabalhando**; esperar o resumo aparecer.

## Pendências

- [ ] `git -C F:\WorkspaceSync commit -am "fix: retencao robusta + exclui session-env do espelho .claude"` e `git push` para versionar no GitHub.
- [ ] Des-aninhar o projeto `automacao-reiki` (procedimento acima) para o export sair `SEM FALHAS`.
- [ ] Limpar o backlog de snapshots do vivobook (rodar a rotina de limpeza ou um import/export lá — a retenção corrigida já faz sozinha).
- [ ] Regra permanente: ejetar o HD com segurança e garantir que monte sempre em `F:`.
