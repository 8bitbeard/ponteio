defmodule Ponteio.Chords.HandPosition do
  @moduledoc """
  A fretting-hand position on the neck, derived from one chord voicing of the
  chords-db catalog (`data/chords-db/guitar.json`).

  Strings are numbered 1 (high e) to 6 (low E). Frets are absolute (0 = open).

  `playable` is the heart of the matching rule: for each string, the single fret
  that can be sounded without moving the hand —

    * a string fretted by the chord: that fret;
    * a muted string lying under a barre: the barre's fret (the finger is already
      pressing it);
    * any other muted string: 0 (an open string needs no finger).
  """

  @type string_number :: 1..6

  @type barre :: %{fret: pos_integer(), from_string: string_number(), to_string: string_number()}

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          key: String.t(),
          suffix: String.t(),
          base_fret: pos_integer(),
          frets: %{string_number() => non_neg_integer() | nil},
          fingers: %{string_number() => 0..4},
          barres: [barre()],
          playable: %{string_number() => non_neg_integer()},
          complexity: float() | nil
        }

  defstruct [:id, :key, :suffix, :base_fret, :frets, :fingers, :barres, :playable, :complexity]

  @doc """
  Builds a hand position from a chords-db position entry, whose `frets` and
  `fingers` lists run from low E to high e and whose fret values are relative to
  `baseFret` (`-1` muted, `0` open).
  """
  @spec from_chords_db(non_neg_integer(), String.t(), String.t(), map()) :: t()
  def from_chords_db(id, key, suffix, %{"frets" => frets, "fingers" => fingers} = position) do
    base_fret = Map.fetch!(position, "baseFret")
    relative_barres = Map.get(position, "barres", [])

    absolute_frets = by_string(frets, &absolute_fret(&1, base_fret))
    barres = Enum.map(relative_barres, &barre(&1, frets, base_fret))

    %__MODULE__{
      id: id,
      key: key,
      suffix: suffix,
      base_fret: base_fret,
      frets: absolute_frets,
      fingers: by_string(fingers, & &1),
      barres: barres,
      playable: playable(absolute_frets, barres)
    }
  end

  defp by_string(low_to_high, fun) do
    low_to_high
    |> Enum.with_index()
    |> Map.new(fn {value, index} -> {6 - index, fun.(value)} end)
  end

  defp absolute_fret(-1, _base_fret), do: nil
  defp absolute_fret(0, _base_fret), do: 0
  defp absolute_fret(relative, base_fret), do: base_fret - 1 + relative

  defp barre(relative_fret, frets, base_fret) do
    pressed_strings =
      frets
      |> Enum.with_index()
      |> Enum.filter(fn {value, _index} -> value == relative_fret end)
      |> Enum.map(fn {_value, index} -> 6 - index end)

    %{
      fret: absolute_fret(relative_fret, base_fret),
      from_string: Enum.min(pressed_strings),
      to_string: Enum.max(pressed_strings)
    }
  end

  defp playable(frets, barres) do
    Map.new(frets, fn
      {string, nil} -> {string, muted_playable_fret(string, barres)}
      {string, fret} -> {string, fret}
    end)
  end

  # With more than one barre over the same string, the one closest to the body
  # (highest fret) is the one that sounds.
  defp muted_playable_fret(string, barres) do
    barres
    |> Enum.filter(&(&1.from_string <= string and string <= &1.to_string))
    |> Enum.map(& &1.fret)
    |> Enum.max(fn -> 0 end)
  end
end
