# Memória de Sessão — Sincronização IMPORT no Notebook 2

- **Data:** 2026-06-15
- **Máquina:** Notebook 2 — `DESKTOP-CQRID29`
- **Operação:** IMPORT (HD `Data (F:)` → Notebook 2), via skill `workspace-sync`
- **Resultado:** Import concluído + dois MCP servers (gmail/defi) reativados. mem0 pendente.

## O que foi feito

1. **Checagens de segurança:** HD `F:` montado (~572 GB livres). `git status` do inner-guru acusou pasta inexistente (sem trabalho local a perder).
2. **Import (`import.ps1`):** backup pré-import salvo em `F:\WorkspaceSync\snapshots\pre-import_DESKTOP-CQRID29_2026-06-15_2346`. Espelhos copiados OK: `C:\Workspace`, `C:\Dev\inner-guru-design-system`, `C:\Users\dpfre\.claude`, `...\claude-instagram`, `...\plugins`.
3. **inner-guru:** clonado do repo bare do HD + checkout manual do `main`. Working tree limpo e populado.
4. **Dependências:** `npm install` em `apps\frontend` (584 pkgs) e em `inner-guru-design-system` (626 pkgs).
5. **Python:** instalado 3.14.6 (não havia Python real, só o stub da Store).
6. **MCP servers gmail_mcp + defi_mcp:** deps pip instaladas, `command` corrigido para o Python local, config mesclada.

## Descobertas importantes (ler antes da próxima sessão)

1. **Claude Desktop é versão Microsoft Store (empacotada).** A config NÃO fica em `%APPDATA%\Claude`. Caminho real:
   `C:\Users\dpfre\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json`
2. **Dubious ownership do Git no HD.** Repos do HD foram criados por outra máquina (SID diferente); o Git recusa até autorizar. Fix:
   `git config --global --add safe.directory '<caminho-do-repo>'` — aplicado a `F:\WorkspaceSync\git-remotes\inner-guru.git` (e vale também para `F:\WorkspaceSync`).
3. **Clone sem checkout.** Após o clone aparece `warning: remote HEAD refers to nonexistent ref`; a pasta fica vazia. Resolver com `git -C C:\Dev\inner-guru checkout -b main hd/main`.
4. **`import.ps1` mente no resultado.** Ele imprime `IMPORT CONCLUIDO SEM FALHAS` mesmo quando o clone do git falha. NÃO confiar nessa linha — verificar o repo de verdade (`git log`, `Get-ChildItem -Force`).
5. **Caminhos de Python na config virtualizada apontam para o Notebook 1** (`C:\Python314\...` e `...\AppData\Local\Python\...`), que não existem aqui. Ao replicar MCP servers, corrigir o `command` para o Python local:
   `C:\Users\dpfre\AppData\Local\Programs\Python\Python314\python.exe`
6. **Config virtualizada do HD está incompleta:** só contém `gmail_mcp` e `defi_mcp`. NÃO contém `mem0` (mesmo ele existindo no Notebook 1) — sinal de export desatualizado.

## Pendências

- [ ] **Reiniciar o Claude Desktop** no Notebook 2 para carregar gmail_mcp/defi_mcp e confirmar conexão.
- [ ] **Replicar o mem0** (instalado no Notebook 1): pegar a entrada do `claude_desktop_config.json` do Notebook 1, identificar se é hospedado (type/url) ou self-hosted (command/args), replicar deps/arquivos e mesclar na config daqui.
- [ ] **EXPORT atualizado no Notebook 1** para o HD passar a carregar o mem0 e o estado mais recente.
- [ ] Verificar Docker no Notebook 2: `docker --version` / `docker compose version`.

## Referências de caminhos

- Config Claude (local): `C:\Users\dpfre\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude_desktop_config.json`
- Config virtualizada (HD): `F:\WorkspaceSync\mirror\configs\claude_desktop_config.virtualizado.json`
- Python local: `C:\Users\dpfre\AppData\Local\Programs\Python\Python314\python.exe`
- gmail-mcp: `C:\Workspace\Claude Code\.claude\gmail-mcp\server.py`
- defi_mcp: `C:\Workspace\Cowork\DEFI\defi_mcp\server.py`