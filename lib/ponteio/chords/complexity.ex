defmodule Ponteio.Chords.Complexity do
  @moduledoc """
  Heuristic execution-difficulty score for a hand position: lower is easier.

      distinct fingers used + 2 per barre + 0.5 * fret span

  where the fret span is the distance between the highest and lowest fretted
  (non-open, non-muted) frets. Only meant to order positions sensibly
  (open < small barre < wide barre with a stretch), not to model real difficulty.
  """

  alias Ponteio.Chords.HandPosition

  @barre_weight 2
  @span_weight 0.5

  @spec score(HandPosition.t()) :: float()
  def score(%HandPosition{fingers: fingers, barres: barres, frets: frets}) do
    fingers_used =
      fingers
      |> Map.values()
      |> Enum.reject(&(&1 == 0))
      |> Enum.uniq()
      |> length()

    (fingers_used + @barre_weight * length(barres) + @span_weight * fret_span(frets)) * 1.0
  end

  defp fret_span(frets) do
    case frets |> Map.values() |> Enum.filter(&(is_integer(&1) and &1 > 0)) do
      [] -> 0
      fretted -> Enum.max(fretted) - Enum.min(fretted)
    end
  end
end
