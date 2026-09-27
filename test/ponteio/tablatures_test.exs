defmodule Ponteio.TablaturesTest do
  use Ponteio.DataCase, async: true

  alias Ponteio.Tablatures

  defp tab!(title \\ "Radical Dreamer"), do: Tablatures.create_tab!(title)

  defp notes(measure), do: Enum.map(measure.notes, &{&1.string, &1.fret, &1.position})

  test "create_tab requires a title" do
    assert {:error, %Ash.Error.Invalid{}} = Tablatures.create_tab("   ")
  end

  test "list_tabs returns the newest first" do
    first = tab!("Primeira")
    second = tab!("Segunda")

    assert Enum.map(Tablatures.list_tabs!(), & &1.id) == [second.id, first.id]
  end

  test "measures are appended with consecutive positions" do
    tab = tab!()
    first = Tablatures.add_measure!(tab.id)
    second = Tablatures.add_measure!(tab.id)

    assert {first.position, second.position} == {0, 1}
    assert Enum.map(Tablatures.list_measures!(tab.id), & &1.id) == [first.id, second.id]
  end

  test "add_notes appends notes after the existing ones" do
    measure = Tablatures.add_measure!(tab!().id)

    Tablatures.add_notes!(measure, "E3 D0")
    measure = Tablatures.add_notes!(measure, "G2", load: [:notes])

    assert notes(measure) == [{6, 3, 0}, {4, 0, 1}, {3, 2, 2}]
  end

  test "add_notes inserts nothing when any note is invalid" do
    tab = tab!()
    measure = Tablatures.add_measure!(tab.id)

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :notes, message: "Nota inválida: X9"}]}} =
             Tablatures.add_notes(measure, "E3 X9")

    assert Tablatures.get_measure!(tab.id, measure.id).notes == []
  end

  test "hand_positions and chord_positions run the chord engine in each mode" do
    tab = tab!()
    measure = Tablatures.add_measure!(tab.id)
    Tablatures.add_notes!(measure, "E3 D0 G2 E3 B0 D0 G2 A0 D2 G2 A0 B0 D2 G2")

    measure = Tablatures.get_measure!(tab.id, measure.id)

    assert [%{segments: [_]} | _] = measure.hand_positions
    assert [%{segments: [_, _]} | _] = measure.chord_positions
  end

  test "destroy_note removes only that note" do
    tab = tab!()
    measure = Tablatures.add_measure!(tab.id)
    measure = Tablatures.add_notes!(measure, "E3 D0 G2", load: [:notes])
    [_, middle, _] = measure.notes

    Tablatures.destroy_note!(Tablatures.get_note!(measure.id, middle.id))

    assert notes(Tablatures.get_measure!(tab.id, measure.id)) == [{6, 3, 0}, {3, 2, 2}]
  end

  test "destroy_measure renumbers the measures after it" do
    tab = tab!()
    [first, second, third] = for _ <- 1..3, do: Tablatures.add_measure!(tab.id)

    Tablatures.destroy_measure!(second)

    assert Enum.map(Tablatures.list_measures!(tab.id), &{&1.id, &1.position}) == [
             {first.id, 0},
             {third.id, 1}
           ]
  end

  test "a measure is only found through its own tab" do
    measure = Tablatures.add_measure!(tab!().id)

    assert {:error, %Ash.Error.Invalid{}} = Tablatures.get_measure(tab!("Outra").id, measure.id)
  end

  test "a note is only found through its own measure" do
    tab = tab!()
    measure = Tablatures.add_notes!(Tablatures.add_measure!(tab.id), "E3", load: [:notes])
    other = Tablatures.add_measure!(tab.id)

    assert {:error, %Ash.Error.Invalid{}} = Tablatures.get_note(other.id, hd(measure.notes).id)
  end
end
