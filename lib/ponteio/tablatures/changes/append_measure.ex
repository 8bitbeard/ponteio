defmodule Ponteio.Tablatures.Changes.AppendMeasure do
  @moduledoc "Gives a new measure the position right after its tab's last measure."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      tab_id = Ash.Changeset.get_attribute(changeset, :tab_id)
      tab = Ash.get!(Ponteio.Tablatures.Tab, tab_id, load: [:last_measure_position])

      Ash.Changeset.force_change_attribute(changeset, :position, next(tab.last_measure_position))
    end)
  end

  defp next(nil), do: 0
  defp next(last), do: last + 1
end
