defmodule PonteioWeb.TabLive.ChordDiagramComponent do
  @moduledoc """
  Renders one chord diagram (desenho do braço do violão) from a
  `Ponteio.Chords.ChordShape` applied at a given `base_fret` (issue #23,
  "Exibir diagrama do acorde sugerido"; PRD §6.5; SDD §4).

  Plain `Phoenix.Component` function component — same rationale as
  `MeasureEditorComponent`/`StudyMeasureComponent` (no isolated state to
  keep; the caller owns the assigns) — with the exact input contract SDD
  §4 sketches for `ChordDiagramComponent`:

      attr :chord_shape, ChordShape, required: true   # relative_frets, root_string, movable
      attr :base_fret, :integer, required: true        # posição no braço onde o shape foi aplicado

  ## Reading `relative_frets` (this issue's acceptance criteria)

  For each of the six strings (`chord_shape.relative_frets`, ordered high
  e (string 1) .. low E (string 6), same convention as
  `Ponteio.Chords.ChordShape.relative_frets`/`Ponteio.Tablatures.Note.string_number`):

    - `nil` → the string is muted/not used by the shape — drawn as an "X"
      above the diagram (this issue's own suggested marking).
    - `0` while `base_fret == 0` → the string rings **open** — drawn as an
      "O" above the diagram, not a dot inside the grid (there is no fret
      to press).
    - anything else → a pressed fret, drawn as a dot. The dot's *row*
      inside the diagram is relative to whichever window the diagram is
      showing: with `base_fret == 0` the window starts at the real nut,
      so row `N` is real fret `N`; with `base_fret > 0` (a barre shape
      applied up the neck) the window starts at `base_fret` itself, so
      `relative_fret == 0` is *already* a pressed fret (the barre) drawn
      in the window's first row rather than treated as open — row `N` is
      real fret `base_fret + N`. A small "‹base_fret›ª" label to the left
      of the first row disambiguates that case from an open-position
      diagram, since the dot pattern alone can't tell the two apart (SDD
      §2.3's `relative_frets` are already offsets *relative to*
      `base_fret` — the diagram never needs to add `base_fret` back in to
      decide *where* to draw a dot, only *whether* to also print the
      neck-position label).

  The number of fret rows shown is computed per diagram — at least 3, for
  a visually consistent minimum size, otherwise the highest row any
  string actually needs (a catalog shape can need more: the seeded
  diminished-7th barre shape needs 5).

  ## Layout convention

  Strings run left (string 6, low E) to right (string 1, high e) — the
  universal printed chord-chart convention (thickest string on the left)
  — the mirror image of `StudyMeasureComponent`'s tab grid, which instead
  runs top (string 1) to bottom (string 6) to match how a tab is read.
  These are two different, both standard, conventions for two different
  kinds of diagram; there is no inconsistency in using each on its own
  terms.

  Every meaningful mark (`X`/`O` letters, fretted dots, the base-fret
  label) carries `data-marker`/`data-string`/`data-row` attributes so
  tests can assert on them without depending on exact SVG geometry.
  """

  use PonteioWeb, :html

  alias Ponteio.Chords.ChordShape

  # Left-to-right column order (see moduledoc "Layout convention").
  @string_order [6, 5, 4, 3, 2, 1]

  @string_gap 18
  @pad_left 16
  @pad_right 10
  @pad_top 18
  @pad_bottom 8
  @row_height 18
  @min_rows 3
  @dot_radius 5

  attr :chord_shape, ChordShape, required: true
  attr :base_fret, :integer, required: true
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  def chord_diagram(assigns) do
    geometry = build_geometry(assigns.chord_shape, assigns.base_fret)

    assigns =
      assigns
      |> assign(:geometry, geometry)
      |> assign(:label, diagram_label(assigns.chord_shape, assigns.base_fret))

    ~H"""
    <svg
      id={@id}
      class={["chord-diagram", @class]}
      viewBox={"0 0 #{@geometry.svg_width} #{@geometry.svg_height}"}
      width={@geometry.svg_width}
      height={@geometry.svg_height}
      role="img"
      aria-label={@label}
    >
      <g>
        <line
          :for={line <- @geometry.fret_lines}
          x1={@geometry.pad_left}
          x2={@geometry.pad_left + @geometry.grid_width}
          y1={line.y}
          y2={line.y}
          stroke="currentColor"
          stroke-opacity={if line.nut?, do: "0.9", else: "0.35"}
          stroke-width={if line.nut?, do: "3", else: "1"}
        />

        <line
          :for={string_line <- @geometry.string_lines}
          x1={string_line.x}
          x2={string_line.x}
          y1={@geometry.pad_top}
          y2={@geometry.grid_bottom}
          stroke="currentColor"
          stroke-opacity="0.35"
          stroke-width="1"
        />

        <text
          :if={@base_fret > 0}
          x={@geometry.base_fret_label_x}
          y={@geometry.base_fret_label_y}
          text-anchor="end"
          font-size="9"
          fill="currentColor"
          data-marker="base-fret"
        >
          {@base_fret}ª
        </text>

        <text
          :for={marker <- @geometry.letter_markers}
          x={marker.x}
          y={marker.y}
          text-anchor="middle"
          font-size="10"
          font-weight="700"
          fill="currentColor"
          data-string={marker.string}
          data-marker={marker.kind}
        >
          {marker.label}
        </text>

        <circle
          :for={marker <- @geometry.dot_markers}
          cx={marker.x}
          cy={marker.y}
          r={@geometry.dot_radius}
          fill="currentColor"
          data-string={marker.string}
          data-marker="fretted"
          data-row={marker.row}
        />
      </g>
    </svg>
    """
  end

  # All the pixel geometry for one diagram, precomputed so the template
  # above only ever reads plain fields off `assigns.geometry` — module
  # attributes (`@pad_left` and friends) are ordinary Elixir here, safe to
  # use freely, unlike inside the `~H` sigil above where `@foo` means
  # `assigns.foo`, not the module attribute of the same name.
  defp build_geometry(chord_shape, base_fret) do
    markers = build_markers(chord_shape, base_fret)
    fret_rows = fret_rows(markers)
    grid_width = (length(@string_order) - 1) * @string_gap
    grid_bottom = @pad_top + fret_rows * @row_height

    string_lines =
      for {_string, column} <- Enum.with_index(@string_order),
          do: %{x: @pad_left + column * @string_gap}

    fret_lines =
      for row <- 0..fret_rows,
          do: %{y: @pad_top + row * @row_height, nut?: row == 0 and base_fret == 0}

    letter_markers =
      markers
      |> Enum.filter(&(&1.kind in [:muted, :open]))
      |> Enum.map(fn marker ->
        %{
          string: marker.string,
          kind: marker.kind,
          label: if(marker.kind == :muted, do: "X", else: "O"),
          x: @pad_left + marker.column * @string_gap,
          y: @pad_top - 6
        }
      end)

    dot_markers =
      markers
      |> Enum.filter(&(&1.kind == :fretted))
      |> Enum.map(fn marker ->
        %{
          string: marker.string,
          row: marker.row,
          x: @pad_left + marker.column * @string_gap,
          y: @pad_top + (marker.row - 0.5) * @row_height
        }
      end)

    %{
      svg_width: @pad_left + grid_width + @pad_right,
      svg_height: grid_bottom + @pad_bottom,
      grid_width: grid_width,
      grid_bottom: grid_bottom,
      pad_left: @pad_left,
      pad_top: @pad_top,
      dot_radius: @dot_radius,
      string_lines: string_lines,
      fret_lines: fret_lines,
      letter_markers: letter_markers,
      dot_markers: dot_markers,
      base_fret_label_x: @pad_left - 6,
      base_fret_label_y: @pad_top + @row_height / 2 + 3
    }
  end

  # Builds one marker per string (left-to-right column order — see
  # moduledoc "Layout convention"): `%{string:, column:, kind:, row:}`,
  # `row` only set for `kind == :fretted` (`nil` otherwise).
  defp build_markers(chord_shape, base_fret) do
    @string_order
    |> Enum.with_index()
    |> Enum.map(fn {string_number, column} ->
      relative_fret = Enum.at(chord_shape.relative_frets, string_number - 1)
      {kind, row} = marker_kind(relative_fret, base_fret)

      %{string: string_number, column: column, kind: kind, row: row}
    end)
  end

  defp marker_kind(nil, _base_fret), do: {:muted, nil}
  defp marker_kind(0, 0), do: {:open, nil}
  defp marker_kind(relative_fret, 0), do: {:fretted, relative_fret}

  defp marker_kind(relative_fret, base_fret) when base_fret > 0,
    do: {:fretted, relative_fret + 1}

  # At least `@min_rows`, for a consistent minimum visual size across
  # every diagram; otherwise the highest row any string actually needs.
  defp fret_rows(markers) do
    markers
    |> Enum.map(& &1.row)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> 0 end)
    |> max(@min_rows)
  end

  defp diagram_label(chord_shape, base_fret) do
    position = if base_fret == 0, do: "posição aberta", else: "#{base_fret}ª casa"
    "Diagrama do acorde #{chord_shape.name}, #{position}"
  end
end
