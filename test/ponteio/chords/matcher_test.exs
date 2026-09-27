defmodule Ponteio.Chords.MatcherTest do
  use ExUnit.Case, async: true

  alias Ponteio.Chords.Catalog
  alias Ponteio.Chords.Matcher

  defp catalog_position(key, suffix, frets) do
    Enum.find(Catalog.all(), &(&1.key == key and &1.suffix == suffix and &1.frets == frets))
  end

  defp notes(pairs), do: Enum.map(pairs, fn {string, fret} -> %{string: string, fret: fret} end)

  defp d_major_open do
    catalog_position("D", "major", %{6 => nil, 5 => nil, 4 => 0, 3 => 2, 2 => 3, 1 => 2})
  end

  defp c_six_barre do
    catalog_position("C", "6", %{6 => 8, 5 => nil, 4 => 10, 3 => 9, 2 => 10, 1 => 8})
  end

  describe "in both modes" do
    for mode <- [:hand, :chord] do
      test "open notes on strings the chord mutes fit the hand position (#{mode})" do
        assert Matcher.matches?(
                 notes([{6, 0}, {5, 0}, {3, 2}, {1, 2}]),
                 d_major_open(),
                 unquote(mode)
               )
      end

      test "a fretted note on a string the chord mutes needs another finger (#{mode})" do
        refute Matcher.matches?(notes([{6, 2}, {3, 2}]), d_major_open(), unquote(mode))
      end

      test "a chord string is never played at another fretted fret (#{mode})" do
        refute Matcher.matches?(notes([{3, 4}]), d_major_open(), unquote(mode))
      end

      test "a muted string under the barre plays at the barre fret, never open (#{mode})" do
        assert Matcher.matches?(notes([{6, 8}, {5, 8}, {1, 8}]), c_six_barre(), unquote(mode))
        refute Matcher.matches?(notes([{5, 0}]), c_six_barre(), unquote(mode))
      end
    end
  end

  describe ":hand mode" do
    test "lifting a finger lets its string ring open" do
      assert Matcher.matches?(notes([{2, 0}, {3, 2}]), d_major_open(), :hand)
      refute Matcher.matches?(notes([{2, 0}, {3, 2}]), d_major_open(), :chord)
    end

    test "a string held by the barre cannot be lifted" do
      assert Matcher.matches?(notes([{4, 0}]), c_six_barre(), :hand)
      refute Matcher.matches?(notes([{6, 0}]), c_six_barre(), :hand)
    end
  end

  test "candidates include every matching position, easiest first" do
    candidates =
      Matcher.candidates(notes([{6, 0}, {5, 0}, {3, 2}, {1, 2}]), Catalog.index(:chord))

    assert d_major_open() in candidates

    assert Enum.map(candidates, & &1.complexity) ==
             Enum.sort(Enum.map(candidates, & &1.complexity))
  end

  test "the :hand index finds everything the :chord index finds, and more" do
    window = notes([{3, 2}, {2, 0}])
    chord = Matcher.candidate_ids(window, Catalog.index(:chord))
    hand = Matcher.candidate_ids(window, Catalog.index(:hand))

    assert MapSet.subset?(chord, hand)
    assert MapSet.size(hand) > MapSet.size(chord)
  end

  test "no notes means no candidates" do
    assert Matcher.candidate_ids([], Catalog.index(:hand)) == MapSet.new()
  end
end
