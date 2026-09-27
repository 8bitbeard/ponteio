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

  test "open notes on strings the chord mutes fit the hand position" do
    assert Matcher.matches?(notes([{6, 0}, {5, 0}, {3, 2}, {1, 2}]), d_major_open())
  end

  test "a fretted note on a string the chord mutes needs another finger" do
    refute Matcher.matches?(notes([{6, 2}, {3, 2}]), d_major_open())
  end

  test "a chord string must be played at the chord's fret" do
    refute Matcher.matches?(notes([{3, 4}]), d_major_open())
  end

  test "a muted string under the barre plays at the barre fret, never open" do
    assert Matcher.matches?(notes([{6, 8}, {5, 8}, {1, 8}]), c_six_barre())
    refute Matcher.matches?(notes([{5, 0}]), c_six_barre())
  end

  test "candidates include every matching position, easiest first" do
    candidates = Matcher.candidates(notes([{6, 0}, {5, 0}, {3, 2}, {1, 2}]), Catalog.index())

    assert d_major_open() in candidates

    assert Enum.map(candidates, & &1.complexity) ==
             Enum.sort(Enum.map(candidates, & &1.complexity))
  end

  test "no notes means no candidates" do
    assert Matcher.candidate_ids([], Catalog.index()) == MapSet.new()
  end
end
