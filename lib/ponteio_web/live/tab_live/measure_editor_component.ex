defmodule PonteioWeb.TabLive.MeasureEditorComponent do
  @moduledoc """
  Renders one compasso's note-entry grid (issue #11, "Inserir notas no
  editor de tablatura"; PRD §6.3; SDD §4's `MeasureEditorComponent`).

  This is a plain `Phoenix.Component` function component, not a
  `Phoenix.LiveComponent` — per the project's Phoenix guideline ("Avoid
  LiveComponent's unless you have a strong, specific need for them"),
  there's no isolated state to keep here: `PonteioWeb.TabLive.Editor` owns
  the whole editor's `measures`/`editing` assigns (it needs them intact,
  as a single in-memory tree, to eventually build the payload for
  `upsert_measure_notes`, issue #14), and every event this component's
  markup emits (`start_note`, `confirm_note`) is handled by that parent
  LiveView, identified via `phx-value-measure`/`phx-value-string` rather
  than a component `phx-target`.

  Grid shape: 6 rows (one per string, `e B G D A E` top-to-bottom —
  string 1 = high e .. string 6 = low E, same convention as
  `Ponteio.Chords.ChordShape.root_string`), and one column per note
  already inserted in the measure **plus one trailing, always-empty
  column** — clicking an empty cell in that trailing column, on the
  string the user wants, opens an inline input for the fret number;
  confirming (Enter or blur) commits the note and the trailing column
  shifts one further right (SDD §4, this issue's "Fluxo de inserção").
  The grid has no fixed width — unlike the static mockup's fixed 7-column
  cards (`docs/mockup-telas.html`, Tela 2), which don't model this
  open-ended growth — the column count always tracks `length(notes) + 1`,
  per this issue's explicit acceptance criterion.

  Cells in already-committed columns that aren't the one note actually
  present are inert placeholders, not editable — issue #11 only wires the
  trailing-column "append a note" flow; editing/removing an existing
  note is issue #13's scope.
  """

  use Phoenix.Component

  @strings 1..6
  @string_labels %{1 => "e", 2 => "B", 3 => "G", 4 => "D", 5 => "A", 6 => "E"}

  attr :measure, :map, required: true
  attr :editing, :any, default: nil

  def measure_editor(assigns) do
    assigns =
      assigns
      |> assign(:column_count, column_count(assigns.measure))
      |> assign(:strings, @strings)

    ~H"""
    <div id={"measure-#{@measure.id}"} class="rounded-lg border border-base-300 bg-base-100 p-4 mb-4">
      <div class="flex items-center justify-between mb-3">
        <span class="text-sm font-semibold text-base-content/70">
          Compasso {@measure.position}
        </span>
      </div>

      <div class="flex flex-col gap-1">
        <div
          :for={string_number <- @strings}
          class="grid items-center h-7"
          style={"grid-template-columns: 1.5rem repeat(#{@column_count}, 2.5rem);"}
        >
          <span class="text-xs font-semibold text-base-content/60">
            {string_label(string_number)}
          </span>

          <.cell
            :for={column <- 0..(@column_count - 1)}
            measure={@measure}
            string_number={string_number}
            column={column}
            trailing?={column == @column_count - 1}
            editing={@editing}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :measure, :map, required: true
  attr :string_number, :integer, required: true
  attr :column, :integer, required: true
  attr :trailing?, :boolean, required: true
  attr :editing, :any, required: true

  defp cell(assigns) do
    assigns =
      assigns
      |> assign(:note, note_at(assigns.measure, assigns.string_number, assigns.column))
      |> assign(:id, "cell-#{assigns.measure.id}-#{assigns.string_number}-#{assigns.column}")
      |> then(fn assigns ->
        assign(
          assigns,
          :editing_this_cell?,
          assigns.trailing? and assigns.editing == {assigns.measure.id, assigns.string_number}
        )
      end)

    ~H"""
    <div
      :if={@editing_this_cell?}
      id={@id}
      class="relative h-full border-b border-base-300"
    >
      <input
        type="number"
        min="0"
        id={"note-input-#{@measure.id}-#{@string_number}"}
        autofocus
        autocomplete="off"
        phx-keydown="confirm_note"
        phx-key="Enter"
        phx-blur="confirm_note"
        phx-value-measure={@measure.id}
        phx-value-string={@string_number}
        class="absolute inset-0 w-full h-full text-center text-xs border border-primary rounded bg-base-100"
      />
    </div>

    <div
      :if={not @editing_this_cell? and @note}
      id={@id}
      class="relative h-full border-b border-base-300"
    >
      <span class="absolute inset-0 flex items-center justify-center">
        <span class="flex items-center justify-center w-5 h-5 rounded-full bg-primary text-primary-content text-xs font-bold">
          {@note.fret_number}
        </span>
      </span>
    </div>

    <div
      :if={not @editing_this_cell? and is_nil(@note) and @trailing?}
      id={@id}
      phx-click="start_note"
      phx-value-measure={@measure.id}
      phx-value-string={@string_number}
      class="relative h-full border-b border-base-300 cursor-pointer hover:bg-base-200"
    >
    </div>

    <div
      :if={not @editing_this_cell? and is_nil(@note) and not @trailing?}
      id={@id}
      class="relative h-full border-b border-base-300"
    >
    </div>
    """
  end

  defp column_count(measure), do: length(measure.notes) + 1

  defp note_at(measure, string_number, column) do
    Enum.find(measure.notes, fn note ->
      note.string_number == string_number and note.position == column
    end)
  end

  defp string_label(string_number), do: Map.fetch!(@string_labels, string_number)
end
