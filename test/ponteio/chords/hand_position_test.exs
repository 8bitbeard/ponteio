defmodule Ponteio.Chords.HandPositionTest do
  use ExUnit.Case, async: true

  alias Ponteio.Chords.HandPosition

  defp build(frets, fingers, base_fret, barres \\ []) do
    HandPosition.from_chords_db(0, "X", "test", %{
      "frets" => frets,
      "fingers" => fingers,
      "baseFret" => base_fret,
      "barres" => barres
    })
  end

  test "converts an open chord, playing muted strings open" do
    c_major = build([-1, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0], 1)

    assert c_major.frets == %{6 => nil, 5 => 3, 4 => 2, 3 => 0, 2 => 1, 1 => 0}
    assert c_major.playable == %{6 => 0, 5 => 3, 4 => 2, 3 => 0, 2 => 1, 1 => 0}
    assert c_major.barres == []
  end

  test "converts relative frets of a barre chord to absolute frets" do
    c_major_barre = build([-1, 1, 3, 3, 3, 1], [0, 1, 2, 3, 4, 1], 3, [1])

    assert c_major_barre.frets == %{6 => nil, 5 => 3, 4 => 5, 3 => 5, 2 => 5, 1 => 3}
    assert c_major_barre.barres == [%{fret: 3, from_string: 1, to_string: 5}]
  end

  test "a muted string outside the barre can still ring open" do
    c_major_barre = build([-1, 1, 3, 3, 3, 1], [0, 1, 2, 3, 4, 1], 3, [1])

    assert c_major_barre.playable[6] == 0
  end

  test "a muted string under the barre is playable only at the barre fret" do
    c_six = build([1, -1, 3, 2, 3, 1], [1, 0, 3, 2, 4, 1], 8, [1])

    assert c_six.barres == [%{fret: 8, from_string: 1, to_string: 6}]
    assert c_six.playable[5] == 8
  end

  test "with overlapping barres, a muted string sounds at the highest one" do
    position = build([1, -1, 3, -1, 1, 3], [1, 0, 3, 0, 1, 4], 5, [1, 3])

    assert position.playable[3] == 7
    assert position.playable[5] == 5
  end
end
