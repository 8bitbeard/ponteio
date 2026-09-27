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

  # Holding full shapes (:chord): Em (complexity 2.0) plays 5:2 and 2:0; A (3.0)
  # plays 3:2 but neither of those; the harder H (3.5) plays 2:0 and 3:2 but not
  # 5:2. With liftable fingers (:hand), A can also play 2:0 (lifting its B finger).
  defp fixture_index(mode) do
    Index.build(
      [
        position(0, "Em", [0, 2, 2, 0, 0, 0], [0, 2, 3, 0, 0, 0]),
        position(1, "A", [-1, 0, 2, 2, 2, 0], [0, 0, 1, 2, 3, 0]),
        position(2, "H", [3, -1, 2, 2, 0, 3], [2, 0, 1, 1, 0, 3])
      ],
      mode
    )
  end

  defp notes(pairs) do
    pairs
    |> Enum.with_index()
    |> Enum.map(fn {{string, fret}, position} ->
      %{string: string, fret: fret, position: position}
    end)
  end

  defp analyze(pairs, opts \\ []) do
    {mode, opts} = Keyword.pop(opts, :mode, :chord)
    MeasureAnalyzer.analyze(notes(pairs), Keyword.put_new(opts, :index, fixture_index(mode)))
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

  test "in :hand mode a lifted finger makes the easier position fit another split" do
    combinations = analyze([{5, 2}, {2, 0}, {3, 2}], mode: :hand)

    assert Enum.map(combinations, &shape/1) == [
             [{0, 0, :chorded, ["Em"]}, {1, 2, :chorded, ["A", "H"]}],
             [{0, 1, :chorded, ["Em"]}, {2, 2, :chorded, ["A", "H"]}]
           ]

    assert Enum.map(combinations, & &1.total_complexity) == [5.0, 5.0]
  end

  test "caps how many tied splits are returned" do
    assert [only] = analyze([{5, 2}, {2, 0}, {3, 2}], max_combinations: 1)
    assert only.total_complexity == 5.0
  end

  test "accepts notes in any order, analyzing them by position" do
    shuffled = notes([{5, 2}, {5, 2}, {3, 2}]) |> Enum.reverse()

    assert [combination] = MeasureAnalyzer.analyze(shuffled, index: fixture_index(:chord))
    assert [{0, 1, _, _}, {2, 2, _, _}] = shape(combination)
  end

  describe "analyze_all/2" do
    # Notes as they come from the database: their own ids, positions not
    # starting at zero, in any order.
    defp db_notes(pairs, first_id) do
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {{string, fret}, i} ->
        %{id: first_id + i, string: string, fret: fret, position: 10 + i}
      end)
      |> Enum.reverse()
    end

    test "gives each measure the same result as analyzing it alone" do
      riff = [{5, 2}, {2, 0}, {3, 2}]

      measures = [
        db_notes(riff, 100),
        db_notes([{5, 2}, {5, 2}, {3, 2}], 200),
        db_notes(riff, 300),
        []
      ]

      for mode <- [:hand, :chord] do
        opts = [index: fixture_index(mode)]

        assert MeasureAnalyzer.analyze_all(measures, opts) ==
                 Enum.map(measures, &MeasureAnalyzer.analyze(&1, opts))
      end
    end

    test "repeated measures point at their own notes" do
      [first, second] =
        MeasureAnalyzer.analyze_all(
          [db_notes([{5, 2}, {2, 0}, {3, 2}], 100), db_notes([{5, 2}, {2, 0}, {3, 2}], 300)],
          index: fixture_index(:chord)
        )

      ids = fn result -> for c <- result, s <- c.segments, n <- s.notes, do: n.id end

      assert Enum.uniq(ids.(first)) |> Enum.sort() == [100, 101, 102]
      assert Enum.uniq(ids.(second)) |> Enum.sort() == [300, 301, 302]
    end
  end

  describe "with the real chord catalog" do
    # First measure of "Radical Dreamers" (Chrono Cross): holding full chord
    # shapes it takes a G add9 shape and then A sus2; letting fingers lift, the
    # hand never moves (E3 and G2 stay down, only a D-string finger comes and goes).
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

    test "in :hand mode the first measure needs a single hand position" do
      assert [%{segments: [segment], notes_covered: 14} | _] =
               MeasureAnalyzer.analyze(notes(@radical_dreamer))

      assert {segment.start_position, segment.end_position} == {0, 13}
    end

    test "in :chord mode the first measure needs two chord shapes" do
      [easiest | _] =
        combinations = MeasureAnalyzer.analyze(notes(@radical_dreamer), mode: :chord)

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
