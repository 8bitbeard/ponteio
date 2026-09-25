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
  note is issue #13's scope, described below.

  ## Editing/removing an existing note (issue #13)

  Clicking a note chip (`start_edit_note`) opens an inline edit form in
  that same cell — unlike the trailing flow's single fret input, this one
  has **two** fields (a corda `<select>` plus a casa number input),
  because either — or both — may change (`update_note/4` looks the note
  up by position alone, never by its old string, so moving it to a
  different string is exactly as valid as changing its fret). A real
  `<.form>` with `phx-submit="confirm_edit_note"` is used instead of the
  trailing flow's `phx-keydown`/`phx-blur` pair, since with two fields
  there's no single element whose blur unambiguously means "done
  editing" — pressing Enter in either field submits it natively. A
  trash-icon button alongside it fires `remove_note` directly, no
  confirmation step (mirrors how confirming a fret of "" silently
  cancels rather than erroring — this editor treats its local,
  not-yet-persisted state as cheap to correct).

  ## Removing a compasso's marker (issue #13)

  A trash-icon button in the `measure-head`, `remove_measure`, lets the
  editor fold this measure's notes into an adjacent one (`Editor`'s
  moduledoc has the merge rule). It's only rendered when `removable?` is
  true — the parent passes `length(@measures) > 1`, since a tablature
  must always keep at least one measure and this grid has no other place
  that enforces that invariant.

  ## Breaking a measure mid-sequence (issue #12)

  A thin "control row" sits above the string rows, sharing the exact same
  `grid-template-columns` as they do so its buttons line up one-per-column.
  Each column (note columns and the trailing empty one alike — the issue's
  "cada coluna do grid de notas" draws no exception for it) gets a small
  scissors button emitting `break_measure` with the owning measure and that
  column index; `PonteioWeb.TabLive.Editor` is what actually splits the
  measure's notes and reindexes `position` across the local `@measures`
  list, the same "parent LiveView owns all state, child just emits
  `phx-value-*` events" split issue #11 established for `start_note`/
  `confirm_note`. This is the extension of `tab-cell`/`measure-card` the
  issue calls for — the static mockup only shows already-whole
  `measure-card`s, it doesn't draw this affordance.
  """

  use PonteioWeb, :html

  @strings 1..6
  @string_labels %{1 => "e", 2 => "B", 3 => "G", 4 => "D", 5 => "A", 6 => "E"}

  attr :measure, :map, required: true
  attr :editing, :any, default: nil
  attr :removable?, :boolean, default: false

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

        <button
          :if={@removable?}
          type="button"
          id={"remove-measure-#{@measure.id}"}
          phx-click="remove_measure"
          phx-value-measure={@measure.id}
          title="Remover marcador de compasso"
          class="text-base-content/40 hover:text-error transition-colors"
        >
          <.icon name="hero-trash" class="size-4" />
        </button>
      </div>

      <div class="flex flex-col gap-1">
        <div
          class="grid items-center h-4"
          style={"grid-template-columns: 1.5rem repeat(#{@column_count}, 2.5rem);"}
        >
          <span></span>

          <button
            :for={column <- 0..(@column_count - 1)}
            type="button"
            id={"break-#{@measure.id}-#{column}"}
            phx-click="break_measure"
            phx-value-measure={@measure.id}
            phx-value-column={column}
            title="Quebrar compasso aqui"
            class="flex items-center justify-center text-base-content/20 hover:text-primary transition-colors"
          >
            <.icon name="hero-scissors" class="size-3" />
          </button>
        </div>

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
      |> then(fn assigns ->
        assign(
          assigns,
          :editing_note?,
          not is_nil(assigns.note) and
            assigns.editing == {assigns.measure.id, :edit, assigns.note.position}
        )
      end)
      |> then(fn assigns ->
        assign(assigns, :note_form, note_form(assigns.note))
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
      :if={@editing_note?}
      id={@id}
      class="relative h-full border-b border-base-300"
    >
      <span class="absolute inset-0 flex items-center justify-center">
        <span class="flex items-center justify-center w-5 h-5 rounded-full bg-primary text-primary-content text-xs font-bold">
          {@note.fret_number}
        </span>
      </span>

      <.form
        for={@note_form}
        id={"edit-note-form-#{@measure.id}-#{@note.position}"}
        phx-submit="confirm_edit_note"
        phx-value-measure={@measure.id}
        phx-value-position={@note.position}
        class="absolute z-10 top-full left-1/2 -translate-x-1/2 mt-1 flex items-end gap-1 rounded border border-primary bg-base-100 p-1 shadow-lg w-max"
      >
        <.input
          field={@note_form[:string]}
          type="select"
          options={string_select_options()}
          class="select select-xs w-16"
        />
        <.input
          field={@note_form[:fret]}
          type="number"
          min="0"
          autofocus
          class="input input-xs w-12"
        />
        <button
          type="button"
          id={"remove-note-#{@measure.id}-#{@note.position}"}
          phx-click="remove_note"
          phx-value-measure={@measure.id}
          phx-value-position={@note.position}
          title="Remover nota"
          class="text-base-content/40 hover:text-error transition-colors pb-2"
        >
          <.icon name="hero-trash" class="size-3" />
        </button>
      </.form>
    </div>

    <div
      :if={not @editing_this_cell? and not @editing_note? and @note}
      id={@id}
      phx-click="start_edit_note"
      phx-value-measure={@measure.id}
      phx-value-string={@string_number}
      phx-value-position={@note.position}
      class="relative h-full border-b border-base-300 cursor-pointer"
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

  # Backs the edit-note form's two fields (issue #13) with the note's
  # current values, so reopening a note's edit UI always starts from what
  # it's actually set to. `nil` when there's no note to edit — every
  # caller only renders this form when `@note` is present, but `cell/1`
  # computes it unconditionally alongside the other assigns.
  defp note_form(nil), do: nil

  defp note_form(note) do
    to_form(%{"string" => to_string(note.string_number), "fret" => to_string(note.fret_number)},
      as: :note
    )
  end

  defp string_select_options, do: for(string <- @strings, do: {string_label(string), string})
end
