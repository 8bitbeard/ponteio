defmodule Ponteio.Chords.MeasureAnalyzerTest do
  use ExUnit.Case, async: true

  alias Ponteio.Chords.Complexity
  alias Ponteio.Chords.HandPosition
  alias Ponteio.Chords.Index
  alias Ponteio.Chords.MeasureAnalyzer

  defp position(id, name, frets, fingers) do
    position =
      HandPosition.from_chords_db(id, name, "", %{
        "frets" => frets,
        "fingers" => fingers,
        "baseFret" => 1,
        "barres" => []
      })

    %{position | complexity: Complexity.score(position)}
  end

  # Em (complexity 2.0) plays 5:2 and 2:0; A (3.0) plays 3:2 but neither of
  # those; the harder H (3.5) plays 2:0 and 3:2 but not 5:2.
  defp fixture_index do
    Index.build([
      position(0, "Em", [0, 2, 2, 0, 0, 0], [0, 2, 3, 0, 0, 0]),
      position(1, "A", [-1, 0, 2, 2, 2, 0], [0, 0, 1, 2, 3, 0]),
      position(2, "H", [3, -1, 2, 2, 0, 3], [2, 0, 1, 1, 0, 3])
    ])
  end

  defp notes(pairs) do
    pairs
    |> Enum.with_index()
    |> Enum.map(fn {{string, fret}, position} ->
      %{string: string, fret: fret, position: position}
    end)
  end

  defp analyze(pairs, opts \\ []) do
    MeasureAnalyzer.analyze(notes(pairs), Keyword.put_new(opts, :index, fixture_index()))
  end

  defp shape(combination) do
    Enum.map(combination.segments, fn segment ->
      {segment.start_position, segment.end_position, segment.status,
       Enum.map(segment.candidates, & &1.key)}
    end)
  end

  test "an empty measure has no combinations" do
    assert analyze([]) == []
  end

  test "notes that fit one hand position form a single segment" do
    assert [combination] = analyze([{5, 2}, {4, 2}, {1, 0}])

    assert shape(combination) == [{0, 2, :chorded, ["Em"]}]
    assert combination.notes_covered == 3
  end

  test "a note no position can play becomes its own uncovered segment" do
    assert [combination] = analyze([{5, 2}, {1, 7}, {4, 2}])

    assert [{0, 0, :chorded, _}, {1, 1, :no_match, []}, {2, 2, :chorded, _}] = shape(combination)
    assert combination.notes_covered == 2
  end

  test "moves the hand only when the next note does not fit the current position" do
    assert [combination] = analyze([{5, 2}, {5, 2}, {3, 2}])

    assert [{0, 1, :chorded, ["Em"]}, {2, 2, :chorded, ["A", "H"]}] = shape(combination)
  end

  test "returns every split with the fewest segments, easiest first" do
    combinations = analyze([{5, 2}, {2, 0}, {3, 2}])

    assert Enum.map(combinations, &shape/1) == [
             [{0, 1, :chorded, ["Em"]}, {2, 2, :chorded, ["A", "H"]}],
             [{0, 0, :chorded, ["Em"]}, {1, 2, :chorded, ["H"]}]
           ]

    assert Enum.map(combinations, & &1.total_complexity) == [5.0, 5.5]
  end

  test "caps how many tied splits are returned" do
    assert [only] = analyze([{5, 2}, {2, 0}, {3, 2}], max_combinations: 1)
    assert only.total_complexity == 5.0
  end

  test "accepts notes in any order, analyzing them by position" do
    shuffled = notes([{5, 2}, {5, 2}, {3, 2}]) |> Enum.reverse()

    assert [combination] = MeasureAnalyzer.analyze(shuffled, index: fixture_index())
    assert [{0, 1, _, _}, {2, 2, _, _}] = shape(combination)
  end

  describe "with the real chord catalog" do
    # First measure of "Radical Dreamer" (Chrono Cross): the whole measure is
    # playable with two hand positions, a G add9 shape and then A sus2.
    @radical_dreamer [
      {6, 3},
      {4, 0},
      {3, 2},
      {6, 3},
      {2, 0},
      {4, 0},
      {3, 2},
      {5, 0},
      {4, 2},
      {3, 2},
      {5, 0},
      {2, 0},
      {4, 2},
      {3, 2}
    ]

    test "Radical Dreamer's first measure needs only two hand positions" do
      [easiest | _] = combinations = MeasureAnalyzer.analyze(notes(@radical_dreamer))

      assert Enum.all?(combinations, &(length(&1.segments) == 2 and &1.notes_covered == 14))

      assert [
               {0, 5, :chorded, [{"G", "add9"} | _]},
               {6, 13, :chorded, [{"A", "sus2"} | _]}
             ] =
               Enum.map(easiest.segments, fn segment ->
                 {segment.start_position, segment.end_position, segment.status,
                  Enum.map(segment.candidates, &{&1.key, &1.suffix})}
               end)

      complexities = Enum.map(combinations, & &1.total_complexity)
      assert complexities == Enum.sort(complexities)
    end
  end
end
