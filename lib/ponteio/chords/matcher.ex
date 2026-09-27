defmodule Ponteio.Chords.Matcher do
  @moduledoc """
  Decides which hand positions can play a window of tablature notes without
  moving the hand: every note `{string, fret}` must be one of the frets that
  string can sound in the chosen mode (see `Ponteio.Chords.HandPosition`).
  """

  alias Ponteio.Chords.HandPosition
  alias Ponteio.Chords.Index

  @type note :: %{
          required(:string) => HandPosition.string_number(),
          required(:fret) => non_neg_integer()
        }

  @spec matches?([note()], HandPosition.t(), HandPosition.mode()) :: boolean()
  def matches?(notes, %HandPosition{} = position, mode) do
    Enum.all?(notes, fn %{string: string, fret: fret} ->
      fret in HandPosition.playable_frets(position, string, mode)
    end)
  end

  @doc """
  Ids of every position in `index` that matches all `notes`. An empty `notes`
  list matches nothing (there is no hand position to infer from it).
  """
  @spec candidate_ids([note()], Index.t()) :: MapSet.t()
  def candidate_ids([], _index), do: MapSet.new()

  def candidate_ids(notes, %{by_note: by_note}) do
    notes
    |> Enum.map(&Map.get(by_note, {&1.string, &1.fret}, MapSet.new()))
    |> Enum.reduce(&MapSet.intersection/2)
  end

  @doc "Positions matching `notes`, easiest first."
  @spec candidates([note()], Index.t()) :: [HandPosition.t()]
  def candidates(notes, index) do
    notes
    |> candidate_ids(index)
    |> Enum.map(&Map.fetch!(index.positions, &1))
    |> sort_by_ease()
  end

  @doc "Orders positions by complexity, then lower on the neck, then id (stable)."
  @spec sort_by_ease([HandPosition.t()]) :: [HandPosition.t()]
  def sort_by_ease(positions) do
    Enum.sort_by(positions, &{&1.complexity, &1.base_fret, &1.id})
  end
end
