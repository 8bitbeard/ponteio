defmodule Ponteio.Tablatures.NoteNotation do
  @moduledoc """
  Text notation for notes: a string letter followed by a fret, e.g. `E3 D0 e2`.
  `E` is the low E string (6) and `e` the high e string (1); letters are
  case-sensitive for that reason. Notes are separated by spaces or commas.
  """

  @strings %{"E" => 6, "A" => 5, "D" => 4, "G" => 3, "B" => 2, "e" => 1}
  @letters Map.new(@strings, fn {letter, string} -> {string, letter} end)
  @max_fret 24

  @spec parse(String.t()) ::
          {:ok, [%{string: 1..6, fret: non_neg_integer()}]} | {:error, String.t()}
  def parse(text) do
    text
    |> String.split([" ", ",", "\n", "\t"], trim: true)
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, notes} ->
      case parse_token(token) do
        {:ok, note} -> {:cont, {:ok, [note | notes]}}
        :error -> {:halt, {:error, "Nota inválida: #{token}"}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, "Nenhuma nota informada"}
      {:ok, notes} -> {:ok, Enum.reverse(notes)}
      error -> error
    end
  end

  @spec format(%{string: 1..6, fret: non_neg_integer()}) :: String.t()
  def format(%{string: string, fret: fret}), do: "#{Map.fetch!(@letters, string)}#{fret}"

  defp parse_token(<<letter::binary-size(1), fret::binary>>) do
    with {:ok, string} <- Map.fetch(@strings, letter),
         {fret, ""} when fret in 0..@max_fret <- Integer.parse(fret) do
      {:ok, %{string: string, fret: fret}}
    else
      _ -> :error
    end
  end

  defp parse_token(_token), do: :error
end
