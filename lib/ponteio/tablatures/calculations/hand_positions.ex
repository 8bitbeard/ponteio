defmodule Ponteio.Tablatures.Calculations.HandPositions do
  @moduledoc "Runs the chord engine on a measure's notes."

  use Ash.Resource.Calculation

  alias Ponteio.Chords.MeasureAnalyzer

  @impl true
  def load(_query, _opts, _context), do: [notes: [:string, :fret, :position]]

  @impl true
  def calculate(measures, _opts, _context) do
    Enum.map(measures, &MeasureAnalyzer.analyze(&1.notes))
  end
end
