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

  ## Responsive row width, no horizontal scroll

  Each row is **one continuous 6-string braço** shared by however many
  compassos land in it, divided by bar-lines, not separate boxed-off cards
  side by side (see `StudyMeasureComponent`'s own moduledoc for the
  single-shared-grid mechanics and the `bar-line` convention borrowed from
  `docs/mockup-telas.html`'s `.tab-cell.bar-line`). How many compassos fit
  in one row depends on how wide the screen actually is — a phone has room
  for maybe one, a phablet/small tablet two, a desktop four — and Phoenix
  renders this page server-side, before it knows the connected browser's
  viewport width, so there's no single `Enum.chunk_every/2` call that's
  right for every screen.

  The fix is the standard CSS-only way to make a *server-rendered*
  grouping (not just spacing/sizing) responsive: render the whole
  tablature **three times**, once per breakpoint-appropriate compasso
  count (`@row_sizes`, one `Enum.chunk_every(@tab.measures, size)` each),
  and let Tailwind's responsive `hidden`/`block` utilities show only the
  one matching the actual viewport — never all three, and never zero.
  Each variant passes its own `variant` string down to
  `StudyMeasureComponent.study_row/1` (folded into every DOM id it emits)
  since the very same measures/segments exist three times on the page at
  once; without it, three copies of `id="study-measure-\#{measure.id}"`
  would collide. This costs 3x the markup for one screen's worth of
  compassos (acceptable here: an authenticated, non-indexed reading
  screen, not content needing to stay lean for SEO/first paint), not 3x
  the analysis — `@tab.measures`/its `chord_segments` are still loaded and
  computed exactly once by `load_study_tree!/2` below; only the `~H`
  rendering repeats.

  A compasso count chosen to comfortably fit its breakpoint's width still
  can't *guarantee* every row fits — a compasso with several chords in it
  (each padded to `StudyMeasureComponent`'s own `@chip_min_columns`, per
  its "chord-chip overlay" moduledoc section) can still need more total
  width than even one compasso has room for on a narrow phone.
  `StudyMeasureComponent.study_row/1`'s own `overflow-x-auto` stays as the
  last-resort fallback for exactly that rare case — contained to that one
  row, never the page — so the study screen's *own* scrolling is
  vertical-only in the common case and only that one dense row ever grows
  a (horizontal) scrollbar of its own in the rare one.

  `Layouts.app`'s shared `<main>` wraps every page's content in `mx-auto
  max-w-2xl` (672px) — comfortable for prose, unusable for a multi-compasso
  braço that wants to fill whatever width the screen actually has — so
  this render deliberately breaks out of it (`-mx-[calc((100vw-100%)/2)]`
  cancels that ancestor's centering margin) rather than widening the
  shared layout for every other screen. Unlike an early version of this
  layout, the escaped area is **not** re-capped at some `max-w-*` of its
  own: a centered column with empty margins on either side is exactly the
  "não aproveita a tela" complaint that shape drew, and every extra pixel
  of width here is a pixel `StudyMeasureComponent.study_row/1` can give
  the "desktop" row-set (`@row_sizes`) before it needs its own
  `overflow-x-auto` fallback — so the tablature now genuinely fills
  whatever's between the `px-4 sm:px-6 lg:px-8` side gutters, on any
  screen, including an ultra-wide monitor.

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

  ## Live updates while analysis is running (issue #24)

  `mount/3` subscribes to `"tab:\#{tab.id}"` — the same topic
  `Ponteio.Tablatures.Changes.RunChordAnalysis` broadcasts on (issue #20) —
  once the socket is `connected?/1` (skipping the topic-less static render
  during dead-render/live-navigation, same guard every other subscribing
  LiveView in this codebase would use, avoiding a duplicate subscription
  from the disconnected mount that immediately gets thrown away).

  Two messages arrive on that topic, both handled without ever
  `redirect`/`push_navigate`-ing the socket (this issue's explicit "sem
  reload de página" requirement):

  - `:analyzing` — flips the local `@tab.status` assign to `:analyzing`
    (no DB round-trip needed: the broadcast itself is the signal, and the
    struct held in the assign is the only place that status is displayed).
    The template shows a visible "Analisando acordes..." banner whenever
    `@tab.status == :analyzing`, covering both this live transition and
    the (rarer) case of landing on this page while a background run is
    already in flight.
  - `{:analysis_completed, tab_id}` — re-fetches the `Tab` itself via
    `Ash.get!/3` (picking up the fresh `status: :ready` the action's own
    final commit wrote, which a plain `Ash.load!/3` of relationships alone
    would not refresh) and reloads the whole compasso/nota/acorde tree
    through the same `load_study_tree!/2` `mount/3` already uses — the new
    `ChordSegment`/`ChordSuggestion` rows `RunChordAnalysis` just committed
    (guaranteed already-committed by the time this message is delivered,
    since it broadcasts from `after_transaction/2`, per that module's own
    moduledoc) replace the stale tree in one `assign/3`, which LiveView
    then re-renders in place.

  ## What this issue deliberately does not do

  - **Choosing between ambiguous candidates** (issue #21's "N de M
    sugestões ▾" dropdown) is not wired here either: `StudyMeasureComponent`
    shows that count as a static label, never a `<select>`/`phx-click`,
    since picking a candidate is not among this issue's stated acceptance
    criteria (only *displaying* the suggested/no-match regions is).
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

  # One row-set per breakpoint (see moduledoc "Responsive row width, no
  # horizontal scroll") — `variant` disambiguates the DOM ids
  # `StudyMeasureComponent.study_row/1` emits for what's otherwise the
  # exact same measures/segments rendered again, `class` is the Tailwind
  # visibility toggle that keeps exactly one of the three actually visible
  # at a time, and `size` is that breakpoint's `Enum.chunk_every/2` count.
  @row_sizes [
    %{variant: "mobile", size: 1, class: "sm:hidden"},
    %{variant: "tablet", size: 2, class: "hidden sm:block lg:hidden"},
    %{variant: "desktop", size: 4, class: "hidden lg:block"}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Ash.get(Tab, id, actor: user, domain: Ponteio.Tablatures) do
      {:ok, tab} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Ponteio.PubSub, "tab:#{tab.id}")
        end

        tab = load_study_tree!(tab, user)

        {:ok, assign(socket, tab: tab, page_title: "Estudo: #{tab.title}")}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, @not_accessible_flash)
         |> redirect(to: ~p"/tabs")}
    end
  end

  # `RunChordAnalysis`'s first broadcast (issue #20) — the independently
  # committed `status: :analyzing` write, sent right after it happens.
  # Flipping the assign locally (rather than re-fetching) is enough: the
  # broadcast itself is the up-to-date signal, and `@tab.status` is the
  # only thing the "Analisando..." banner below reads.
  @impl true
  def handle_info(:analyzing, socket) do
    {:noreply, update(socket, :tab, &%{&1 | status: :analyzing})}
  end

  # `RunChordAnalysis`'s second broadcast — sent from `after_transaction/2`
  # once the whole action (status flip to `:ready` plus every
  # `ChordSegment`/`ChordSuggestion` it persisted) has actually committed
  # (see that module's moduledoc), so it's always safe to reload here.
  # Re-fetches the `Tab` itself first (picking up the fresh `status`, which
  # `load_study_tree!/2` alone — a relationships-only `Ash.load!/3` — would
  # never refresh), then reloads the whole tree through the same helper
  # `mount/3` uses, replacing the stale assign in place. Never navigates.
  @impl true
  def handle_info({:analysis_completed, tab_id}, socket) do
    user = socket.assigns.current_user
    tab = Ash.get!(Tab, tab_id, actor: user, domain: Ponteio.Tablatures)
    tab = load_study_tree!(tab, user)

    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :row_sizes, @row_sizes)

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

      <div :if={@tab.status == :analyzing} id="analyzing-banner" class="alert alert-warning mb-4">
        <span class="loading loading-spinner loading-sm"></span>
        <span>
          Analisando acordes... As sugestões serão atualizadas automaticamente ao terminar.
        </span>
      </div>

      <div class="-mx-[calc((100vw-100%)/2)] px-4 sm:px-6 lg:px-8">
        <.study_rows
          :for={row_size <- @row_sizes}
          tab={@tab}
          variant={row_size.variant}
          size={row_size.size}
          class={row_size.class}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :tab, :map, required: true
  attr :variant, :string, required: true
  attr :size, :integer, required: true
  attr :class, :string, required: true

  defp study_rows(assigns) do
    ~H"""
    <div class={["flex flex-col gap-4", @class]}>
      <StudyMeasureComponent.study_row
        :for={row <- Enum.chunk_every(@tab.measures, @size)}
        measures={row}
        capo_fret={@tab.capo_fret}
        variant={@variant}
      />
    </div>
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
