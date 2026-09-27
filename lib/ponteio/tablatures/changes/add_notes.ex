defmodule Ponteio.Tablatures.Changes.AddNotes do
  @moduledoc """
  Parses the `:notes` argument (see `Ponteio.Tablatures.NoteNotation`) and, once
  the measure update runs, creates the notes after the measure's last one. A
  single invalid note rejects the whole batch.
  """

  use Ash.Resource.Change

  alias Ponteio.Tablatures.Note
  alias Ponteio.Tablatures.NoteNotation

  @impl true
  def change(changeset, _opts, _context) do
    case NoteNotation.parse(Ash.Changeset.get_argument(changeset, :notes) || "") do
      {:ok, notes} ->
        Ash.Changeset.after_action(changeset, fn _changeset, measure ->
          create_notes(measure, notes)
          {:ok, measure}
        end)

      {:error, message} ->
        Ash.Changeset.add_error(
          changeset,
          Ash.Error.Changes.InvalidArgument.exception(field: :notes, message: message)
        )
    end
  end

  defp create_notes(measure, notes) do
    %{last_note_position: last} = Ash.load!(measure, :last_note_position)
    first = if last, do: last + 1, else: 0

    notes
    |> Enum.with_index(first)
    |> Enum.map(fn {note, position} ->
      Map.merge(note, %{measure_id: measure.id, position: position})
    end)
    |> Ash.bulk_create!(Note, :create, return_errors?: true, stop_on_error?: true)
  end
end
