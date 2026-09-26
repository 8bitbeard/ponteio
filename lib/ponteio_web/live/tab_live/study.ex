defmodule PonteioWeb.TabLive.Study do
  @moduledoc """
  `GET /tabs/:id/study` — "Modo de estudo" (issue #22, "Visualizar
  tablatura completa com acordes sobrepostos"; PRD §6.5; SDD §4, §7).

  The consumption screen the whole "cifra + tablatura" pitch (PRD §1)
  actually delivers on: the full tablature, every compasso, rendered in
  one scrollable page — no per-measure pagination or "reveal the next
  chord" interaction (this issue's explicit acceptance criteria) — with
  each already-computed `ChordSegment` overlaid as a `chord-chip`
  delimiting the note region it covers, the way a cifra shows a chord
  above the lyric line it applies to.

  ## Loading (SDD §4's own prescription)

  `mount/3` loads the `Tab` scoped to its owner via `Ash.get/3` (same
  "authorization denial, never a silent crash" treatment as
  `TabLive.Editor`/`TabLive.Index` — issue #10), then, in one
  `Ash.load!/3` call, its whole associated tree: `measures` (sorted by
  `position`) → `notes` (sorted by `position`) and `chord_segments`
  (sorted by `start_position`) → `chord_suggestions` (sorted by `rank`)
  plus each segment's `selected_suggestion` (issue #21's pick, when one
  exists). None of these four resources declares a default sort on its
  own `:read` action (each has its own reason not to — see their
  moduledocs), so this issue is the first caller that actually needs one,
  supplied here via a nested `Ash.Query` per relationship — Ash loads a
  relationship with whatever query it's given as the load statement's
  value, which is what makes per-level sorting possible in the single
  call SDD §4 sketches, rather than N+1 separate queries.

  This is a single, eager, whole-tree load — never lazy/paginated per
  compasso — precisely because the screen itself must show every compasso
  and every already-computed chip at once (this issue's third acceptance
  criterion); there is nothing left to fetch on scroll or on demand.

  ## What this issue deliberately does not do

  - **The chord diagram** (`ChordDiagramComponent`, the little braço-do-violão
    drawing the mockup shows inside each chip) is issue #23's scope, not
    this one's — `StudyMeasureComponent`'s chip shows only the chord's
    display name.
  - **Choosing between ambiguous candidates** (issue #21's "N de M
    sugestões ▾" dropdown) is not wired here either: `StudyMeasureComponent`
    shows that count as a static label, never a `<select>`/`phx-click`,
    since picking a candidate is not among this issue's stated acceptance
    criteria (only *displaying* the suggested/no-match regions is).
  - **Live updates while analysis is running** (subscribing to
    `"tab:\#{tab_id}"`, reacting to `:analyzing`/`{:analysis_completed,
    tab_id}`) is issue #24's scope (SDD §4 describes the eventual
    behavior, but `Ponteio.Tablatures.Changes.RunChordAnalysis`'s own
    moduledoc explicitly attributes the reloading subscriber to "issue
    #24, not yet implemented") — this LiveView loads the tree once, on
    mount, and does not react to broadcasts. Visiting a tab that is still
    `:draft`/`:analyzing` (nothing stops that at the router level; only
    `TabLive.Index`'s own "Estudar" shortcut hides itself for a non-ready
    tab) simply renders whatever `chord_segments` already exist for it —
    typically none yet — without erroring.
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  require Ash.Query

  alias Ponteio.Tablatures.ChordSegment
  alias Ponteio.Tablatures.ChordSuggestion
  alias Ponteio.Tablatures.Measure
  alias Ponteio.Tablatures.Note
  alias Ponteio.Tablatures.Tab
  alias PonteioWeb.TabLive.StudyMeasureComponent

  # Same non-committal wording as `TabLive.Editor`'s equivalent constant
  # (issue #10) — confirming "it belongs to someone else" would itself
  # leak that the id exists, which the read policy's filter-based scoping
  # is designed to avoid.
  @not_accessible_flash "Tablatura não encontrada ou você não tem permissão para acessá-la."

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Ash.get(Tab, id, actor: user, domain: Ponteio.Tablatures) do
      {:ok, tab} ->
        tab = load_study_tree!(tab, user)

        {:ok, assign(socket, tab: tab, page_title: "Estudo: #{tab.title}")}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, @not_accessible_flash)
         |> redirect(to: ~p"/tabs")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-start justify-between gap-4 mb-2">
        <div>
          <h1 class="text-2xl font-semibold">{@tab.title}</h1>
          <p class="text-base-content/70">{@tab.artist}</p>
        </div>

        <div class="flex items-center gap-3">
          <span :if={@tab.capo_fret > 0} class="badge badge-outline">
            Capo na {@tab.capo_fret}ª casa
          </span>
          <.link navigate={~p"/tabs"} class="btn btn-ghost">Voltar</.link>
        </div>
      </div>

      <StudyMeasureComponent.study_measure
        :for={measure <- @tab.measures}
        measure={measure}
        capo_fret={@tab.capo_fret}
      />
    </Layouts.app>
    """
  end

  # Single eager load of the whole compasso/nota/acorde tree (SDD §4),
  # each level sorted the way this screen needs it rendered — see this
  # module's moduledoc "Loading" section for why a plain `Ash.load!(tab,
  # measures: [notes: [], chord_segments: [chord_suggestions: []]])`
  # (SDD §4's own illustrative example) isn't enough on its own: none of
  # these four `:read` actions carries a default sort, so each nested
  # relationship is loaded through its own `Ash.Query` (with its own
  # `sort`, and its own further nested `load`) instead of a bare atom/list.
  defp load_study_tree!(tab, user) do
    Ash.load!(
      tab,
      [
        measures:
          Measure
          |> Ash.Query.sort(position: :asc)
          |> Ash.Query.load(
            notes: Ash.Query.sort(Note, position: :asc),
            chord_segments:
              ChordSegment
              |> Ash.Query.sort(start_position: :asc)
              |> Ash.Query.load(
                chord_suggestions:
                  ChordSuggestion
                  |> Ash.Query.sort(rank: :asc)
                  |> Ash.Query.load(:chord_shape),
                selected_suggestion: [:chord_shape]
              )
          )
      ],
      actor: user
    )
  end
end
