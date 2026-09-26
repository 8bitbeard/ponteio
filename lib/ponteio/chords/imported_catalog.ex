defmodule Ponteio.Chords.ImportedCatalog do
  @moduledoc """
  Offline, curated guitar positions from tombatossals/chords-db. See
  `docs/chords-db-import.md` for the pinned source and conversion rules.
  """

  @qualities %{
    "major" => :major,
    "minor" => :minor,
    "dominant_seventh" => :dominant_seventh,
    "sus2" => :sus2,
    "sus4" => :sus4,
    "diminished" => :diminished,
    "augmented" => :augmented
  }

  @doc "Returns the validated local positions as ChordShape create attributes."
  def all do
    :ponteio
    |> :code.priv_dir()
    |> Path.join("repo/chords_db_guitar.json")
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(fn row ->
      %{
        slug: Map.fetch!(row, "slug"),
        name: Map.fetch!(row, "name"),
        quality: Map.fetch!(@qualities, Map.fetch!(row, "quality")),
        root_string: Map.fetch!(row, "root_string"),
        movable: Map.fetch!(row, "movable"),
        min_base_fret: Map.fetch!(row, "min_base_fret"),
        max_base_fret: Map.fetch!(row, "max_base_fret"),
        relative_frets: Map.fetch!(row, "relative_frets")
      }
    end)
  end

  @doc "Absolute low-E-to-high-e fret pattern for one instantiated shape."
  def position(shape, base_fret) do
    shape.relative_frets
    |> Enum.reverse()
    |> Enum.map(fn
      nil -> nil
      offset -> offset + base_fret
    end)
  end
end
