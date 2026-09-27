defmodule Ponteio.Chords.ComplexityTest do
  use ExUnit.Case, async: true

  alias Ponteio.Chords.Complexity
  alias Ponteio.Chords.HandPosition

  defp build(frets, fingers, base_fret, barres \\ []) do
    HandPosition.from_chords_db(0, "X", "test", %{
      "frets" => frets,
      "fingers" => fingers,
      "baseFret" => base_fret,
      "barres" => barres
    })
  end

  test "counts distinct fingers plus half the fret span" do
    c_major = build([-1, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0], 1)

    assert Complexity.score(c_major) == 4.0
  end

  test "adds a penalty per barre" do
    c_major_barre = build([-1, 1, 3, 3, 3, 1], [0, 1, 2, 3, 4, 1], 3, [1])

    assert Complexity.score(c_major_barre) == 7.0
  end

  test "all open strings score zero" do
    assert Complexity.score(build([0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0], 1)) == 0.0
  end
end
