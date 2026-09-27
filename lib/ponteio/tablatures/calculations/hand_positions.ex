defmodule Ponteio.Tablatures.Calculations.HandPositions do
  @moduledoc """
  Runs the chord engine on a measure's notes, in the matching `:mode` given as
  the calculation option (see `Ponteio.Chords.HandPosition`). Ash hands over all
  measures being loaded in one batch, so repeated passages are analyzed once
  (`Ponteio.Chords.MeasureAnalyzer.analyze_all/2`).
  """

  use Ash.Resource.Calculation

  alias Ponteio.Chords.MeasureAnalyzer

  @impl true
  def init(opts) do
    if opts[:mode] in [:hand, :chord],
      do: {:ok, opts},
      else: {:error, "expected mode: :hand or :chord"}
  end

  @impl true
  def load(_query, _opts, _context), do: [notes: [:string, :fret, :position]]

  @impl true
  def calculate(measures, opts, _context) do
    measures
    |> Enum.map(& &1.notes)
    |> MeasureAnalyzer.analyze_all(mode: opts[:mode])
  end
end
