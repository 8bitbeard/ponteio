defmodule PonteioWeb.TablatureComponents do
  @moduledoc """
  Renders a tab as sheet music: six string lines labelled on the left, the fret
  of each note on its string, and the measure's hand positions (the easiest
  split found by `Ponteio.Chords.MeasureAnalyzer`) as tinted regions with the
  chord diagram on top.
  """

  use Phoenix.Component

  alias Ponteio.Chords.HandPosition

  # Every line (system) holds this many measures, each taking an equal share of
  # the page width; a region grows with its note count inside its measure.
  @measures_per_system 2
  # Minimum pixel widths: below them a line scrolls sideways instead of
  # squeezing fret numbers or chord diagrams together.
  @note_width 20
  @region_padding 8
  @region_min_width 84
  @empty_measure_width 64
  @labels_width 20

  # String labels from the top line (1, high e) to the bottom one (6, low E).
  @string_labels %{1 => "e", 2 => "B", 3 => "G", 4 => "D", 5 => "A", 6 => "E"}

  attr :measures, :list, required: true
  attr :mode, :atom, required: true, values: [:hand, :chord]

  def tablature(assigns) do
    assigns =
      assign(assigns,
        systems: systems(assigns.measures, assigns.mode),
        measures_per_system: @measures_per_system
      )

    ~H"""
    <div id="tablature" class="space-y-6">
      <p :if={@measures == []} class="text-sm text-base-content/60">Nenhum compasso ainda.</p>
      <div :for={system <- @systems} class="overflow-x-auto pb-2">
        <div class="flex" style={"min-width: #{system.min_width}px"}>
          <.string_labels />
          <div class="self-end h-30 border-l-2 border-base-content/60"></div>
          <div
            class="flex-1 grid"
            style={"grid-template-columns: repeat(#{@measures_per_system}, minmax(0, 1fr))"}
          >
            <.tab_measure :for={measure <- system.measures} measure={measure} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp string_labels(assigns) do
    assigns = assign(assigns, :labels, @string_labels)

    ~H"""
    <div class="flex flex-col pr-1.5 font-mono text-xs text-base-content/70">
      <div class="h-39"></div>
      <div :for={string <- 1..6} class="h-5 flex items-center justify-end">
        {@labels[string]}
      </div>
    </div>
    """
  end

  attr :measure, :map, required: true

  defp tab_measure(assigns) do
    ~H"""
    <div id={"tab-measure-#{@measure.id}"} class="flex flex-col min-w-0">
      <div class="h-5 px-1 text-xs text-base-content/60">{@measure.number}</div>
      <div class="flex flex-1">
        <.region
          :for={{segment, index} <- Enum.with_index(@measure.segments)}
          id={"tab-segment-#{@measure.id}-#{index}"}
          segment={segment}
          variant={variant(segment, index)}
        />
        <div
          :if={@measure.segments == []}
          class="tab-region tab-region-empty relative flex-1 h-30 self-end"
        >
          <.staff_lines />
        </div>
        <div class="flex-none self-end h-30 border-r-2 border-base-content/60"></div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :segment, :map, required: true
  attr :variant, :string, required: true

  defp region(assigns) do
    assigns =
      assign(assigns,
        best: List.first(assigns.segment.candidates),
        note_count: length(assigns.segment.notes),
        min_width: region_width(assigns.segment)
      )

    ~H"""
    <div
      id={@id}
      class={["tab-region flex flex-col rounded-box transition-colors", @variant]}
      style={"flex: #{@note_count} 1 0%; min-width: #{@min_width}px"}
      title={region_title(@best)}
    >
      <div class="h-34 flex flex-col items-center pt-1">
        <%= if @best do %>
          <span class="text-sm font-semibold leading-5">{HandPosition.chord_name(@best)}</span>
          <.chord_diagram position={@best} />
        <% else %>
          <span class="text-sm font-semibold leading-5 text-warning">?</span>
          <span class="text-xs text-base-content/60">sem posição</span>
        <% end %>
      </div>
      <div class="relative h-30 flex justify-around px-1">
        <.staff_lines />
        <div :for={note <- @segment.notes} class="relative flex flex-col flex-1 min-w-5">
          <div :for={string <- 1..6} class="h-5 flex items-center justify-center">
            <span
              :if={string == note.string}
              class="px-0.5 font-mono text-sm font-semibold leading-none bg-(--region)"
            >
              {note.fret}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp staff_lines(assigns) do
    ~H"""
    <div class="absolute inset-0 flex flex-col pointer-events-none" aria-hidden="true">
      <%!-- The line is the bottom border of the row's top half: a whole-pixel
           offset, where a centered 1px line would sit at 9.5px and blur or
           vanish on scaled displays. --%>
      <div :for={_string <- 1..6} class="h-5">
        <div class="h-2.5 border-b border-base-content/50"></div>
      </div>
    </div>
    """
  end

  @string_gap 10
  @fret_gap 13
  @left 16
  @nut_y 14
  @min_frets 5
  @diagram_scale 1.1

  @doc """
  A chord box as chord sites draw it: strings vertical (low E on the left),
  frets horizontal, `×`/`○` above muted/open strings, dots with the finger
  number, barres as bars, and the first fret on the left when the shape is up
  the neck.
  """
  attr :position, HandPosition, required: true

  def chord_diagram(assigns) do
    position = assigns.position
    relative = &(&1 - position.base_fret + 1)

    max_relative =
      position.frets
      |> Map.values()
      |> Enum.filter(&(is_integer(&1) and &1 > 0))
      |> Enum.map(relative)
      |> Enum.max(fn -> 1 end)

    fret_count = max(@min_frets, max_relative)
    right = @left + 5 * @string_gap

    barres =
      Enum.map(position.barres, fn barre ->
        %{
          x: string_x(barre.to_string) - 4,
          width: string_x(barre.from_string) - string_x(barre.to_string) + 8,
          y: fret_y(relative.(barre.fret)) - 4,
          finger: position.fingers[barre.from_string]
        }
      end)

    dots =
      for {string, fret} <- position.frets,
          is_integer(fret) and fret > 0,
          not Enum.any?(position.barres, &under_barre?(&1, string, fret)) do
        %{x: string_x(string), y: fret_y(relative.(fret)), finger: position.fingers[string]}
      end

    markers =
      for {string, fret} <- position.frets, fret in [nil, 0] do
        %{x: string_x(string), symbol: if(fret == nil, do: "×", else: "○")}
      end

    assigns =
      assign(assigns,
        width: right + 8,
        height: @nut_y + fret_count * @fret_gap + 4,
        left: @left,
        right: right,
        fret_gap: @fret_gap,
        scale: @diagram_scale,
        nut_y: @nut_y,
        bottom: @nut_y + fret_count * @fret_gap,
        fret_lines: for(n <- 0..fret_count, do: @nut_y + n * @fret_gap),
        string_lines: for(string <- 6..1//-1, do: string_x(string)),
        barres: barres,
        dots: dots,
        markers: markers
      )

    ~H"""
    <svg
      viewBox={"0 0 #{@width} #{@height}"}
      width={@width * @scale}
      height={@height * @scale}
      class="shrink-0 text-base-content"
      role="img"
      aria-label={"#{HandPosition.chord_name(@position)} #{HandPosition.diagram(@position)}"}
    >
      <line
        :for={y <- @fret_lines}
        x1={@left}
        x2={@right}
        y1={y}
        y2={y}
        stroke="currentColor"
        stroke-opacity="0.5"
      />
      <line
        :for={x <- @string_lines}
        x1={x}
        x2={x}
        y1={@nut_y}
        y2={@bottom}
        stroke="currentColor"
        stroke-opacity="0.7"
      />
      <line
        :if={@position.base_fret == 1}
        x1={@left - 0.5}
        x2={@right + 0.5}
        y1={@nut_y}
        y2={@nut_y}
        stroke="currentColor"
        stroke-width="3"
      />
      <text
        :if={@position.base_fret > 1}
        x={@left - 4}
        y={@nut_y + @fret_gap / 2 + 3}
        text-anchor="end"
        font-size="8"
        fill="currentColor"
      >
        {@position.base_fret}
      </text>
      <text
        :for={marker <- @markers}
        x={marker.x}
        y={@nut_y - 4}
        text-anchor="middle"
        font-size="8"
        fill="currentColor"
      >
        {marker.symbol}
      </text>
      <g :for={barre <- @barres}>
        <rect x={barre.x} y={barre.y} width={barre.width} height="8" rx="4" fill="currentColor" />
      </g>
      <g :for={dot <- @dots}>
        <circle cx={dot.x} cy={dot.y} r="4.5" fill="currentColor" />
        <text
          :if={dot.finger && dot.finger > 0}
          x={dot.x}
          y={dot.y + 2.5}
          text-anchor="middle"
          font-size="7"
          class="fill-base-100"
        >
          {dot.finger}
        </text>
      </g>
    </svg>
    """
  end

  defp string_x(string), do: @left + (6 - string) * @string_gap
  defp fret_y(relative_fret), do: @nut_y + (relative_fret - 0.5) * @fret_gap

  defp under_barre?(barre, string, fret) do
    barre.fret == fret and barre.from_string <= string and string <= barre.to_string
  end

  defp variant(%{status: :no_match}, _index), do: "tab-region-miss"
  defp variant(_segment, index) when rem(index, 2) == 0, do: "tab-region-a"
  defp variant(_segment, _index), do: "tab-region-b"

  defp region_title(nil), do: "Nenhuma posição de mão toca estas notas"

  defp region_title(best) do
    "#{HandPosition.chord_name(best)} (#{HandPosition.diagram(best)}), complexidade #{best.complexity}"
  end

  # Picks each measure's easiest split in the given mode and groups the measures
  # into lines of `@measures_per_system`. Every measure takes the same width, so
  # every line gets the same minimum width: the widest measure of the whole tab
  # times the measure count.
  defp systems(measures, mode) do
    layouts = Enum.map(measures, &measure_layout(&1, mode))
    widest = layouts |> Enum.map(& &1.width) |> Enum.max(fn -> 0 end)
    min_width = @labels_width + widest * @measures_per_system

    layouts
    |> Enum.chunk_every(@measures_per_system)
    |> Enum.map(&%{measures: &1, min_width: min_width})
  end

  defp measure_layout(measure, mode) do
    combinations = if mode == :hand, do: measure.hand_positions, else: measure.chord_positions

    segments =
      case combinations do
        [best | _] -> best.segments
        [] -> []
      end

    %{
      id: measure.id,
      number: measure.position + 1,
      segments: segments,
      width: measure_width(segments)
    }
  end

  defp measure_width([]), do: @empty_measure_width

  defp measure_width(segments) do
    segments |> Enum.map(&region_width/1) |> Enum.sum()
  end

  defp region_width(segment),
    do: max(length(segment.notes) * @note_width + @region_padding, @region_min_width)
end
