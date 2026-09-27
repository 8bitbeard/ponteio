defmodule Ponteio.Chords.MeasureAnalyzer do
  @moduledoc """
  Splits one measure's notes (in playing order) into contiguous segments, each
  played from a single hand position, choosing the split by, in order of priority:

    1. the most notes covered by some hand position (a note no position can play,
       even alone, becomes a one-note `:no_match` segment);
    2. the fewest segments, i.e. the fewest hand movements;
    3. the lowest total complexity (sum of each segment's easiest candidate).

  Every split tied on (2) is a valid answer; up to `:max_combinations` of them are
  returned, easiest first.

  Criterion (1) needs no search: a note inside a segment is playable from that
  segment's position, so it is playable alone too. The only uncovered notes are
  the ones no position can play even alone, and they are uncovered in every
  split, so any split is already maximal in coverage.

  Criterion (2) is solved by a dynamic program over prefixes. For each prefix it
  also keeps the `:max_combinations` cheapest partial splits reaching the optimum;
  since complexity adds up segment by segment, that yields exactly the cheapest
  complete splits without enumerating every tied one.
  """

  alias Ponteio.Chords.Catalog
  alias Ponteio.Chords.Matcher

  defmodule Segment do
    @moduledoc "A run of consecutive notes played from one hand position."

    @type t :: %__MODULE__{
            start_position: non_neg_integer(),
            end_position: non_neg_integer(),
            notes: [map()],
            status: :chorded | :no_match,
            candidates: [Ponteio.Chords.HandPosition.t()]
          }

    defstruct [:start_position, :end_position, :notes, :status, candidates: []]
  end

  defmodule Combination do
    @moduledoc "One complete split of a measure into segments."

    @type t :: %__MODULE__{
            segments: [Ponteio.Chords.MeasureAnalyzer.Segment.t()],
            notes_covered: non_neg_integer(),
            total_complexity: float()
          }

    defstruct [:segments, :notes_covered, :total_complexity]
  end

  @default_max_combinations 20

  @doc """
  Analyzes a measure. Each note is a map with `:string` (1 = high e .. 6 = low E),
  `:fret` (absolute, 0 = open) and `:position` (playing order).

  Options:

    * `:max_combinations` — how many tied splits to return (default #{@default_max_combinations});
    * `:index` — the catalog index to search (default `Ponteio.Chords.Catalog.index/0`).
  """
  @spec analyze([map()], keyword()) :: [Combination.t()]
  def analyze(notes, opts \\ [])

  def analyze([], _opts), do: []

  def analyze(notes, opts) do
    max_combinations = Keyword.get(opts, :max_combinations, @default_max_combinations)
    index = Keyword.get_lazy(opts, :index, &Catalog.index/0)

    notes = notes |> Enum.sort_by(& &1.position) |> List.to_tuple()
    count = tuple_size(notes)
    windows = matching_windows(notes, count, index)

    count
    |> solve(windows, max_combinations)
    |> Enum.map(fn {total_complexity, bounds} ->
      segments = bounds |> Enum.reverse() |> Enum.map(&to_segment(&1, notes, windows, index))

      %Combination{
        segments: segments,
        notes_covered:
          segments
          |> Enum.filter(&(&1.status == :chorded))
          |> Enum.map(&length(&1.notes))
          |> Enum.sum(),
        total_complexity: total_complexity
      }
    end)
  end

  # `{start, stop}` (stop exclusive) => {candidate ids, easiest candidate's
  # complexity}, only for windows with at least one candidate. Adding a note can
  # only shrink the candidate set, so each start stops growing at the first
  # empty window.
  defp matching_windows(notes, count, index) do
    for start <- 0..(count - 1), reduce: %{} do
      windows -> extend_window(windows, notes, count, index, start, start + 1, nil)
    end
  end

  defp extend_window(windows, _notes, count, _index, _start, stop, _ids) when stop > count,
    do: windows

  defp extend_window(windows, notes, count, index, start, stop, ids) do
    note_ids = Matcher.candidate_ids([elem(notes, stop - 1)], index)
    ids = if ids, do: MapSet.intersection(ids, note_ids), else: note_ids

    if MapSet.size(ids) == 0 do
      windows
    else
      easiest = ids |> Enum.map(&Map.fetch!(index.positions, &1).complexity) |> Enum.min()
      windows = Map.put(windows, {start, stop}, {ids, easiest})
      extend_window(windows, notes, count, index, start, stop + 1, ids)
    end
  end

  # `fewest` maps each prefix length to its minimum number of segments; `paths`
  # maps it to up to `max_combinations` cheapest splits reaching that minimum,
  # as {total complexity, bounds in reverse order}. Returns the complete splits.
  defp solve(count, windows, max_combinations) do
    {_fewest, paths} =
      Enum.reduce(1..count, {%{0 => 0}, %{0 => [{0.0, []}]}}, fn stop, {fewest, paths} ->
        transitions =
          for start <- 0..(stop - 1),
              transition = transition(windows, start, stop),
              transition != nil do
            {status, cost} = transition
            {start, status, cost, Map.fetch!(fewest, start) + 1}
          end

        minimum =
          transitions
          |> Enum.map(fn {_start, _status, _cost, segments} -> segments end)
          |> Enum.min()

        stop_paths =
          for {start, status, cost, ^minimum} <- transitions,
              {total, bounds} <- Map.fetch!(paths, start) do
            {total + cost, [{start, stop, status} | bounds]}
          end
          |> Enum.sort_by(fn {total, bounds} -> {total, Enum.reverse(bounds)} end)
          |> Enum.take(max_combinations)

        {Map.put(fewest, stop, minimum), Map.put(paths, stop, stop_paths)}
      end)

    Map.fetch!(paths, count)
  end

  defp transition(windows, start, stop) do
    case Map.fetch(windows, {start, stop}) do
      {:ok, {_ids, easiest}} -> {:chorded, easiest}
      :error when stop - start == 1 -> {:no_match, 0.0}
      :error -> nil
    end
  end

  defp to_segment({start, stop, status}, notes, windows, index) do
    segment_notes = for i <- start..(stop - 1), do: elem(notes, i)

    candidates =
      case status do
        :chorded ->
          {ids, _easiest} = Map.fetch!(windows, {start, stop})
          ids |> Enum.map(&Map.fetch!(index.positions, &1)) |> Matcher.sort_by_ease()

        :no_match ->
          []
      end

    %Segment{
      start_position: hd(segment_notes).position,
      end_position: List.last(segment_notes).position,
      notes: segment_notes,
      status: status,
      candidates: candidates
    }
  end
end
