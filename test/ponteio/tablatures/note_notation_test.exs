defmodule Ponteio.Tablatures.NoteNotationTest do
  use ExUnit.Case, async: true

  alias Ponteio.Tablatures.NoteNotation

  test "parses string letters and frets, low E and high e apart" do
    assert NoteNotation.parse("E3 A0 D2 G2 B3 e12") ==
             {:ok,
              [
                %{string: 6, fret: 3},
                %{string: 5, fret: 0},
                %{string: 4, fret: 2},
                %{string: 3, fret: 2},
                %{string: 2, fret: 3},
                %{string: 1, fret: 12}
              ]}
  end

  test "accepts commas and extra whitespace as separators" do
    assert {:ok, [%{string: 6, fret: 3}, %{string: 1, fret: 0}]} =
             NoteNotation.parse("  E3,  e0 ")
  end

  test "rejects unknown strings, bad frets and empty input" do
    assert NoteNotation.parse("E3 X2") == {:error, "Nota inválida: X2"}
    assert NoteNotation.parse("b2") == {:error, "Nota inválida: b2"}
    assert NoteNotation.parse("E25") == {:error, "Nota inválida: E25"}
    assert NoteNotation.parse("E") == {:error, "Nota inválida: E"}
    assert NoteNotation.parse("  ") == {:error, "Nenhuma nota informada"}
  end

  test "formats a note back to the notation" do
    assert NoteNotation.format(%{string: 6, fret: 3}) == "E3"
    assert NoteNotation.format(%{string: 1, fret: 0}) == "e0"
  end
end
