defmodule Ponteio.Chords.Index do
  @moduledoc """
  Lookup structure over a set of hand positions for one matching mode (see
  `Ponteio.Chords.HandPosition.playable_frets/3`): positions by id, plus each
  `{string, fret}` pair mapped to the ids of the positions that can sound it.
  """

  alias Ponteio.Chords.HandPosition

  @type t :: %{
          mode: HandPosition.mode(),
          positions: %{non_neg_integer() => HandPosition.t()},
          by_note: %{{HandPosition.string_number(), non_neg_integer()} => MapSet.t()}
        }

  @spec build([HandPosition.t()], HandPosition.mode()) :: t()
  def build(positions, mode) do
    by_note =
      for position <- positions,
          string <- 1..6,
          fret <- HandPosition.playable_frets(position, string, mode),
          reduce: %{} do
        acc ->
          Map.update(acc, {string, fret}, MapSet.new([position.id]), &MapSet.put(&1, position.id))
      end

    %{mode: mode, positions: Map.new(positions, &{&1.id, &1}), by_note: by_note}
  end
end
