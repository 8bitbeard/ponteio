---
name: implement-issue
description: "Implementa uma issue do repositório de ponta a ponta (branch, código, PR) subindo um subagente com contexto zerado. Use quando o usuário disser /implement-issue, 'implementa a issue X', 'pega essa atividade do board e implementa'."
trigger: /implement-issue
---

# /implement-issue

Implementa uma atividade do board de ponta a ponta: lê a issue no GitHub, cria a branch, implementa, e abre o PR — tudo isso rodando em um **subagente novo, com contexto zerado**, para que a implementação não herde suposições da conversa atual e se baseie apenas no que está escrito na issue.

## Uso

```
/implement-issue
/implement-issue <numero-da-issue>
/implement-issue <numero-da-issue> --notas "contexto extra relevante que não está na issue"
```

Se o usuário informar uma descrição livre em vez de um número, primeiro localize (ou crie, seguindo o AGENTS.md) a issue correspondente no repositório antes de prosseguir — o subagente sempre deve trabalhar a partir de uma issue existente no GitHub, nunca de uma descrição solta.

Se o comando for chamado **sem nenhum argumento**, resolva a issue automaticamente a partir do project board (veja "Resolver a próxima issue do backlog" abaixo) em vez de perguntar ao usuário qual issue implementar.

## O que este comando faz

1. **Resolve a issue**:
   - Se o usuário passou um número, use-o diretamente.
   - Se passou uma descrição, rode `gh issue list` / `gh issue view` para encontrar a issue correspondente; se não existir, siga o AGENTS.md e crie a issue antes de continuar (pergunte ao usuário se não estiver claro).
   - Se **nenhum argumento** foi passado, resolva a "próxima issue do backlog" direto no project board:
     1. Descubra o número do project e o `project-id`: `gh project list --owner 8bitbeard --format json` (há um único project, "Ponteio APP").
     2. Liste os itens do board: `gh project item-list <numero-do-project> --owner 8bitbeard --format json --limit 100`. Cada item traz `content.number` (issue), `status` (coluna do board) e a ordem reflete a posição no board.
     3. **Não confie cegamente no campo `status` do board** — ele pode estar desatualizado em relação ao estado real da issue (ex.: issue já implementada e mergeada em `develop`, mas ainda aberta no GitHub porque o PR mirou `develop`, não a branch default `main`, e `Closes #N` só fecha automaticamente ao mergear na branch default). Para cada candidato, confirme o estado real com `gh issue view <numero> --json state`.
        - Se encontrar um item com card em "In progress"/"In review"/"Done" cuja issue já está `CLOSED`, mas o card não está em "Done": corrija o card (mova para "Done") antes de continuar — use o mesmo mecanismo descrito em "Atualizar o card no board" abaixo, com a option `Done`.
        - Se encontrar um item com issue `CLOSED` mas o card ainda em "Backlog"/"Ready"/"In progress"/"In review": mova o card para "Done" e pule para o próximo candidato.
     4. Escolha o primeiro item, na ordem do board, cuja issue esteja `OPEN` **e** cujo card esteja em "Ready" (prioridade) ou "Backlog". Essa é a "próxima issue do backlog".
     5. Informe ao usuário qual issue foi escolhida (número + título) antes de prosseguir.

2. **Sobe um subagente novo** (Agent tool, `subagent_type: "general-purpose"`, **sem** usar `fork` — o objetivo é justamente que ele comece com contexto zerado) com um prompt autocontido contendo:
   - O número da issue e o repositório (`8bitbeard/ponteio`).
   - A instrução explícita de ler a issue completa via `gh issue view <numero> --comments` antes de fazer qualquer coisa, e tratar o corpo da issue como a especificação da tarefa.
   - As regras de Git Flow do `AGENTS.md` (branch `feature/<nome-da-demanda>` a partir de `develop`, commits em Conventional Commits, PR via squash).
   - A instrução de atualizar o card do board para "In progress" assim que a branch for criada, e para "In review" assim que o PR for aberto (ver "Atualizar o card no board" abaixo).
   - A instrução de implementar a atividade, escrever/rodar os testes pertinentes, e validar a implementação antes de abrir o PR.
   - A instrução de abrir o PR com `gh pr create` (ver formato abaixo).
   - Qualquer nota extra passada via `--notas`.

3. **Prompt do subagente** (adapte o número/branch antes de disparar):

   ````
   Você vai implementar a issue #<numero> do repositório 8bitbeard/ponteio.
   Contexto: nenhum além do que está escrito aqui e no repositório — leia
   `AGENTS.md` primeiro para entender o processo do projeto (Git Flow,
   proteção de branches, convenção de commits).

   Passos:
   1. Rode `gh issue view <numero> --comments` e trate o corpo/comentários
      como a especificação completa da tarefa. Se a issue citar `PRD §X` /
      `SDD §Y`, leia `docs/PRD-plataforma-tablaturas.md` e
      `docs/SDD-plataforma-tablaturas.md` no repositório — essas referências
      não são decorativas, são a especificação normativa. Para telas de
      `tabs` (Minhas tablaturas, Editor, Estudo), leia também
      `docs/mockup-telas.html` (mockup estático de referência visual). Se
      algo continuar ambíguo mesmo após ler esses documentos, pare e reporte
      a ambiguidade em vez de assumir.
   2. Garanta que está com `develop` atualizada
      (`git fetch origin && git checkout develop && git pull`).
   3. Crie a branch `feature/<nome-da-demanda>` a partir de `develop`
      (nome em kebab-case derivado do título da issue).
   3.1. Mova o card da issue no board para **"In progress"** (veja
      "Atualizar o card no board" abaixo). O trabalho está começando —
      o board deve refletir isso imediatamente.
   4. Implemente a atividade descrita na issue.
   5. Valide a implementação (rode a suíte de testes existente e/ou
      teste manual pertinente ao tipo de mudança). Não abra o PR sem
      validar.
   6. Faça commit(s) seguindo Conventional Commits e dê push na branch.
   7. Abra o PR com `gh pr create --base develop --head feature/<nome-da-demanda>`,
      com:
      - Título em Conventional Commits.
      - Corpo contendo obrigatoriamente estas seções:
        ## O que foi feito
        <resumo objetivo da implementação>

        ## Como foi validado
        <testes/comandos rodados e resultado, ou passos de validação manual>

        Closes #<numero>
   7.1. Mova o card da issue no board para **"In review"** (mesmo
      mecanismo). O PR está aberto e pronto para revisão/merge — não
      marque como "Done" aqui, pois este comando não faz merge.
   8. Comente na issue original um resumo curto do que foi feito e o link do PR.

   Regras:
   - Nunca implemente direto em `develop` ou `main`.
   - Nunca abra PR direto para `main` — o destino é sempre `develop`.
   - Se a issue já estiver com uma branch/PR em andamento, avise em vez de duplicar.
   - Não use `gh issue close`: quem decide fechar a issue é quem faz o merge do PR (ver
     "Observações" abaixo sobre o `Closes #N` não fechar automaticamente).

   ### Atualizar o card no board

   O project board é `8bitbeard/ponteio` → project "Ponteio APP" (owner `8bitbeard`).
   Resolva os IDs dinamicamente a cada execução (não assuma que são estáveis entre
   projetos/boards recriados):

   ```bash
   OWNER=8bitbeard
   PROJECT_NUMBER=$(gh project list --owner $OWNER --format json | jq -r '.projects[] | select(.title=="Ponteio APP") | .number')
   PROJECT_ID=$(gh project list --owner $OWNER --format json | jq -r '.projects[] | select(.title=="Ponteio APP") | .id')
   FIELD_ID=$(gh project field-list $PROJECT_NUMBER --owner $OWNER --format json | jq -r '.fields[] | select(.name=="Status") | .id')
   OPTION_ID=$(gh project field-list $PROJECT_NUMBER --owner $OWNER --format json | jq -r --arg opt "In progress" '.fields[] | select(.name=="Status") | .options[] | select(.name==$opt) | .id')
   ITEM_ID=$(gh project item-list $PROJECT_NUMBER --owner $OWNER --format json --limit 100 | jq -r --argjson n <numero> '.items[] | select(.content.number==$n) | .id')

   gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID"
   ```

   Troque `"In progress"` por `"In review"` (ou `"Done"`) no `--arg opt` conforme o
   momento. Se `jq` não estiver disponível, adapte para `python3 -c "..."` como
   alternativa.
   ````

4. Depois que o subagente terminar, resuma para o usuário: branch criada, link do PR, status atual do card no board, e o que ficou pendente (se algo não pôde ser validado, diga isso explicitamente).

## Observações

- Este comando **não** faz merge do PR — merge fica a critério do usuário (ou de outra automação), respeitando a proteção de branches descrita no `AGENTS.md`.
- Se `develop` não existir ou estiver com conflitos com `main`, avise o usuário em vez de tentar resolver sozinho.
- **`Closes #N` no corpo do PR não fecha a issue automaticamente**: como os PRs de feature miram `develop` (não a branch default `main`), o fechamento automático do GitHub não dispara ao mergear. Isso é coberto pelo workflow `.github/workflows/close-issue-on-merge.yml`: ao mergear o PR na `develop`, ele lê o `Closes #N` do corpo do PR, fecha a issue e move o card para "Done" automaticamente (depende do secret `PROJECT_TOKEN`, um PAT com escopos `repo`+`project`). Isso não é responsabilidade deste comando (que não faz merge). Se o secret não estiver configurado ou o workflow falhar, a issue/card ficam defasados; ao rodar `/implement-issue` sem argumento, o passo de resolução do próximo item do backlog corrige inconsistências desse tipo que encontrar pelo caminho (ver acima).
