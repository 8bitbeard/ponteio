defmodule Ponteio.Chords.Catalog do
  @moduledoc """
  Every guitar hand position from the vendored chords-db
  (`data/chords-db/guitar.json`), loaded and indexed at compile time: the JSON is
  parsed once while this module compiles and baked into the BEAM file as a
  literal, so there is no file I/O or parsing at runtime.
  """

  alias Ponteio.Chords.Complexity
  alias Ponteio.Chords.HandPosition
  alias Ponteio.Chords.Index

  @source Path.expand("../../../data/chords-db/guitar.json", __DIR__)
  @external_resource @source

  @positions @source
             |> File.read!()
             |> Jason.decode!()
             |> Map.fetch!("chords")
             |> Enum.sort_by(fn {key, _chords} -> key end)
             |> Enum.flat_map(fn {_key, chords} -> chords end)
             |> Enum.flat_map(fn %{"key" => key, "suffix" => suffix, "positions" => positions} ->
               Enum.map(positions, &{key, suffix, &1})
             end)
             |> Enum.with_index()
             |> Enum.map(fn {{key, suffix, position}, id} ->
               hand_position = HandPosition.from_chords_db(id, key, suffix, position)
               %{hand_position | complexity: Complexity.score(hand_position)}
             end)

  @hand_index Index.build(@positions, :hand)
  @chord_index Index.build(@positions, :chord)

  @spec all() :: [HandPosition.t()]
  def all, do: @positions

  @doc "The index for a matching mode (see `Ponteio.Chords.HandPosition`)."
  @spec index(HandPosition.mode()) :: Index.t()
  def index(:hand), do: @hand_index
  def index(:chord), do: @chord_index
end
