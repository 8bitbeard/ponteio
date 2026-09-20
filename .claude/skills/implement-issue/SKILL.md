---
name: implement-issue
description: "Implementa uma issue do repositório de ponta a ponta (branch, código, PR) subindo um subagente com contexto zerado. Use quando o usuário disser /implement-issue, 'implementa a issue X', 'pega essa atividade do board e implementa'."
trigger: /implement-issue
---

# /implement-issue

Implementa uma atividade do board de ponta a ponta: lê a issue no GitHub, cria a branch, implementa, e abre o PR — tudo isso rodando em um **subagente novo, com contexto zerado**, para que a implementação não herde suposições da conversa atual e se baseie apenas no que está escrito na issue.

## Uso

```
/implement-issue <numero-da-issue>
/implement-issue <numero-da-issue> --notas "contexto extra relevante que não está na issue"
```

Se o usuário informar uma descrição livre em vez de um número, primeiro localize (ou crie, seguindo o AGENTS.md) a issue correspondente no repositório antes de prosseguir — o subagente sempre deve trabalhar a partir de uma issue existente no GitHub, nunca de uma descrição solta.

## O que este comando faz

1. **Resolve a issue**: se o usuário passou um número, use-o diretamente. Se passou uma descrição, rode `gh issue list` / `gh issue view` para encontrar a issue correspondente; se não existir, siga o AGENTS.md e crie a issue antes de continuar (pergunte ao usuário se não estiver claro).

2. **Sobe um subagente novo** (Agent tool, `subagent_type: "general-purpose"`, **sem** usar `fork` — o objetivo é justamente que ele comece com contexto zerado) com um prompt autocontido contendo:
   - O número da issue e o repositório (`8bitbeard/ponteio`).
   - A instrução explícita de ler a issue completa via `gh issue view <numero> --comments` antes de fazer qualquer coisa, e tratar o corpo da issue como a especificação da tarefa.
   - As regras de Git Flow do `AGENTS.md` (branch `feature/<nome-da-demanda>` a partir de `develop`, commits em Conventional Commits, PR via squash).
   - A instrução de implementar a atividade, escrever/rodar os testes pertinentes, e validar a implementação antes de abrir o PR.
   - A instrução de abrir o PR com `gh pr create` (ver formato abaixo).
   - Qualquer nota extra passada via `--notas`.

3. **Prompt do subagente** (adapte o número/branch antes de disparar):

   ```
   Você vai implementar a issue #<numero> do repositório 8bitbeard/ponteio.
   Contexto: nenhum além do que está escrito aqui e no repositório — leia
   `AGENTS.md` primeiro para entender o processo do projeto (Git Flow,
   proteção de branches, convenção de commits).

   Passos:
   1. Rode `gh issue view <numero> --comments` e trate o corpo/comentários
      como a especificação completa da tarefa. Se algo estiver ambíguo,
      pare e reporte a ambiguidade em vez de assumir.
   2. Garanta que está com `develop` atualizada
      (`git fetch origin && git checkout develop && git pull`).
   3. Crie a branch `feature/<nome-da-demanda>` a partir de `develop`
      (nome em kebab-case derivado do título da issue).
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
   8. Comente na issue original um resumo curto do que foi feito e o link do PR.

   Regras:
   - Nunca implemente direto em `develop` ou `main`.
   - Nunca abra PR direto para `main` — o destino é sempre `develop`.
   - Se a issue já estiver com uma branch/PR em andamento, avise em vez de duplicar.
   ```

4. Depois que o subagente terminar, resuma para o usuário: branch criada, link do PR, e o que ficou pendente (se algo não pôde ser validado, diga isso explicitamente).

## Observações

- Este comando **não** faz merge do PR — merge fica a critério do usuário (ou de outra automação), respeitando a proteção de branches descrita no `AGENTS.md`.
- Se `develop` não existir ou estiver com conflitos com `main`, avise o usuário em vez de tentar resolver sozinho.
