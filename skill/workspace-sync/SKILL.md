---
name: workspace-sync
description: Gerencia a sincronização e backup do workspace entre os notebooks Trabalho e Casa via HD externo Data (F:). Use quando o usuário pedir para "exportar o workspace", "importar o workspace", "sincronizar com o HD", "rodar o export", "rodar o import", "fazer backup do workspace", "snapshot do workspace", "levar o trabalho para casa", "trazer o trabalho de casa", "preparar o HD" ou qualquer variante de sincronização/backup entre os dois notebooks.
---

# Workspace Sync — HD externo Data (F:)

Você gerencia o processo de sincronização sem nuvem entre o notebook Trabalho e o notebook Casa. O HD `Data (F:)` é o canal único. **Regra de ouro: o HD sempre carrega o estado mais recente.** Documentação completa: `F:\WorkspaceSync\LEIA-ME.md`.

## Antes de qualquer ação

1. Confirme que o HD está conectado e montado como F:
   ```powershell
   Get-Volume -DriveLetter F
   ```
   Se não estiver, peça ao usuário para conectar (e desbloquear, se BitLocker). Se montou com outra letra, oriente a trocar para F: no Gerenciamento de Disco — os scripts e o remote git `hd` dependem de `F:`.
2. Identifique a intenção: **EXPORT** (terminou de trabalhar aqui → manda para o HD) ou **IMPORT** (vai começar a trabalhar aqui → traz do HD).

## EXPORT (fim do trabalho nesta máquina)

1. Verifique trabalho não commitado no inner-guru:
   ```powershell
   git -C C:\Dev\inner-guru status --porcelain
   ```
   Se houver saída, **avise o usuário e ofereça commitar antes** (mudanças não commitadas NÃO viajam pelo git). Só prossiga sem commit se o usuário aceitar explicitamente.
2. Rode:
   ```powershell
   powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\export.ps1
   ```
3. **Snapshot mensal:** verifique se já existe snapshot do mês corrente em `F:\WorkspaceSync\snapshots\` (pastas `AAAA-MM-DD`). Se não houver, rode com `-Snapshot` em vez do comando acima.
4. Confirme na saída a linha `EXPORT CONCLUIDO SEM FALHAS`. Se houver falhas, mostre quais e o caminho do log — não declare sucesso.

## IMPORT (início do trabalho nesta máquina)

1. Avise: arquivos abertos podem causar falha — ideal fechar Docker e outras janelas do Claude antes.
2. Verifique trabalho local não commitado no inner-guru (mesmo comando acima). Se houver, **PARE e avise**: o usuário precisa decidir (commit local, ou aceitar que o script pulará o pull do git).
3. Rode:
   ```powershell
   powershell -ExecutionPolicy Bypass -File F:\WorkspaceSync\import.ps1
   ```
4. Confirme `IMPORT CONCLUIDO SEM FALHAS`. O script já faz cópia de segurança pré-import em `snapshots\pre-import_*`.
5. Se `package.json`/`package-lock.json` mudaram desde o último import, lembre de `npm install` em `C:\Dev\inner-guru\apps\frontend` e `C:\Dev\inner-guru-design-system`.

## Pontos de atenção

- **Nunca** rode export e import na mesma sessão sem o usuário pedir — um desfaz o efeito do outro.
- Se o usuário relatar que "arquivos sumiram", a causa provável é import sem export prévio na outra máquina — os `pre-import_*` em `snapshots\` são a recuperação.
- Os scripts vivem em `F:\WorkspaceSync` e são versionados no GitHub (`dpfrenatorms/workspace-sync`). Se editar um script, faça commit e push de dentro de `F:\WorkspaceSync`.
- O HD carrega segredos (.env, wallet) — se o usuário mencionar perda/troca do HD, oriente a rotacionar as chaves expostas.
- Ao final, sempre apresente um resumo curto: o que foi sincronizado, falhas/avisos, e (no export) se o trabalho está commitado.
