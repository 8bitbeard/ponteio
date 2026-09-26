# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seeds the curated `Ponteio.Chords.ChordShape` catalog (SDD §2.3): a set of
# open-position chords, barre/movable shapes, and quality variations (major,
# minor, dominant 7th, sus2, sus4, diminished, augmented) — enough to cover
# common songs, not an exhaustive chord dictionary.
#
# Idempotent: each shape's `:create` action upserts on the unique `slug`
# identity, so running this script again just refreshes the existing rows
# instead of duplicating them.
#
# Fret notation below follows the standard low-to-high string order
# (E A D G B e) for readability; each entry is converted to the resource's
# storage order (string 1 = high e .. string 6 = low E) before insertion.
# `nil` means the string is muted / not part of the shape.

defmodule Ponteio.ChordShapeSeeds do
  @moduledoc false

  alias Ponteio.Chords.ChordShape
  alias Ponteio.Chords.ImportedCatalog

  # Reverses a low-to-high (E A D G B e) fret list into the resource's
  # storage order (string 1 = high e .. string 6 = low E).
  defp to_relative_frets(low_to_high_frets), do: Enum.reverse(low_to_high_frets)

  def open_chords do
    [
      # -- E ------------------------------------------------------------
      %{
        slug: "open-e-major",
        name: "Maior",
        quality: :major,
        root_string: 6,
        low_to_high_frets: [0, 2, 2, 1, 0, 0]
      },
      %{
        slug: "open-e-minor",
        name: "Menor",
        quality: :minor,
        root_string: 6,
        low_to_high_frets: [0, 2, 2, 0, 0, 0]
      },
      %{
        slug: "open-e-dominant-seventh",
        name: "7",
        quality: :dominant_seventh,
        root_string: 6,
        low_to_high_frets: [0, 2, 0, 1, 0, 0]
      },

      # -- A ------------------------------------------------------------
      %{
        slug: "open-a-major",
        name: "Maior",
        quality: :major,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 2, 0]
      },
      %{
        slug: "open-a-minor",
        name: "Menor",
        quality: :minor,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 1, 0]
      },
      %{
        slug: "open-a-dominant-seventh",
        name: "7",
        quality: :dominant_seventh,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 0, 2, 0]
      },
      %{
        slug: "open-a-sus2",
        name: "Sus2",
        quality: :sus2,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 0, 0]
      },
      %{
        slug: "open-a-sus4",
        name: "Sus4",
        quality: :sus4,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 3, 0]
      },

      # -- D ------------------------------------------------------------
      %{
        slug: "open-d-major",
        name: "Maior",
        quality: :major,
        root_string: 4,
        low_to_high_frets: [nil, nil, 0, 2, 3, 2]
      },
      %{
        slug: "open-d-minor",
        name: "Menor",
        quality: :minor,
        root_string: 4,
        low_to_high_frets: [nil, nil, 0, 2, 3, 1]
      },
      %{
        slug: "open-d-dominant-seventh",
        name: "7",
        quality: :dominant_seventh,
        root_string: 4,
        low_to_high_frets: [nil, nil, 0, 2, 1, 2]
      },
      %{
        slug: "open-d-sus2",
        name: "Sus2",
        quality: :sus2,
        root_string: 4,
        low_to_high_frets: [nil, nil, 0, 2, 3, 0]
      },
      %{
        slug: "open-d-sus4",
        name: "Sus4",
        quality: :sus4,
        root_string: 4,
        low_to_high_frets: [nil, nil, 0, 2, 3, 3]
      },

      # -- C / G ---------------------------------------------------------
      %{
        slug: "open-c-major",
        name: "Maior",
        quality: :major,
        root_string: 5,
        low_to_high_frets: [nil, 3, 2, 0, 1, 0]
      },
      %{
        slug: "open-c-dominant-seventh",
        name: "7",
        quality: :dominant_seventh,
        root_string: 5,
        low_to_high_frets: [nil, 3, 2, 3, 1, 0]
      },
      %{
        slug: "open-g-major",
        name: "Maior",
        quality: :major,
        root_string: 6,
        low_to_high_frets: [3, 2, 0, 0, 0, 3]
      },

      # -- Augmented (fretted "open-position" voicing, not movable) -----
      %{
        slug: "open-c-augmented",
        name: "Aug",
        quality: :augmented,
        root_string: 5,
        low_to_high_frets: [nil, 3, 2, 1, 1, 0]
      }
    ]
    |> Enum.map(&Map.put(&1, :movable, false))
    |> Enum.map(&Map.merge(&1, %{min_base_fret: 0, max_base_fret: 0}))
  end

  def barre_chords do
    [
      # -- "E-shape" barre (root on the low E string) --------------------
      %{
        slug: "barre-e-shape-major",
        name: "Maior",
        quality: :major,
        root_string: 6,
        low_to_high_frets: [0, 2, 2, 1, 0, 0]
      },
      %{
        slug: "barre-e-shape-minor",
        name: "Menor",
        quality: :minor,
        root_string: 6,
        low_to_high_frets: [0, 2, 2, 0, 0, 0]
      },
      %{
        slug: "barre-e-shape-dominant-seventh",
        name: "7",
        quality: :dominant_seventh,
        root_string: 6,
        low_to_high_frets: [0, 2, 0, 1, 0, 0]
      },

      # -- "A-shape" barre (root on the A string) ------------------------
      %{
        slug: "barre-a-shape-major",
        name: "Maior",
        quality: :major,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 2, 0]
      },
      %{
        slug: "barre-a-shape-minor",
        name: "Menor",
        quality: :minor,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 1, 0]
      },
      %{
        slug: "barre-a-shape-dominant-seventh",
        name: "7",
        quality: :dominant_seventh,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 0, 2, 0]
      },
      %{
        slug: "barre-a-shape-sus4",
        name: "Sus4",
        quality: :sus4,
        root_string: 5,
        low_to_high_frets: [nil, 0, 2, 2, 3, 0]
      },

      # -- Diminished 7th (fully symmetric, genuinely movable) -----------
      %{
        slug: "barre-a-shape-diminished-seventh",
        name: "Dim",
        quality: :diminished,
        root_string: 5,
        low_to_high_frets: [nil, 2, 3, 4, 3, nil]
      }
    ]
    |> Enum.map(&Map.put(&1, :movable, true))
    |> Enum.map(&Map.merge(&1, %{min_base_fret: 1, max_base_fret: 9}))
  end

  def all do
    (open_chords() ++ barre_chords())
    |> Enum.map(fn shape ->
      shape
      |> Map.put(:relative_frets, to_relative_frets(shape.low_to_high_frets))
      |> Map.delete(:low_to_high_frets)
    end)
  end

  def run do
    legacy_shapes = all()

    # The original slugs remain authoritative. A legacy movable shape covers
    # all its allowed base frets, so compare actual sounding positions, not
    # just its stored relative offsets, before adding a chords-db position.
    legacy_positions =
      legacy_shapes
      |> Enum.flat_map(fn shape ->
        Enum.map(shape.min_base_fret..shape.max_base_fret, &ImportedCatalog.position(shape, &1))
      end)
      |> MapSet.new()

    imported_shapes =
      ImportedCatalog.all()
      |> Enum.reject(fn shape ->
        MapSet.member?(legacy_positions, ImportedCatalog.position(shape, shape.min_base_fret))
      end)

    shapes = legacy_shapes ++ imported_shapes

    Enum.each(shapes, fn attrs ->
      ChordShape
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create!()
    end)

    IO.puts(
      "Seeded #{length(legacy_shapes)} original and #{length(imported_shapes)} chords-db shapes " <>
        "(#{Ash.count!(ChordShape)} total in catalog)."
    )
  end
end

Ponteio.ChordShapeSeeds.run()
