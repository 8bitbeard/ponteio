# PRD — Plataforma de Aprendizado de Violão via Tablaturas com Sugestão de Acordes

## 1. Visão Geral

Plataforma web para aprendizado de músicas no violão através de tablaturas, cujo diferencial é analisar a tablatura e sugerir, para cada trecho, um acorde de referência que indica ao usuário como posicionar a mão no braço do violão — trazendo para a tablatura a facilidade de posicionamento que hoje só a cifra oferece, sem perder a precisão de notas e cordas que só a tablatura oferece.

## 2. Problema

Ao estudar uma música pela tablatura, o usuário sabe exatamente quais notas tocar, mas não tem indicação de como posicionar a mão esquerda no braço do violão. Tocar nota a nota com um único dedo é tecnicamente inviável para manter melodia e ritmo corretos. A cifra resolve esse problema (mostra o acorde/posição de mão), mas perde a precisão de quais notas e cordas tocar exatamente. Não há hoje uma ferramenta que combine as duas coisas.

## 3. Objetivo do Produto

Permitir que o usuário estude uma tablatura mantendo o foco apenas em **quais cordas tocar e no ritmo**, enquanto a plataforma resolve **como posicionar a mão** através da sugestão automática de acordes de referência para cada trecho da música.

## 4. Persona

Violonista com conhecimento básico/intermediário, que já sabe ler tablatura e reconhece diagramas de acorde, mas tem dificuldade em traduzir uma sequência de notas em posição de mão fluida.

## 5. Fases do Produto

| Fase | Conteúdo |
|---|---|
| **Fase 1 — MVP** (escopo deste PRD) | Autenticação, CRUD de tablaturas próprias, editor de tablatura, motor de sugestão de acordes, visualização de estudo |
| Fase 2 | Compartilhamento de tablaturas (com amigos e com a comunidade) |
| Fase 3 | Reprodução sonora (play) da tablatura, com ritmo, pausas e intensidade — requer fusão de tablatura com informação de partitura |

As fases 2 e 3 estão fora do escopo de implementação deste PRD, mas são consideradas no modelo de domínio para não gerar retrabalho estrutural.

## 6. Escopo da Fase 1 (MVP)

### 6.1 Autenticação e Conta
- Cadastro e login com e-mail/senha.
- Recuperação/troca de senha.
- Login social via Google.
- Cada usuário só acessa e gerencia as próprias tablaturas (não há compartilhamento na Fase 1).

### 6.2 Gestão de Tablaturas (CRUD)
- Criar, listar, editar e excluir tablaturas próprias.
- Metadados obrigatórios de uma tablatura: **título**, **artista**, **afinação/capotraste**.
- Instrumento suportado: **violão de 6 cordas**, afinação padrão (E A D G B E), com suporte a **capotraste**. Afinações alternativas e outros instrumentos (baixo, cavaquinho, ukulele) estão fora de escopo da Fase 1.

### 6.3 Editor de Tablatura
- Editor visual próprio (não há importação de arquivos externos como Guitar Pro na Fase 1).
- O usuário insere as notas da tablatura como posições de corda/casa, na sequência em que devem ser tocadas.
- O editor **não captura ritmo/duração** das notas na Fase 1 — apenas a sequência de notas por corda.
- O usuário insere manualmente **marcadores de compasso** (equivalentes às barras `|` da tablatura tradicional) para delimitar onde cada compasso começa e termina. É a partir desses marcadores que o motor de sugestão de acordes organiza sua análise.

### 6.4 Motor de Sugestão de Acordes (diferencial central)

**Janela de análise:** o compasso (delimitado pelos marcadores inseridos pelo usuário) é a unidade base de análise.

**Regras de negócio:**
1. Para cada compasso, o sistema analisa o conjunto de notas (corda + casa) e busca, em uma base de acordes, qual(is) acorde(s) permitiriam tocar aquelas notas mantendo a mão numa única posição.
2. Se as notas de um compasso não podem ser cobertas por um único acorde, o sistema testa automaticamente possíveis subdivisões do compasso e sugere os pontos onde deve haver troca de acorde dentro do próprio compasso.
3. Quando mais de um acorde da base é compatível com a mesma janela de notas, o sistema apresenta as opções ao usuário, que escolhe qual usar como referência. A escolha do usuário é salva junto à tablatura.
4. Quando nenhum acorde da base tem correspondência satisfatória com a janela de notas (ex.: riffs, linhas de baixo melódicas), o sistema marca o trecho como **"sem sugestão"** — não força uma sugestão de baixa qualidade.
5. A sugestão considera o **capotraste** definido nos metadados da tablatura ao comparar com a base de acordes.
6. Ao editar notas de um compasso já existente, a sugestão daquele compasso é **recalculada quando o usuário salva** a edição (não é necessário recálculo em tempo real a cada tecla digitada).

**Base de acordes (catálogo):** catálogo curado internamente pela plataforma, cobrindo acordes abertos, acordes com pestana (barre) e variações comuns (maior, menor, 7, sus, dim, aug). Não é expansível pelo usuário na Fase 1.

### 6.5 Visualização / Modo de Estudo
- Após a análise da tablatura completa, a página exibe a tablatura inteira (navegável por scroll) com os acordes sugeridos indicados **sobre a tablatura**, delimitando visualmente qual região de notas corresponde a qual acorde — de forma semelhante a como uma cifra mostra o acorde acima do trecho da letra correspondente.
- Cada acorde sugerido é exibido junto de seu diagrama (desenho do braço do violão).
- Todos os acordes da música já estão calculados e visíveis na página ao mesmo tempo; não é necessário navegar compasso a compasso para revelá-los.

## 7. Fora de Escopo da Fase 1
- Compartilhamento de tablaturas (amigos ou comunidade) — Fase 2.
- Reprodução sonora / playback — Fase 3.
- Importação de arquivos de tablatura externos (Guitar Pro, ASCII, etc.).
- Captura de ritmo/duração de notas.
- Afinações alternativas.
- Outros instrumentos além de violão de 6 cordas.
- Edição colaborativa de tablaturas.
- Expansão do catálogo de acordes pelo usuário.

## 8. Requisitos Não Funcionais
- Aplicação web, responsiva.
- Idioma da interface: português (Brasil).
- Atualizações de estado da interface devem ser fluidas, refletindo mudanças (como recálculo de sugestões após salvar um compasso) sem necessidade de recarregar a página manualmente.

## 9. Glossário
- **Compasso:** unidade de agrupamento de notas delimitada manualmente pelo usuário no editor através de marcadores, usada como janela base de análise do motor de sugestão de acordes.
- **Janela de notas:** conjunto de notas (corda + casa) dentro de um compasso (ou subdivisão dele) que é comparado com a base de acordes.
- **Acorde de referência/sugerido:** acorde da base que indica a posição de mão recomendada para tocar as notas de uma janela.
- **Trecho livre/sem sugestão:** trecho cujas notas não correspondem satisfatoriamente a nenhum acorde da base.
