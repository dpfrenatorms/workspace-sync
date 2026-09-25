# Prompt — instalar o plugin `andrej-karpathy-skills` no Claude Code

Contexto: `/plugin marketplace add` e `/plugin install` não existem no Claude Code
na nuvem (claude.ai/code). No Claude Code local (Windows, usuário `dpfre`) eles
funcionam, mas só podem ser digitados por você — o Claude não executa slash commands.
O prompt abaixo cobre os dois casos e tem fallback manual.

Upstream verificado em 2026-09-25 (commit `2c60614`):
- marketplace `karpathy-skills` → plugin `andrej-karpathy-skills` v1.0.0 (MIT)
- conteúdo: 1 skill, `skills/karpathy-guidelines/SKILL.md`
  (Think Before Coding · Simplicity First · Surgical Changes · Goal-Driven Execution)

---

## Prompt para colar no Claude Code

```text
Instale o plugin "andrej-karpathy-skills" (marketplace "karpathy-skills",
repo GitHub forrestchang/andrej-karpathy-skills) para o meu usuário, de forma que
a skill "karpathy-guidelines" fique disponível em todos os projetos.

Regras:
- Antes de alterar qualquer arquivo, leia-o e faça backup (<arquivo>.bak).
- Nunca sobrescreva ~/.claude/settings.json inteiro: faça merge das chaves.
- Pare e me pergunte se algo divergir do esperado. Não invente comandos:
  se um comando não existir, diga isso e siga para o próximo caminho.

Caminho 1 — CLI (preferido):
1. Rode `claude plugin --help`. Se os subcomandos existirem, rode:
   claude plugin marketplace add forrestchang/andrej-karpathy-skills
   claude plugin install andrej-karpathy-skills@karpathy-skills
2. Se funcionar, pule para "Verificação".

Caminho 2 — settings.json (se o Caminho 1 não existir/falhar):
1. Em ~/.claude/settings.json (Windows: C:\Users\dpfre\.claude\settings.json),
   faça merge de:
   {
     "extraKnownMarketplaces": {
       "karpathy-skills": {
         "source": { "source": "github", "repo": "forrestchang/andrej-karpathy-skills" }
       }
     },
     "enabledPlugins": {
       "andrej-karpathy-skills@karpathy-skills": true
     }
   }
2. Valide que o JSON continua válido.
3. Me avise que preciso reiniciar o Claude Code (e, se aparecer, aprovar
   o marketplace / a instalação).

Caminho 3 — skill manual (fallback garantido, não depende do sistema de plugins):
1. Baixe:
   https://raw.githubusercontent.com/forrestchang/andrej-karpathy-skills/main/skills/karpathy-guidelines/SKILL.md
2. Salve em ~/.claude/skills/karpathy-guidelines/SKILL.md
   (Windows: C:\Users\dpfre\.claude\skills\karpathy-guidelines\SKILL.md).
3. Confira que o arquivo começa com o frontmatter `name: karpathy-guidelines`.
4. Use este caminho só se 1 e 2 falharem — não instale pelos dois jeitos
   ao mesmo tempo, para não duplicar a skill.

Verificação:
- Mostre qual caminho funcionou e o diff dos arquivos alterados.
- Liste onde a skill ficou instalada e confirme que "karpathy-guidelines"
  aparece entre as skills disponíveis (após reiniciar, se necessário).
- Lembre-me de rodar o export do WorkspaceSync (wse) para levar a mudança
  em C:\Users\dpfre\.claude ao outro notebook.
```

---

## Se preferir fazer à mão no Claude Code local

Digite no prompt do Claude Code (não no terminal):

```text
/plugin marketplace add forrestchang/andrej-karpathy-skills
/plugin install andrej-karpathy-skills@karpathy-skills
```

## Na nuvem (claude.ai/code)

`/plugin` não está disponível. Opções: commitar no repositório do projeto
`.claude/skills/karpathy-guidelines/SKILL.md` (skill de projeto), ou as chaves
`extraKnownMarketplaces`/`enabledPlugins` em `.claude/settings.json` do projeto.
Não verifiquei se a sessão na nuvem instala plugins declarados em
`.claude/settings.json` — a skill de projeto é o caminho mais seguro.
