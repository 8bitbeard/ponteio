defmodule PonteioWeb.TabLive.StudyMeasureComponent do
  @moduledoc """
  Renders one compasso, read-only, for `PonteioWeb.TabLive.Study` (issue
  #22, "Visualizar tablatura completa com acordes sobrepostos"; PRD §6.5;
  SDD §4, §7).

  This is a plain `Phoenix.Component` function component — same rationale
  as `PonteioWeb.TabLive.MeasureEditorComponent` (no isolated state to
  keep, `TabLive.Study` owns everything as assigns) — but read-only: there
  is no `phx-click`/editable cell here, since study mode is pure
  consumption (PRD §6.5 draws no editing affordance for it, unlike the
  editor).

  ## Grid shape

  Same 6-row string grid as `MeasureEditorComponent` (`e B G D A E`,
  string 1 = high e .. string 6 = low E), but sized to exactly
  `length(measure.notes)` columns — no trailing empty column, since
  nothing is ever inserted here. A measure with no notes renders a short
  placeholder message instead of an empty grid.

  ## The chord-chip overlay (this issue's actual new part)

  A `segment-row`-equivalent sits above the string grid, sharing the same
  `grid-template-columns` so its brackets line up over the exact note
  columns they cover — the same "shared grid template" trick
  `MeasureEditorComponent`'s control row uses for its scissors buttons.
  For each of the measure's `chord_segments` (already sorted by
  `start_position` by the caller — see `TabLive.Study`), one bracket
  spans `grid-column: (start_position + 2) / span (end_position -
  start_position + 1)` — `+ 2` because the grid's own first column is the
  1.5rem string-label gutter, and `Note.position` is 0-based, so note
  position 0 sits in grid-column 2.

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
  them). The chord diagram (`ChordDiagramComponent`) the mockup also shows
  inside the chip is explicitly issue #23's scope, not this one's.

  A `:no_match` segment's bracket shows a plain "sem sugestão" label
  instead (PRD §6.4 regra 4), dashed rather than solid to distinguish it
  visually from a resolved segment (mirrors the mockup's `.segment-bracket.muted`).
  """

  use PonteioWeb, :html

  alias Ponteio.Chords

  @strings 1..6
  @string_labels %{1 => "e", 2 => "B", 3 => "G", 4 => "D", 5 => "A", 6 => "E"}

  attr :measure, :map, required: true
  attr :capo_fret, :integer, required: true

  def study_measure(assigns) do
    assigns =
      assigns
      |> assign(:column_count, length(assigns.measure.notes))
      |> assign(:strings, @strings)

    ~H"""
    <div
      id={"study-measure-#{@measure.id}"}
      class="rounded-lg border border-base-300 bg-base-100 p-4 mb-4"
    >
      <div class="mb-3">
        <span class="text-sm font-semibold text-base-content/70">
          Compasso {@measure.position}
        </span>
      </div>

      <div :if={@column_count > 0} class="flex flex-col gap-1">
        <div
          class="grid items-end h-16"
          style={"grid-template-columns: 1.5rem repeat(#{@column_count}, 2.5rem);"}
        >
          <span></span>

          <.segment_bracket
            :for={segment <- @measure.chord_segments}
            segment={segment}
            capo_fret={@capo_fret}
          />
        </div>

        <div
          :for={string_number <- @strings}
          class="grid items-center h-7"
          style={"grid-template-columns: 1.5rem repeat(#{@column_count}, 2.5rem);"}
        >
          <span class="text-xs font-semibold text-base-content/60">
            {string_label(string_number)}
          </span>

          <.note_cell
            :for={column <- 0..(@column_count - 1)}
            note={note_at(@measure, string_number, column)}
          />
        </div>
      </div>

      <p :if={@column_count == 0} class="text-sm text-base-content/50 italic">
        Compasso sem notas.
      </p>
    </div>
    """
  end

  attr :segment, :map, required: true
  attr :capo_fret, :integer, required: true

  defp segment_bracket(assigns) do
    span = assigns.segment.end_position - assigns.segment.start_position + 1

    assigns =
      assign(
        assigns,
        :style,
        "grid-column: #{assigns.segment.start_position + 2} / span #{span};"
      )

    ~H"""
    <div
      id={"segment-#{@segment.id}"}
      style={@style}
      class={[
        "flex items-end pb-1 border-b-2",
        @segment.status == :suggested && "border-base-content/50",
        @segment.status == :no_match && "border-dashed border-base-content/25"
      ]}
    >
      <.chord_chip :if={@segment.status == :suggested} segment={@segment} capo_fret={@capo_fret} />

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

  defp chord_chip(assigns) do
    suggestion = displayed_suggestion(assigns.segment)
    assigns = assign(assigns, :suggestion, suggestion)

    ~H"""
    <div
      :if={@suggestion}
      class="chord-chip flex flex-col bg-base-200 border border-base-300 rounded px-2 py-1 leading-tight"
    >
      <span class="font-semibold text-sm">{chord_name(@suggestion, @capo_fret)}</span>
      <span class="text-[11px] text-base-content/60">
        {@suggestion.rank} de {length(@segment.chord_suggestions)} sugestões
      </span>
    </div>
    """
  end

  attr :note, :map, default: nil

  defp note_cell(assigns) do
    ~H"""
    <div class="relative h-full border-b border-base-300">
      <span :if={@note} class="absolute inset-0 flex items-center justify-center">
        <span class="flex items-center justify-center w-5 h-5 rounded-full bg-primary text-primary-content text-xs font-bold">
          {@note.fret_number}
        </span>
      </span>
    </div>
    """
  end

  defp note_at(measure, string_number, column) do
    Enum.find(measure.notes, fn note ->
      note.string_number == string_number and note.position == column
    end)
  end

  defp string_label(string_number), do: Map.fetch!(@string_labels, string_number)

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
