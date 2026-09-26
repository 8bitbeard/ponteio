defmodule Ponteio.Chords.ChordShapeSeedsTest do
  use Ponteio.DataCase

  alias Ponteio.Chords.ChordShape
  alias Ponteio.Chords.ImportedCatalog

  test "the full seed preserves original slugs, omits overlapping positions and is idempotent" do
    Code.require_file("priv/repo/seeds.exs")
    seed_module = Module.concat(["Ponteio", "ChordShapeSeeds"])

    first = Ash.read!(ChordShape)
    originals = seed_module.all()
    assert length(originals) == 25
    assert length(first) == 286

    first_by_slug = Map.new(first, &{&1.slug, &1})
    assert Enum.all?(originals, &Map.has_key?(first_by_slug, &1.slug))
    original_slugs = MapSet.new(originals, & &1.slug)

    original_positions =
      originals
      |> Enum.flat_map(fn shape ->
        Enum.map(shape.min_base_fret..shape.max_base_fret, &ImportedCatalog.position(shape, &1))
      end)
      |> MapSet.new()

    imported_positions =
      first
      |> Enum.reject(&MapSet.member?(original_slugs, &1.slug))
      |> Enum.map(&ImportedCatalog.position(&1, &1.min_base_fret))

    assert Enum.all?(imported_positions, &(not MapSet.member?(original_positions, &1)))
    assert length(imported_positions) == length(Enum.uniq(imported_positions))

    seed_module.run()
    second = Ash.read!(ChordShape)
    assert length(second) == length(first)
    assert Map.new(second, &{&1.slug, &1.id}) == Map.new(first, &{&1.slug, &1.id})
  end
end
