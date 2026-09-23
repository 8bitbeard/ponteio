# SDD — Ponteio (Fase 1 / MVP)
### Elixir + Phoenix LiveView + Ash Framework · Desktop-only

## 1. Stack e Princípios
- **Elixir + Phoenix LiveView** para toda a interface (sem API JSON separada nesta fase).
- **Ash Framework** organiza todo o backend: os antigos "Phoenix Contexts" viram **Domains** do Ash, e os schemas Ecto viram **Resources** com ações declarativas (`create`, `read`, `update`, `destroy`, ações customizadas).
- **AshPostgres** como data layer dos resources (PostgreSQL por baixo, normalizado — tabelas separadas para tablatura, compasso e nota).
- **AshAuthentication** (+ `AshAuthentication.Phoenix`) para autenticação: estratégia `password` (email/senha, troca de senha, confirmação) e estratégia `google` (OAuth2) para login social. Substitui o `phx.gen.auth` + Ueberauth previstos na versão anterior deste SDD.
- **AshOban** para dispersar a análise de sugestão de acordes de forma assíncrona via trigger declarativo no resource; **Phoenix.PubSub** para notificar os LiveViews quando a análise termina.
- **Ash.Policy.Authorizer** em cada resource para a regra "usuário só acessa as próprias tablaturas" — declarada como policy, não como filtro manual espalhado pelo código.
- **AshPhoenix** (`AshPhoenix.Form`) para conectar os formulários dos LiveViews diretamente às ações dos resources.
- Domains: `Ponteio.Accounts`, `Ponteio.Tablatures`, `Ponteio.Chords`.
- Desktop-only: sem necessidade de layout adaptativo para toque/telas pequenas nesta fase.

## 2. Modelagem de Dados (Ash Resources)

### 2.1 Domain `Ponteio.Accounts`

**Resource `User`**
- Usa a extensão `AshAuthentication`, com:
  - `strategies :password` — email + senha, com add-ons `confirmation` e `resettable` (troca/recuperação de senha).
  - `strategies :google` (via `AshAuthentication.Strategy.OAuth2`, preset Google) — login social.
- Atributos: `email`, `hashed_password` (gerido pela estratégia password).
- Relacionamento: `has_many :tabs, Ponteio.Tablatures.Tab`.

### 2.2 Domain `Ponteio.Tablatures`

**Resource `Tab`**
| atributo | tipo |
|---|---|
| user_id | `belongs_to :user, Ponteio.Accounts.User` |
| title | `:string` |
| artist | `:string` |
| capo_fret | `:integer`, default 0 |
| status | `:atom`, `[:draft, :analyzing, :ready]` |

`status` existe para a UI refletir quando o AshOban está processando a análise (ex.: exibir "analisando..." no modo de estudo).

**Policy do resource:** `actor(:user).id == user_id` exigido para as ações `read`, `update` e `destroy`. A ação `create` sempre grava `user_id` a partir do actor (`change relate_actor(:user)`), então o usuário nunca cria tablatura em nome de outro.

**Relacionamentos:** `has_many :measures, Ponteio.Tablatures.Measure`.

**Resource `Measure`** (compasso)
| atributo | tipo |
|---|---|
| tab_id | `belongs_to :tab, Ponteio.Tablatures.Tab` |
| position | `:integer` (ordem do compasso na música) |

Policy: herdada por relacionamento (`relates_to_actor_via [:tab, :user]`) — só acessível se o `tab` pai pertence ao actor.

**Resource `Note`**
| atributo | tipo |
|---|---|
| measure_id | `belongs_to :measure, Ponteio.Tablatures.Measure` |
| string_number | `:integer` (1–6) |
| fret_number | `:integer` (**relativo ao capo** — casa 0 = posição do capo) |
| position | `:integer` (ordem dentro do compasso) |

**Resource `ChordSegment`** (resultado da análise: sub-trecho de um compasso mapeado a candidatos de acorde)
| atributo | tipo |
|---|---|
| measure_id | `belongs_to :measure, Ponteio.Tablatures.Measure` |
| start_position / end_position | `:integer` (posições de nota cobertas, dentro do compasso) |
| status | `:atom`, `[:suggested, :no_match]` |
| selected_suggestion_id | `belongs_to :selected_suggestion, Ponteio.Tablatures.ChordSuggestion`, opcional — escolha do usuário |

**Resource `ChordSuggestion`** (candidatos calculados para um segmento)
| atributo | tipo |
|---|---|
| chord_segment_id | `belongs_to :chord_segment, Ponteio.Tablatures.ChordSegment` |
| chord_shape_id | `belongs_to :chord_shape, Ponteio.Chords.ChordShape` |
| base_fret | `:integer` (posição no braço onde o shape foi aplicado) |
| rank | `:integer` (1 = melhor, até 3) |

### 2.3 Domain `Ponteio.Chords`

**Resource `ChordShape`** (catálogo curado)
| atributo | tipo |
|---|---|
| name | `:string` (ex.: "Maior", "Menor", "7", "Sus4", "Dim", "Aug") |
| quality | `:atom` interno (usado para nomear o acorde resultante) |
| relative_frets | `{:array, :integer}` de 6 posições (uma por corda); cada valor é um offset relativo ao `base_fret`, ou `nil` se a corda é abafada/não faz parte do shape |
| root_string | `:integer` (qual corda carrega a nota fundamental — usada para nomear o acorde, ex. "Sol", "Ré7") |
| movable | `:boolean` (true = pestana, false = aberto) |
| min_base_fret / max_base_fret | `:integer` (0/0 para abertos; ex. 1..9 para pestana) |

Sem policy de autorização — catálogo é lido por qualquer usuário autenticado, nunca escrito por eles (seed interno).

A afinação padrão (E A D G B E) é uma **constante de aplicação**, não um resource — usada junto com `root_string` + `base_fret` para calcular o nome da nota fundamental exibido no diagrama.

## 3. Algoritmo de Sugestão de Acordes

A lógica pura (correspondência, segmentação, ranking) continua vivendo em funções Elixir comuns dentro do domain `Ponteio.Chords` — o Ash não muda esse núcleo, só a forma como ele é *disparado* e *persistido* (via ação do resource + trigger AshOban).

### 3.1 Candidatos para uma janela de notas
Dada uma janela (lista de pares `{corda, casa}`):
```
para cada chord_shape no catálogo:
  para cada base_fret entre chord_shape.min_base_fret e chord_shape.max_base_fret:
    instancia o shape: expected_fret[corda] = relative_frets[corda] + base_fret (ou nil se abafada)
    se TODA nota da janela satisfaz nota.casa == expected_fret[nota.corda] (e não é nil):
      adiciona {chord_shape, base_fret} aos candidatos
retorna candidatos
```
Isso implementa a regra de **correspondência por subconjunto**: cordas do shape não tocadas nesse trecho não impedem o match.

### 3.2 Segmentação do compasso (busca exaustiva)
Objetivo: dividir as N notas do compasso (em ordem) no **menor número de segmentos** possível, onde cada segmento contíguo:
- tem ao menos 1 candidato válido (segmento "chorded"), **ou**
- é uma nota isolada sem candidato algum (segmento `no_match`, fallback — só permitido para segmentos de tamanho 1).

Resolvido via **programação dinâmica**: `dp[i]` = menor número de segmentos para cobrir as primeiras `i` notas.
```
dp[0] = 0
para i de 1 até N:
  dp[i] = infinito
  para j de 0 até i-1:
    janela = notes[j..i)
    se candidatos_para(janela) não vazio, ou (i - j == 1):
      custo = dp[j] + 1
      se custo < dp[i]: dp[i] = custo; backtrack[i] = j
reconstrói os segmentos a partir de backtrack[N]
```
Isso garante o **menor número de trocas de acorde** dentro do compasso, com fallback de nota isolada quando nada casa.

### 3.3 Ranking dos candidatos de um segmento
Critério: **menor deslocamento de mão** em relação à posição anterior.
```
rank_candidates(candidatos, posicao_anterior):
  ordena candidatos por abs(candidato.base_fret - posicao_anterior)
  retorna os 3 primeiros, com rank 1..3
```
**Importante — continuidade entre compassos:** `posicao_anterior` é a **posição do último segmento resolvido da música inteira** (não reinicia a cada compasso), já que a mão do violonista não "reseta" na troca de compasso. Para o primeiríssimo segmento da música, usa-se `posicao_anterior = 0` (posição aberta) como referência default.
A "posição resolvida" de um segmento para efeito de referência do próximo é o `base_fret` do candidato de **rank 1**, calculado durante a mesma passada de análise (não depende da escolha manual do usuário).

### 3.4 Ação de análise + trigger AshOban

O resource `Tab` ganha uma ação genérica `:run_chord_analysis`, responsável por rodar o algoritmo acima (via chamadas às funções puras de `Ponteio.Chords`) e persistir os `ChordSegment`/`ChordSuggestion` resultantes. Essa ação é disparada automaticamente por um **trigger AshOban**, sem enqueue manual de job:

```elixir
# no resource Tab
oban do
  triggers do
    trigger :analyze_chords do
      action :run_chord_analysis
      where expr(status == :draft or status == :analyzing)
    end
  end
end
```

Fluxo equivalente ao worker manual da versão anterior:
```
run_chord_analysis(tab):
  atualiza tab.status = :analyzing; PubSub.broadcast("tab:#{tab.id}", :analyzing)
  apaga chord_segments/chord_suggestions antigos do tab
  posicao_anterior = 0
  para cada measure em ordem:
    segmentos = Chords.segment_measure(measure.notes)
    para cada segmento:
      candidatos = Chords.candidates_for_window(segmento.notas)
      se candidatos vazio: cria ChordSegment status: :no_match
      senão:
        ranked = Chords.rank_candidates(candidatos, posicao_anterior)
        cria ChordSegment status: :suggested + ChordSuggestions (rank 1..3)
        posicao_anterior = ranked[0].base_fret
  atualiza tab.status = :ready
  PubSub.broadcast("tab:#{tab.id}", {:analysis_completed, tab.id})
```
O trigger dispara quando o usuário salva edições de notas/compassos no editor (a ação que atualiza `Note`/`Measure` também marca `tab.status = :draft`, o que satisfaz o `where` do trigger) — não a cada tecla digitada, conforme definido no PRD.

## 4. LiveViews e Componentes

| LiveView | Responsabilidade |
|---|---|
| `TabLive.Index` | Listagem/CRUD das tablaturas do usuário logado |
| `TabLive.Editor` | Formulário de metadados (título, artista, capotraste) + editor visual de compassos/notas, via `AshPhoenix.Form`; salvar dispara o trigger AshOban indiretamente |
| `TabLive.Study` | Modo de estudo: tablatura completa, scrollável, com acordes sobrepostos por segmento |

| Componente | Responsabilidade |
|---|---|
| `ChordDiagramComponent` | Renderiza o diagrama (braço do violão) a partir de `chord_shape` + `base_fret` |
| `MeasureEditorComponent` | Grid de entrada de notas (corda × posição) de um compasso no editor |

`TabLive.Editor` e `TabLive.Study` assinam o tópico `"tab:#{tab_id}"` no `mount/3` e reagem a `{:analysis_completed, tab_id}` recarregando `chord_segments`/`chord_suggestions` nos assigns — sem reload de página.

Os formulários de `TabLive.Editor` são construídos com `AshPhoenix.Form.for_create/2` e `for_update/2` a partir das ações do resource `Tab` — validações (ex.: título obrigatório) ficam declaradas na ação do resource, não duplicadas no LiveView.

## 5. Interface Pública dos Domains (rascunho)

Com Ash, a API pública deixa de ser um módulo de contexto escrito à mão e passa a ser a **code interface** declarada em cada domain (`define :nome, action: :acao`), que gera funções normais para chamar de fora (LiveViews, testes):

**`Ponteio.Tablatures`**
- `list_tabs_for_user/1`, `get_tab!/1`, `create_tab/1`, `update_tab/2`, `delete_tab/1` — code interfaces sobre as ações padrão do resource `Tab`
- `upsert_measure_notes/2` — ação customizada no resource `Measure`/`Note` que salva notas/marcadores de compasso e marca `tab.status = :draft` (satisfazendo o trigger do AshOban)
- `select_chord_suggestion/2` — ação customizada em `ChordSegment` que persiste a escolha do usuário entre os candidatos

**`Ponteio.Chords`**
- `ChordShape` exposto só para leitura (`list_chord_shapes/0`)
- `candidates_for_window/2`, `segment_measure/1`, `rank_candidates/2` — funções puras (não são ações Ash, são módulos Elixir comuns usados internamente pela ação `:run_chord_analysis`)

## 6. Estratégia de Testes
- **`Ponteio.Chords`** (funções puras): testes unitários ExUnit sobre `candidates_for_window/2`, `segment_measure/1` e `rank_candidates/2`, com fixtures de `chord_shapes` — não depende de banco, Ash ou LiveView.
- **Resources**: testes de ação via `Ash.create!/Ash.update!/Ash.destroy!` diretamente (sem passar por LiveView), cobrindo policies (actor sem permissão deve ser barrado) e validações.
- **Trigger AshOban**: `AshOban.Test` (ou `Oban.Testing` por baixo) para disparar `:run_chord_analysis` manualmente em teste e validar a persistência de `ChordSegment`/`ChordSuggestion` a partir de compassos de exemplo.
- **LiveViews**: `Phoenix.LiveViewTest` cobrindo fluxo de criação/edição de tablatura via `AshPhoenix.Form` e atualização do modo de estudo após broadcast do PubSub.

## 7. Telas e Rotas

Mockup de referência: https://claude.ai/artifact/SWfmCNPaU4ER4qecEnatam (3 telas: Minhas tablaturas, Editor, Estudo).

| Rota | LiveView | `live_action` | Tela |
|---|---|---|---|
| `GET /tabs` | `TabLive.Index` | `:index` | Minhas tablaturas — listagem/CRUD |
| `GET /tabs/new` | `TabLive.Editor` | `:new` | Editor — criação de tablatura nova |
| `GET /tabs/:id/edit` | `TabLive.Editor` | `:edit` | Editor — edição de tablatura existente |
| `GET /tabs/:id/study` | `TabLive.Study` | `:show` | Modo de estudo (leitura, acordes sobrepostos) |

`TabLive.Index` e `TabLive.Editor` compartilham o mesmo módulo LiveView, diferenciados por `live_action` (`:new` vs `:edit`), já que o formulário de metadados e o editor de compassos são idênticos nos dois casos — só muda se a tablatura já existe no banco.

Rotas de autenticação são geradas pelas macros de router do `AshAuthentication.Phoenix` (`sign_in_route`, `sign_out_route`, `reset_route`, `auth_routes_for Ponteio.Accounts.User`), incluindo o callback OAuth do Google automaticamente — sem necessidade de configurar rotas manuais do Ueberauth.

Todas as rotas de `tabs` exigem sessão autenticada (`on_mount` gerado pelo `AshAuthentication.Phoenix`) e são escopadas ao usuário logado **via policy do resource** (`Ash.Policy.Authorizer`), não por filtro manual nas queries — não há acesso a tablaturas de outros usuários na Fase 1 (sem compartilhamento).

## 8. Pontos em Aberto (assumidos como padrão de engenharia, ajustáveis)
- Critério de desempate secundário quando dois candidatos têm o mesmo deslocamento de posição anterior: menor `base_fret` absoluto.
- Tamanho máximo de compasso (nº de notas) não é limitado explicitamente — a busca exaustiva de segmentação é O(N²) em relação ao nº de notas do compasso, aceitável para o volume esperado de uma tablatura manual.
- Sintaxe exata do trigger AshOban (`where`, nomes de callback) segue a API da versão do pacote no momento da implementação — o pseudocódigo da seção 3.4 descreve o comportamento esperado, não o código final.
