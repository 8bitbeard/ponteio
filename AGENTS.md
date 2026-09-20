# AGENTS.md

## Fonte da verdade: GitHub Issues + Project Board

Este repositório (`8bitbeard/ponteio`) possui um **board de projeto no GitHub**. O board e as issues do repositório são a **única fonte da verdade** sobre o que precisa ser trabalhado.

Regras obrigatórias:

- **Toda atividade de trabalho vem do board.** Antes de iniciar qualquer tarefa, verifique as issues abertas no repositório (ou no board) — não trabalhe em algo que não esteja registrado lá.
- **Toda nova atividade precisa virar uma issue no repositório e entrar no board.** Nenhum trabalho deve ser conduzido "informalmente" sem um item correspondente rastreável no GitHub.
- **Toda edição de escopo, status ou detalhes de uma atividade deve ser feita na issue correspondente**, não apenas em conversas ou arquivos locais.
- **Arquivos markdown locais (em `docs/`, por exemplo) podem ser usados como rascunho de planos** (PRDs, SDDs, RFCs, notas de design, etc.) durante a fase de definição.
- **Assim que um plano estiver definido**, as atividades derivadas dele devem ser criadas como issues no repositório e adicionadas ao board — os arquivos locais não substituem o rastreamento oficial.

## Fluxo de trabalho esperado

1. Definir/discutir o plano (pode gerar markdown local em `docs/`).
2. Quando o escopo estiver claro, criar as issues correspondentes no repositório via `gh issue create` (ou UI do GitHub).
3. Adicionar as issues ao project board.
4. Trabalhar a partir das issues — qualquer mudança de plano ou escopo deve ser refletida de volta na issue (comentário, edição de descrição, labels, status no board).
5. Fechar/mover a issue no board conforme o trabalho avança.

## Para agentes de IA trabalhando neste repositório

- Antes de começar a implementar algo, confira se existe uma issue aberta cobrindo o trabalho. Se não existir, crie a issue (e adicione ao board) antes de prosseguir, ou pergunte ao usuário se deseja que isso seja feito.
- Não considere uma tarefa "planejada" apenas por existir um markdown em `docs/` — o plano só é oficial quando as issues correspondentes existem no repositório.
- Ao concluir trabalho relacionado a uma issue, atualize a issue (comentário e/ou status) em vez de apenas relatar o resultado no chat.
- Para implementar uma issue de ponta a ponta (branch, código, PR), use a skill `/implement-issue` (veja `.claude/skills/implement-issue/SKILL.md`).

## Git Flow

O projeto segue um Git Flow simplificado, com três tipos de branch:

- **`main`** — código em produção. Reflete sempre a última release publicada.
- **`develop`** — branch de integração. Recebe as features já concluídas antes de irem para produção.
- **`feature/<nome-da-demanda>`** — uma branch por atividade/issue implementada (ex.: `feature/login-com-google`, nome derivado do título da issue em kebab-case). Criada sempre a partir de `develop`.

Regras:

- Nenhuma implementação é feita diretamente em `develop` ou `main`. Toda mudança nasce em uma branch `feature/<nome-da-demanda>`.
- Ao terminar uma feature, abra um PR de `feature/<nome-da-demanda>` para `develop`.
- Quando `develop` estiver estável e pronta para ir a produção, abra um PR de `develop` para `main`.
- Commits e títulos de PR devem seguir [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `chore:`, `docs:`, etc.) — isso é usado pela automação de release para decidir a versão e montar o changelog.
- O merge de PRs é feito via **squash and merge**, usando o título do PR (em Conventional Commits) como mensagem final do commit.

### Proteção de branches (branch protection)

- **`develop`** só aceita código via PR vindo de branches `feature/*`. Push direto é bloqueado.
- **`main`** só aceita código via PR vindo da branch `develop` (ou do PR automático de release do `release-please`). Push direto é bloqueado.
- A validação de que o PR vem da branch de origem correta é feita pelo workflow `.github/workflows/branch-source-guard.yml`, cujo status check é obrigatório (`required status check`) em ambas as branches.
- Aprovação de outra pessoa não é exigida (projeto solo) — mas o PR precisa existir e passar no status check.

### Release automática

- Todo merge na `main` dispara o workflow `.github/workflows/release-please.yml` ([release-please](https://github.com/googleapis/release-please)).
- O `release-please` lê os commits desde a última release, decide a versão semântica (major/minor/patch) a partir dos Conventional Commits, atualiza o `CHANGELOG.md` e, ao mergear o PR de release que ele mesmo abre, cria a tag e a GitHub Release correspondente.
- Configuração em `release-please-config.json` e `.release-please-manifest.json`, na raiz do repositório.
