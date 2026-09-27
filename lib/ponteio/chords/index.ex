defmodule Ponteio.Chords.Index do
  @moduledoc """
  Lookup structure over a set of hand positions: positions by id, plus each
  `{string, fret}` pair mapped to the ids of the positions whose `playable` fret
  on that string is `fret` (see `Ponteio.Chords.HandPosition`).
  """

  alias Ponteio.Chords.HandPosition

  @type t :: %{
          positions: %{non_neg_integer() => HandPosition.t()},
          by_note: %{{HandPosition.string_number(), non_neg_integer()} => MapSet.t()}
        }

  @spec build([HandPosition.t()]) :: t()
  def build(positions) do
    by_note =
      Enum.reduce(positions, %{}, fn position, acc ->
        Enum.reduce(position.playable, acc, fn {string, fret}, acc ->
          Map.update(acc, {string, fret}, MapSet.new([position.id]), &MapSet.put(&1, position.id))
        end)
      end)

    %{positions: Map.new(positions, &{&1.id, &1}), by_note: by_note}
  end
end
