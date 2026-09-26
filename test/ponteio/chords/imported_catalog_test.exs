defmodule Ponteio.Chords.ImportedCatalogTest do
  use Ponteio.DataCase, async: true

  alias Ponteio.Chords.ChordShape
  alias Ponteio.Chords.ImportedCatalog

  @tuning [4, 9, 2, 7, 11, 4]
  @intervals %{
    major: [0, 4, 7],
    minor: [0, 3, 7],
    dominant_seventh: [0, 4, 7, 10],
    sus2: [0, 2, 7],
    sus4: [0, 5, 7],
    diminished: [0, 3, 6],
    augmented: [0, 4, 8]
  }

  test "curated positions have correct roots, qualities, string order and no duplicates" do
    shapes = ImportedCatalog.all()
    assert length(shapes) == 326
    assert Enum.map(shapes, & &1.slug) |> Enum.uniq() |> length() == 326

    positions = Enum.map(shapes, &ImportedCatalog.position(&1, &1.min_base_fret))
    assert length(Enum.uniq(positions)) == 326

    Enum.each(shapes, fn shape ->
      assert shape.min_base_fret == shape.max_base_fret
      frets = ImportedCatalog.position(shape, shape.min_base_fret)
      assert length(frets) == 6
      root_fret = Enum.at(frets, 6 - shape.root_string)
      assert is_integer(root_fret)
      root = Integer.mod(Enum.at(@tuning, 6 - shape.root_string) + root_fret, 12)

      actual =
        @tuning
        |> Enum.zip(frets)
        |> Enum.reject(fn {_note, fret} -> is_nil(fret) end)
        |> Enum.map(fn {note, fret} -> Integer.mod(note + fret, 12) end)
        |> MapSet.new()

      expected =
        @intervals
        |> Map.fetch!(shape.quality)
        |> Enum.map(&Integer.mod(root + &1, 12))
        |> MapSet.new()

      assert actual == expected, shape.slug
    end)
  end

  test "open, muted and closed positions retain the source's absolute frets" do
    shapes = Map.new(ImportedCatalog.all(), &{&1.slug, &1})

    assert ImportedCatalog.position(shapes["chords-db-c-major-1"], 0) ==
             [nil, 3, 2, 0, 1, 0]

    assert ImportedCatalog.position(shapes["chords-db-c-major-2"], 3) ==
             [nil, 3, 5, 5, 5, 3]

    assert shapes["chords-db-c-major-2"].root_string == 5
    assert shapes["chords-db-c-major-2"].movable
  end

  test "imported positions persist with stable slugs on repeated upsert" do
    attrs = Enum.find(ImportedCatalog.all(), &(&1.slug == "chords-db-c-major-2"))

    first = ChordShape |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
    second = ChordShape |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()

    assert second.id == first.id
    assert Ash.count!(ChordShape) == 1
    assert second.relative_frets == [0, 2, 2, 2, 0, nil]
  end
end
