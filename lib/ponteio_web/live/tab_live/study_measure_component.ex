defmodule PonteioWeb.TabLive.StudyMeasureComponent do
  @moduledoc """
  Renders one **row of the study screen** — up to four compassos sharing
  one continuous 6-string "braço" (fretboard), read-only, for
  `PonteioWeb.TabLive.Study` (issue #22, "Visualizar tablatura completa
  com acordes sobrepostos"; PRD §6.5; SDD §4, §7).

  This is a plain `Phoenix.Component` function component — same rationale
  as `PonteioWeb.TabLive.MeasureEditorComponent` (no isolated state to
  keep, `TabLive.Study` owns everything as assigns) — but read-only: there
  is no `phx-click`/editable cell here, since study mode is pure
  consumption (PRD §6.5 draws no editing affordance for it, unlike the
  editor).

  ## One continuous grid per row, not one card per compasso

  A row's compassos are **not** independent boxes side by side — the
  string lines (`e B G D A E`) run uninterrupted across every compasso in
  the row, divided only by a `bar-line` (a `border-r-2` on a compasso's
  last column, the exact convention `docs/mockup-telas.html`'s own
  `.tab-cell.bar-line` already defines — that mockup only ever shows one
  compasso per row, but the class was already styled as a column-ending
  border, ready for this). Achieved by building **one** `grid-template-
  columns` for the whole row (`1.5rem` label gutter + one `2.5rem` column
  per note across *every* compasso in the row) and rendering each of the
  six strings as a single grid row spanning that whole template, rather
  than one grid per compasso — the same "shared grid template" trick
  `MeasureEditorComponent`'s control row uses for its scissors buttons,
  just widened to cover several compassos' worth of columns at once.

  `build_entries/1` turns the row's `measures` into `%{measure:,
  column_count:, offset:, column_plan:}` entries. `offset` is the running
  sum of every earlier entry's own `column_count`, i.e. where that
  compasso's columns start within the row's single grid (column 1 is
  always the label gutter, so a compasso's first column is `offset + 2`).
  `column_plan` (`build_column_plan/1`) is the real reason this isn't a
  straight `Note.position`-to-column mapping: each of the measure's
  segments gets its own `%{segment:, local_start:, real_span:,
  padded_span:}`, and a `:suggested` segment's `padded_span` is *at least*
  `@chip_min_columns` regardless of how many real notes it actually
  covers or where it sits within the measure — every chord gets room for
  its own diagram, not only one lucky enough to end the measure. The gap
  between a segment's `real_span` and its `padded_span` renders as empty
  note cells right after its real notes (`note_at_column/3`), and
  `column_count` is simply the sum of every plan item's own `padded_span`.
  `TabLive.Study` decides how many compassos land in one row — a fixed
  number per *screen breakpoint*, not overall (see its own moduledoc
  "Responsive row width, no horizontal scroll") — this component only
  ever renders whatever `measures` list it's given as one braço, for
  whichever breakpoint is asking.

  `TabLive.Study`'s max-width breakout gives a row generous space, but a
  row with enough total (padded) columns can still exceed it — the whole
  row (label row, chip row and all six string rows together, so they
  never drift out of column alignment with each other) sits in one shared
  `overflow-x-auto`, the fallback that keeps the study screen's own
  scrolling vertical-only (see that module's moduledoc). That div also
  carries an explicit `overflow-y-hidden`: per the CSS overflow spec, a
  `visible` value on one axis is invalid once the other is anything but
  `visible`, so a bare `overflow-x-auto` computes `overflow-y` as `auto`
  too, not `visible` — harmless as long as content never needs to scroll
  vertically (it doesn't here, the row's height is exactly its content's),
  *except* that on a platform with classic, space-reserving scrollbars
  (unlike this browser's own overlay ones), the horizontal scrollbar this
  div is legitimately showing eats into its available height, which can
  then trigger that auto-computed `overflow-y` for real — an unwanted
  vertical scrollbar on a single row. `overflow-y-hidden` forecloses that
  regardless of the viewer's scrollbar style, without hiding anything real.

  ## The chord-chip overlay (issue #22's actual new part over the editor's grid)

  A `segment-row`-equivalent sits above the string grid, sharing the same
  row-wide `grid-template-columns` so its brackets line up over the exact
  (padded) note columns they cover. For each of the measure's segments —
  `entry_segments/1` pairs every real plan item with the entry it belongs
  to — one bracket spans `grid-column: (entry.offset + plan_item.local_start
  + 2) / span plan_item.padded_span`.

  A `:suggested` segment's bracket shows a `chord-chip` with the
  suggestion actually being displayed (`ChordSegment.selected_suggestion`
  when the user already chose one via issue #21's
  `select_chord_suggestion`, else the rank-1 candidate — the same
  documented fallback that action's own resource description states) and,
  when the segment carries more than one candidate, a small "N de M
  sugestões" line — a **static** label, not the interactive dropdown
  mockup shows (`docs/mockup-telas.html`, Tela 3, `.chord-chip .pick`):
  wiring that selector to `Ponteio.Tablatures.select_chord_suggestion/3`
  is issue #21's own UI half, not yet built anywhere in the codebase, and
  is not among this issue's acceptance criteria (which only call for
  *displaying* the suggested/no-match regions, not for choosing between
  them). The chord diagram itself (`ChordDiagramComponent.chord_diagram/1`,
  the little braço-do-violão drawing the mockup shows inside the chip) is
  issue #23's addition, rendered here from the same `suggestion` already
  resolved for the chip's name/rank label — **every** `:suggested`
  segment's chip includes it, even one repeating a chord already drawn
  earlier in the same tab, and even a segment too narrow to comfortably
  fit it (explicit product requirement over avoiding overflow — see
  `chord_chip/1`'s own comment).

  A `:no_match` segment's bracket shows a plain "sem sugestão" label
  instead (PRD §6.4 regra 4), dashed rather than solid to distinguish it
  visually from a resolved segment (mirrors the mockup's `.segment-bracket.muted`).

  ## Which notes share a hand position

  The bracket above already says *where* one chord ends and the next
  begins, but that boundary is easy to miss once your eyes are down on
  the string grid itself, actually playing the notes. `chorded_spans/1`
  gives every `:suggested` segment's own note columns (its plan item's
  `local_start`/`padded_span`, so the shading lines up exactly with its
  bracket above, padding included) a background tint —
  alternating `"a"`/`"b"` in playing order, so two consecutive chords are
  always visibly different even across a compasso boundary within the
  row. Every note cell under the same tint is playable without moving the
  hand up/down the braço; the tint changing *is* the hand-position change.
  A `:no_match` segment's lone note gets no tint at all (it isn't part of
  either neighboring hand position).
  """

  use PonteioWeb, :html

  alias Ponteio.Chords
  alias PonteioWeb.TabLive.ChordDiagramComponent

  @strings 1..6
  @string_labels %{1 => "e", 2 => "B", 3 => "G", 4 => "D", 5 => "A", 6 => "E"}

  # The minimum `padded_span` (`build_column_plan/1`) any `:suggested`
  # segment gets — roughly enough columns for its diagram + name + rank
  # chip (`chord_chip/1`, always rendered in full) to have room to
  # breathe, independent of every other segment in the same measure.
  @chip_min_columns 6

  attr :measures, :list, required: true
  attr :capo_fret, :integer, required: true

  # Disambiguates DOM ids when the *same* measures render more than once on
  # the same page — `TabLive.Study` does exactly that (one set of rows per
  # responsive breakpoint, see its own moduledoc "Responsive row width,
  # no horizontal scroll"), so every id this component emits
  # (`dom_id/3`) folds this in. Left at its default `""` (no infix) for a
  # `study_row/1` rendered just once, e.g. every test in
  # `StudyMeasureComponentTest`.
  attr :variant, :string, default: ""

  def study_row(assigns) do
    entries = build_entries(assigns.measures)
    total_columns = entries |> List.last() |> then(&(&1.offset + &1.column_count))
    segments = entry_segments(entries)

    assigns =
      assigns
      |> assign(:entries, entries)
      |> assign(:segments, segments)
      |> assign(:chorded_spans, chorded_spans(segments))
      |> assign(:total_columns, total_columns)
      |> assign(:template, "1.5rem repeat(#{total_columns}, 2.5rem)")
      |> assign(:strings, @strings)

    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-100 p-4">
      <div class="overflow-x-auto overflow-y-hidden">
        <div class="flex flex-col gap-1 w-fit min-w-full">
          <div class="grid" style={"grid-template-columns: #{@template};"}>
            <span></span>

            <span
              :for={entry <- @entries}
              id={dom_id("study-measure", @variant, entry.measure.id)}
              style={"grid-column: #{entry.offset + 2} / span #{entry.column_count};"}
              class="text-sm font-semibold text-base-content/70"
            >
              Compasso {entry.measure.position}
            </span>
          </div>

          <div class="grid items-end min-h-16 pb-2" style={"grid-template-columns: #{@template};"}>
            <span></span>

            <.segment_bracket
              :for={{entry, plan_item} <- @segments}
              entry={entry}
              plan_item={plan_item}
              capo_fret={@capo_fret}
              variant={@variant}
            />
          </div>

          <div
            :for={string_number <- @strings}
            class="grid items-center h-7"
            style={"grid-template-columns: #{@template};"}
          >
            <span class="text-xs font-semibold text-base-content/60">
              {string_label(string_number)}
            </span>

            <.note_cell
              :for={column <- 0..(@total_columns - 1)}
              note={note_at_column(@entries, string_number, column)}
              bar_line={last_column_of_entry?(@entries, column)}
              tint={column_tint(@chorded_spans, column)}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :plan_item, :map, required: true
  attr :capo_fret, :integer, required: true
  attr :variant, :string, default: ""

  defp segment_bracket(assigns) do
    column = assigns.entry.offset + assigns.plan_item.local_start + 2
    span = assigns.plan_item.padded_span

    assigns =
      assigns
      |> assign(:segment, assigns.plan_item.segment)
      |> assign(:style, "grid-column: #{column} / span #{span};")

    ~H"""
    <div
      id={dom_id("segment", @variant, @segment.id)}
      style={@style}
      class={[
        "flex items-end pb-1 border-b-2",
        @segment.status == :suggested && "border-base-content/50",
        @segment.status == :no_match && "border-dashed border-base-content/25"
      ]}
    >
      <.chord_chip
        :if={@segment.status == :suggested}
        segment={@segment}
        capo_fret={@capo_fret}
        variant={@variant}
      />

      <span
        :if={@segment.status == :no_match}
        class="no-match-chip text-xs italic text-base-content/50 px-2 py-1"
      >
        sem sugestão
      </span>
    </div>
    """
  end

  attr :segment, :map, required: true
  attr :capo_fret, :integer, required: true
  attr :variant, :string, default: ""

  # Every `:suggested` segment shows its diagram, name and rank line —
  # always, regardless of how narrow its own column span is (explicit
  # product requirement: every chord chip above the tablature shows its
  # diagram, even one that repeats a chord already drawn elsewhere in the
  # same tab). A segment narrower than the chip's natural width (diagram +
  # name + rank line, roughly `@chip_min_columns` columns) visually
  # extends past its own grid area — `build_column_plan/1`'s per-segment
  # padding absorbs the common cases, and for a still-too-narrow interior
  # segment (a short chord sandwiched between two others in the same
  # compasso) the opaque `chord-chip` background is what keeps that
  # overflow legible rather than letting it interleave with whatever sits
  # next to it, the same trade-off already accepted for `:no_match`'s "sem
  # sugestão" label.
  defp chord_chip(assigns) do
    suggestion = displayed_suggestion(assigns.segment)
    assigns = assign(assigns, :suggestion, suggestion)

    ~H"""
    <div
      :if={@suggestion}
      class="chord-chip flex items-center gap-2 bg-base-200 border border-base-300 rounded px-2 py-1 leading-tight"
    >
      <ChordDiagramComponent.chord_diagram
        id={dom_id("chord-diagram", @variant, @segment.id)}
        chord_shape={@suggestion.chord_shape}
        base_fret={@suggestion.base_fret}
        class="text-base-content/80 shrink-0"
      />

      <div class="flex flex-col">
        <span class="font-semibold text-sm">{chord_name(@suggestion, @capo_fret)}</span>
        <span class="text-[11px] text-base-content/60">
          {@suggestion.rank} de {length(@segment.chord_suggestions)} sugestões
        </span>
      </div>
    </div>
    """
  end

  attr :note, :map, default: nil
  attr :bar_line, :boolean, default: false
  attr :tint, :string, default: nil

  defp note_cell(assigns) do
    ~H"""
    <div class={[
      "relative h-full border-b border-base-300",
      @bar_line && "border-r-2 border-r-base-content/30",
      @tint == "a" && "bg-primary/10",
      @tint == "b" && "bg-base-content/5"
    ]}>
      <span :if={@note} class="absolute inset-0 flex items-center justify-center">
        <span class="flex items-center justify-center w-5 h-5 rounded-full bg-primary text-primary-content text-xs font-bold">
          {@note.fret_number}
        </span>
      </span>
    </div>
    """
  end

  # One `%{measure:, column_count:, offset:, column_plan:}` per measure in
  # the row — `offset` the running sum of every earlier entry's own
  # `column_count` (column 1 is always the label gutter, so an entry's own
  # first column is `offset + 2`). `column_count` is the sum of its own
  # `column_plan`'s `padded_span`s (never 0 — see `build_column_plan/1`).
  defp build_entries(measures) do
    {entries, _next_offset} =
      Enum.map_reduce(measures, 0, fn measure, offset ->
        column_plan = build_column_plan(measure)
        column_count = column_plan |> List.last() |> then(&(&1.local_start + &1.padded_span))

        entry = %{
          measure: measure,
          column_count: column_count,
          offset: offset,
          column_plan: column_plan
        }

        {entry, offset + column_count}
      end)

    entries
  end

  # One `%{segment:, local_start:, real_span:, padded_span:}` per segment
  # of the measure (position-sorted), `local_start` the running sum of
  # every earlier plan item's own `padded_span` (column 0 of the plan is
  # the measure's own first note column, before `build_entries/1` adds the
  # row-wide `offset` + the label gutter). `padded_span` is `real_span`
  # (`end_position - start_position + 1`) for a `:no_match` segment — a
  # passing note doesn't need extra room — but for a `:suggested` one it's
  # at least `@chip_min_columns`, *regardless of the segment's position
  # within the measure*: every chord's own diagram + name + rank chip
  # gets that room, not just a measure-ending chord borrowing unused
  # trailing space (issue with the earlier design — an interior chord in a
  # multi-chord compasso had nowhere to grow and either dropped its
  # diagram or spilled into its neighbor). The gap between `real_span` and
  # `padded_span` renders as empty note cells after that segment's real
  # notes (`note_at_column/3`) — never stolen from a different segment's
  # own columns.
  #
  # A measure with no `chord_segments` yet (never analyzed) falls back to
  # one column per real note (or one reserved column for a genuinely empty
  # measure) — nothing to pad without a `:suggested` segment to pad it for.
  defp build_column_plan(%{chord_segments: []} = measure) do
    span = max(length(measure.notes), 1)
    [%{segment: nil, local_start: 0, real_span: span, padded_span: span}]
  end

  defp build_column_plan(measure) do
    {plan, _next_local_start} =
      measure.chord_segments
      |> Enum.sort_by(& &1.start_position)
      |> Enum.map_reduce(0, fn segment, local_start ->
        real_span = segment.end_position - segment.start_position + 1

        padded_span =
          if segment.status == :suggested, do: max(real_span, @chip_min_columns), else: real_span

        item = %{
          segment: segment,
          local_start: local_start,
          real_span: real_span,
          padded_span: padded_span
        }

        {item, local_start + padded_span}
      end)

    plan
  end

  # Every `{entry, plan_item}` pair whose `plan_item.segment` is real (the
  # `build_column_plan/1` not-yet-analyzed fallback's `segment: nil` entry
  # excluded — there's no bracket/chip to render for it).
  defp entry_segments(entries) do
    for entry <- entries, plan_item <- entry.column_plan, plan_item.segment do
      {entry, plan_item}
    end
  end

  # One `%{start_column:, end_column:, tint:}` per `:suggested` segment in
  # the row (in playing order, `:no_match` ones excluded — a passing note
  # isn't a hand position to shade), alternating `"a"`/`"b"` so two
  # consecutive chords always render in visibly different tints even when
  # they're in different compassos of the same row. `note_cell`'s
  # background is this hand-position cue (see this module's moduledoc
  # "Which notes share a hand position"): every note under the same tint
  # is playable without moving up/down the braço, and the tint change is
  # exactly where the hand has to move for the next chord.
  defp chorded_spans(segments) do
    segments
    |> Enum.filter(fn {_entry, plan_item} -> plan_item.segment.status == :suggested end)
    |> Enum.with_index()
    |> Enum.map(fn {{entry, plan_item}, index} ->
      start_column = entry.offset + plan_item.local_start

      %{
        start_column: start_column,
        end_column: start_column + plan_item.padded_span - 1,
        tint: if(rem(index, 2) == 0, do: "a", else: "b")
      }
    end)
  end

  defp column_tint(chorded_spans, column) do
    Enum.find_value(chorded_spans, fn %{start_column: s, end_column: e, tint: tint} ->
      column >= s and column <= e and tint
    end)
  end

  # Maps a global column back to a real `Note` (or `nil`, for a column
  # that's either genuinely between notes — impossible within a segment's
  # own `real_span` — or one of `build_column_plan/1`'s padding columns
  # past a `:suggested` segment's real notes).
  defp note_at_column(entries, string_number, column) do
    with %{measure: measure, offset: offset, column_plan: plan} <-
           entry_at_column(entries, column),
         local_column = column - offset,
         %{local_start: local_start} = plan_item <- plan_item_at(plan, local_column),
         real_position when not is_nil(real_position) <-
           real_position_for(plan_item.segment, local_start, local_column) do
      Enum.find(measure.notes, fn note ->
        note.string_number == string_number and note.position == real_position
      end)
    else
      _ -> nil
    end
  end

  defp plan_item_at(plan, local_column) do
    Enum.find(plan, fn %{local_start: s, padded_span: span} ->
      local_column >= s and local_column < s + span
    end)
  end

  # `segment: nil` is the not-yet-analyzed fallback plan item (see
  # `build_column_plan/1`) — a straight 1-to-1 mapping, no padding to skip
  # past. Otherwise, a column past the segment's own `real_span` (i.e.
  # past its last real note) is padding, not a note.
  defp real_position_for(nil, _local_start, local_column), do: local_column

  defp real_position_for(segment, local_start, local_column) do
    real_position = segment.start_position + (local_column - local_start)
    if real_position <= segment.end_position, do: real_position
  end

  defp last_column_of_entry?(entries, column) do
    case entry_at_column(entries, column) do
      %{offset: offset, column_count: column_count} -> column == offset + column_count - 1
      nil -> false
    end
  end

  defp entry_at_column(entries, column) do
    Enum.find(entries, fn %{offset: offset, column_count: column_count} ->
      column >= offset and column < offset + column_count
    end)
  end

  defp string_label(string_number), do: Map.fetch!(@string_labels, string_number)

  # `variant` (see `study_row/1`'s own attr doc) is folded into every id
  # this component emits so the *same* measure/segment rendered more than
  # once on one page (`TabLive.Study`'s one-row-set-per-breakpoint markup)
  # never collides — `""` (the default, every direct `study_row/1` call in
  # `StudyMeasureComponentTest`) keeps the id exactly as it was before
  # `variant` existed.
  defp dom_id(prefix, "", id), do: "#{prefix}-#{id}"
  defp dom_id(prefix, variant, id), do: "#{prefix}-#{variant}-#{id}"

  # The suggestion actually shown for a `:suggested` segment: the user's
  # own pick (issue #21's `selected_suggestion`) when there is one, else
  # the rank-1 candidate — `ChordSegment.select_chord_suggestion`'s own
  # documented default. `chord_suggestions` is loaded sorted by `rank`
  # ascending by the caller (`TabLive.Study`), so the first entry is
  # always rank 1.
  defp displayed_suggestion(%{selected_suggestion: %Ponteio.Tablatures.ChordSuggestion{} = s}),
    do: s

  defp displayed_suggestion(%{chord_suggestions: [first | _]}), do: first
  defp displayed_suggestion(%{chord_suggestions: []}), do: nil

  # Full display label (ex.: "Mi Maior") — the fundamental note name
  # (`Ponteio.Chords.root_note_name/3`, capo-aware) composed with the
  # chord shape's own quality label, per `ChordShape.name`'s own
  # moduledoc example of the composed form.
  defp chord_name(suggestion, capo_fret) do
    root = Chords.root_note_name(suggestion.chord_shape, suggestion.base_fret, capo_fret)

    "#{root} #{suggestion.chord_shape.name}"
  end
end
