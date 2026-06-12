# WorkspaceSync — sincronização notebook Trabalho ⇄ notebook Casa

HD `Data (F:)` é o canal único de sincronização e backup (política sem nuvem).
**Regra de ouro: o HD sempre carrega o estado mais recente.**

## Fluxo

| Momento | Comando |
|---|---|
| Terminou de trabalhar | `powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\export.ps1` |
| Vai começar na outra máquina | `powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\import.ps1` |
| 1x por mês (backup congelado) | `export.ps1 -Snapshot` (retém os 3 últimos) |

Nunca edite a mesma pasta nas duas máquinas sem passar pelo HD no meio.
Para o `inner-guru` (git), trabalho inacabado deve virar **commit** antes do export — mudanças não commitadas não viajam.

## O que é sincronizado

- `C:\Dev\inner-guru` — via **git** (repo bare em `git-remotes\inner-guru.git`, remote `hd`)
- `C:\Workspace` (Cowork, Claude Code, Projetos) — espelho
- `C:\Dev\inner-guru-design-system` — espelho (sem node_modules/.next)
- `C:\Users\dpfre\.claude` — rules, skills, scheduled-tasks, settings + memória dos projetos (sem histórico de sessões)
- `C:\Users\dpfre\claude-instagram` — scripts + .env
- `C:\Users\dpfre\plugins` — plugin contador-irpf-2026
- Config virtualizado do Claude Desktop (referência em `mirror\configs\`)

## Setup do notebook 2 — Casa (uma vez)

1. Usuário Windows **dpfre** (obrigatório — caminhos absolutos).
2. **NÃO ativar OneDrive** (política sem nuvem).
3. Instalar: git, Node LTS, Python 3.14 em `C:\Python314`, Docker Desktop, VS Code, Claude Code, Claude Desktop (Store).
4. Rodar `import.ps1`.
5. `npm install` em `C:\Dev\inner-guru\apps\frontend` e em `C:\Dev\inner-guru-design-system`.
6. Abrir Claude Desktop → Configurações → Desenvolvedor → conferir gmail_mcp e defi_mcp.
7. Identidade git: `git -C C:\Dev\inner-guru config user.name "Renato Menezes Santana"` e `...config user.email "dpf.renato.rms@gmail.com"`.

## Segurança

- O espelho contém **segredos** (.env com chaves de API, wallet). Mantenha o **BitLocker To Go ativado** neste HD (Painel de Controle → BitLocker → Data F:).
- Apps fechados durante export/import: Claude Desktop (segura os MCP python) e Docker.

## Estrutura

```
F:\WorkspaceSync\
├── export.ps1 / import.ps1 / LEIA-ME.md
├── git-remotes\inner-guru.git
├── mirror\            ← estado mais recente (vivo)
├── snapshots\         ← AAAA-MM-DD congelados (3) + pre-import_* (2 por máquina)
└── logs\              ← logs de cada export/import
```
