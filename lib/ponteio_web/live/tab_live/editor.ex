defmodule PonteioWeb.TabLive.Editor do
  @moduledoc """
  `GET /tabs/new` and `GET /tabs/:id/edit` — "Editor" screen, both the
  creation (issue #6) and metadata-edit (issue #8) flows, plus the
  note-entry grid added by issue #11 ("Inserir notas no editor de
  tablatura"), per PRD §6.2, §6.3, SDD §4, §7.

  The two routes share this module, differentiated by `live_action`
  (`:new` vs `:edit`, SDD §7): the metadata form (title, artist, capo
  position) is identical either way, backed by an `AshPhoenix.Form` around
  the `Ponteio.Tablatures.Tab` resource's `:create` or `:update` action.

  For `:edit`, the tablature is loaded first, scoped to its owner by the
  resource's `:read` policy (SDD §2.2). Issue #10 ("Isolamento de
  tablaturas por usuário") replaced the earlier `Ash.get!/3` here — which
  let a non-owner's or unknown id crash into a bare 404 — with an explicit
  `Ash.get/3` match: either outcome (the tab genuinely doesn't exist, or it
  belongs to someone else — indistinguishable by design, since the read
  policy's `access_type :filter` excludes non-owned rows from the query
  rather than raising, precisely to avoid an enumeration oracle) is treated
  uniformly as "not accessible to this actor" and handled as an
  authorization-flavored denial: a flash error plus a redirect to `/tabs`,
  never a silent crash into Phoenix's generic error page (issue #10's
  explicit acceptance criterion).

  ## The measure/note grid (issue #11)

  Below the metadata form, the editor renders a grid of compassos (see
  `PonteioWeb.TabLive.MeasureEditorComponent`) for entering notes as
  corda/casa pairs. As explained in issue #11/#12/#14's "Persistência"
  notes, this grid does **not** round-trip to `Ponteio.Tablatures.Measure`/
  `Note` on every note typed — it keeps the whole editor's compassos/notas
  as local assigns (`@measures`) here in the LiveView, and only the future
  `upsert_measure_notes` bulk action (issue #14) will persist that tree in
  one shot when the user saves. That's also why `:new` and `:edit` both
  start from the same single, empty "Compasso 1" — there's nothing to load
  from the database either way (no `Measure` row is ever written by this
  LiveView).

  ## Adding/splitting compassos (issue #12)

  Two ways a second (or Nth) `measure-card` comes to exist, both purely
  local-state operations on `@measures`, per the same deferred-persistence
  note above:

    * **"+ Adicionar compasso"** appends one empty measure after the last
      one, `position` = previous last + 1.
    * **"Quebrar compasso aqui"** (one scissors button per column inside
      `MeasureEditorComponent`, `break_measure` event) splits an existing
      measure at a given column: notes at that column and after move,
      keeping their relative order, into a brand-new measure inserted
      right after the one being split; every measure's `position` is then
      recomputed from its new list index (1-based) so positions stay a
      contiguous, gap-free sequence no matter where in the middle the
      split happened.

  Each measure keeps a `id` that is stable and independent of `position`
  (`next_measure_seq` hands out the next one) — `position` gets rewritten
  on every split/reindex, but `id` is what `phx-value-measure` and DOM ids
  key off of, so it must never change under an already-rendered card.

  ## Editing/removing notes and measures (issue #13)

  `@editing` now holds either shape, distinguished by tuple arity so both
  can share the one assign without ambiguity:

    * `{measure_id, string_number}` — the issue #11 "insert a new note in
      the trailing column" flow, unchanged.
    * `{measure_id, :edit, position}` — new: editing an **existing** note
      (clicking its chip opens an inline form, `MeasureEditorComponent`'s
      `cell/1`, with a corda `<select>` and a casa number input instead
      of the single fret input the trailing flow uses, since either
      field — or both — may change). Deliberately keyed by `position`
      alone, not `string_number`: if editing changed the note's string,
      keying by the *old* string would stop matching the note's new cell
      the moment it re-rendered on a different row, silently closing the
      form out from under the user.

  `update_note/4` looks the note up by `{measure_id, position}` alone
  (never by its old `string_number`) because the insertion model
  guarantees at most one note per position within a measure — position is
  insertion order, not a per-string slot — so position alone is already a
  unique key. `delete_note/2` removes the note at a given position and
  renumbers the rest of that measure's notes from their new list order,
  the same "recompute positions from list index" trick `reindex_measures/1`
  already uses for measures.

  `remove_measure/2` implements the issue's merge rule: a removed
  measure's notes are folded into an adjacent measure rather than
  discarded, preserving chronological order —

    * removing any measure but the first appends its notes after the
      **previous** measure's own notes (the previous measure was played
      first);
    * removing the first measure prepends its notes before the **next**
      measure's own notes instead (symmetric reasoning: the removed
      measure was played first), and that next measure becomes the new
      first.

  Either way every surviving measure is renumbered by `reindex_measures/1`
  afterwards. A tablature must always keep at least one measure, so
  `MeasureEditorComponent` only renders the remove-measure control when
  more than one measure exists (`removable?`) — there is deliberately no
  server-side guard beyond that, mirroring how `start_note`/`break_measure`
  already treat a stale/unknown id as a silent no-op rather than raising.
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  alias Ponteio.Tablatures.Tab
  alias PonteioWeb.TabLive.MeasureEditorComponent

  # Deliberately non-committal about *why* (issue #10): confirming "it
  # belongs to someone else" would itself leak that the id exists, which is
  # exactly what the read policy's filter-based scoping is designed to
  # avoid (Ash's documented rationale for `access_type :filter` on reads).
  @not_accessible_flash "Tablatura não encontrada ou você não tem permissão para acessá-la."

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_for_action(socket.assigns.live_action, params)
     |> assign(
       measures: [%{id: "measure-1", position: 1, notes: []}],
       editing: nil,
       next_measure_seq: 2
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between gap-4">
        <h1 class="text-2xl font-semibold">{heading(@live_action)}</h1>
        <.link navigate={~p"/tabs"} class="btn btn-ghost">Cancelar</.link>
      </div>

      <.form
        for={@form}
        id="tab-editor-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-2 max-w-md"
      >
        <.input field={@form[:title]} type="text" label="Título" required />
        <.input field={@form[:artist]} type="text" label="Artista" required />
        <.input
          field={@form[:capo_fret]}
          type="number"
          label="Capotraste"
          min="0"
          step="1"
          required
        />
        <p class="text-sm text-base-content/70">0 = sem capotraste.</p>

        <.button variant="primary" phx-disable-with="Salvando...">
          Salvar
        </.button>
      </.form>

      <h2 class="text-lg font-semibold mt-8 mb-2">Notas</h2>
      <MeasureEditorComponent.measure_editor
        :for={measure <- @measures}
        measure={measure}
        editing={@editing}
        removable?={length(@measures) > 1}
      />

      <button type="button" class="btn btn-ghost" phx-click="add_measure">
        + Adicionar compasso
      </button>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("start_note", %{"measure" => measure_id, "string" => string}, socket) do
    {:noreply, assign(socket, editing: {measure_id, String.to_integer(string)})}
  end

  def handle_event(
        "confirm_note",
        %{"measure" => measure_id, "string" => string, "value" => value},
        socket
      ) do
    string_number = String.to_integer(string)

    measures =
      case parse_fret(value) do
        {:ok, fret} -> add_note(socket.assigns.measures, measure_id, string_number, fret)
        :error -> socket.assigns.measures
      end

    {:noreply, assign(socket, measures: measures, editing: nil)}
  end

  def handle_event("add_measure", _params, socket) do
    measures = socket.assigns.measures
    seq = socket.assigns.next_measure_seq

    new_measure = %{id: "measure-#{seq}", position: length(measures) + 1, notes: []}

    {:noreply, assign(socket, measures: measures ++ [new_measure], next_measure_seq: seq + 1)}
  end

  def handle_event(
        "break_measure",
        %{"measure" => measure_id, "column" => column},
        socket
      ) do
    column = String.to_integer(column)
    seq = socket.assigns.next_measure_seq

    {measures, seq} = split_measure(socket.assigns.measures, measure_id, column, seq)

    {:noreply, assign(socket, measures: measures, next_measure_seq: seq)}
  end

  def handle_event(
        "start_edit_note",
        %{"measure" => measure_id, "position" => position},
        socket
      ) do
    editing = {measure_id, :edit, String.to_integer(position)}

    {:noreply, assign(socket, editing: editing)}
  end

  def handle_event(
        "confirm_edit_note",
        %{
          "measure" => measure_id,
          "position" => position,
          "note" => %{"string" => string, "fret" => fret}
        },
        socket
      ) do
    position = String.to_integer(position)

    measures =
      with {:ok, string_number} <- parse_string_number(string),
           {:ok, fret_number} <- parse_fret(fret) do
        update_note(socket.assigns.measures, measure_id, position, string_number, fret_number)
      else
        :error -> socket.assigns.measures
      end

    {:noreply, assign(socket, measures: measures, editing: nil)}
  end

  def handle_event(
        "remove_note",
        %{"measure" => measure_id, "position" => position},
        socket
      ) do
    measures = delete_note(socket.assigns.measures, measure_id, String.to_integer(position))

    {:noreply, assign(socket, measures: measures, editing: nil)}
  end

  def handle_event("remove_measure", %{"measure" => measure_id}, socket) do
    measures = remove_measure(socket.assigns.measures, measure_id)

    {:noreply, assign(socket, measures: measures)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, tab} ->
        {:noreply,
         socket
         |> put_flash(:info, save_flash(socket.assigns.live_action, tab))
         |> redirect(to: ~p"/tabs")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp assign_for_action(socket, :new, _params) do
    form = build_create_form(socket.assigns.current_user)

    assign(socket, form: form, page_title: "Nova tablatura")
  end

  defp assign_for_action(socket, :edit, %{"id" => id}) do
    user = socket.assigns.current_user

    case Ash.get(Tab, id, actor: user, domain: Ponteio.Tablatures) do
      {:ok, tab} ->
        form = build_update_form(tab, user)

        assign(socket, form: form, page_title: "Editar tablatura")

      {:error, _error} ->
        socket
        |> put_flash(:error, @not_accessible_flash)
        |> redirect(to: ~p"/tabs")
    end
  end

  defp build_create_form(user) do
    Tab
    |> AshPhoenix.Form.for_create(:create, actor: user, domain: Ponteio.Tablatures)
    |> to_form()
  end

  defp build_update_form(tab, user) do
    tab
    |> AshPhoenix.Form.for_update(:update, actor: user, domain: Ponteio.Tablatures)
    |> to_form()
  end

  # Only a non-negative integer, with nothing left over, confirms a note
  # (issue #11's grid cell). Anything else (empty, negative, non-numeric)
  # silently cancels the in-progress edit instead of creating a note —
  # there's no dedicated error path for this local-only, not-yet-persisted
  # input.
  defp parse_fret(value) do
    case Integer.parse(String.trim(to_string(value))) do
      {fret, ""} when fret >= 0 -> {:ok, fret}
      _ -> :error
    end
  end

  # Mirrors parse_fret/1's "silently cancel instead of erroring" contract,
  # but bounded to the six playable strings (issue #13's corda select only
  # ever submits 1..6, this guards a hand-crafted request the same way).
  defp parse_string_number(value) do
    case Integer.parse(String.trim(to_string(value))) do
      {string_number, ""} when string_number in 1..6 -> {:ok, string_number}
      _ -> :error
    end
  end

  # Appends a note to the given measure's local note list. `position` is
  # the note's index within that list — i.e. insertion order, per this
  # issue's acceptance criterion — not a musical time value.
  defp add_note(measures, measure_id, string_number, fret_number) do
    Enum.map(measures, fn
      %{id: ^measure_id} = measure ->
        note = %{
          string_number: string_number,
          fret_number: fret_number,
          position: length(measure.notes)
        }

        %{measure | notes: measure.notes ++ [note]}

      measure ->
        measure
    end)
  end

  # Updates the corda/casa of the note at `position` within `measure_id`
  # (issue #13, "alterar corda/casa de uma nota existente"). Looked up by
  # position alone — never by the note's old string_number — because the
  # insertion flow (issue #11) guarantees at most one note per position in
  # a measure, so position is already a unique key on its own. An unknown
  # measure_id/position (stale DOM event) is a no-op, same convention as
  # split_measure/4.
  defp update_note(measures, measure_id, position, string_number, fret_number) do
    Enum.map(measures, fn
      %{id: ^measure_id} = measure ->
        notes =
          Enum.map(measure.notes, fn
            %{position: ^position} = note ->
              %{note | string_number: string_number, fret_number: fret_number}

            note ->
              note
          end)

        %{measure | notes: notes}

      measure ->
        measure
    end)
  end

  # Removes the note at `position` within `measure_id` (issue #13,
  # "remover uma nota"), then renumbers the remaining notes' `position`
  # from their new list order so they stay a contiguous, gap-free sequence
  # — the same "recompute from list index" trick reindex_measures/1 uses
  # for measures. An unknown measure_id/position is a no-op.
  defp delete_note(measures, measure_id, position) do
    Enum.map(measures, fn
      %{id: ^measure_id} = measure ->
        notes =
          measure.notes
          |> Enum.reject(&(&1.position == position))
          |> Enum.sort_by(& &1.position)
          |> Enum.with_index()
          |> Enum.map(fn {note, position} -> %{note | position: position} end)

        %{measure | notes: notes}

      measure ->
        measure
    end)
  end

  # Removes `measure_id`'s marker (issue #13, "remover um marcador de
  # compasso") by folding its notes into an adjacent measure, preserving
  # chronological order:
  #
  #   * any measure but the first merges into the PREVIOUS one, its notes
  #     appended after the previous measure's own notes (the previous
  #     measure was played first);
  #   * the first measure merges into the NEXT one instead, its notes
  #     prepended before the next measure's own notes (symmetric
  #     reasoning: the removed first measure was played first) — that
  #     next measure becomes the new first.
  #
  # Either branch renumbers the merged notes' `position` from their new
  # list order, then reindex_measures/1 renumbers every surviving
  # measure's `position`. A single remaining measure has no adjacent
  # measure to merge into — the UI never renders the remove control in
  # that case (see `removable?` in MeasureEditorComponent), so this is a
  # no-op rather than a guard, same convention as split_measure/4 for an
  # unknown measure_id.
  defp remove_measure(measures, measure_id) do
    case Enum.find_index(measures, &(&1.id == measure_id)) do
      nil ->
        measures

      0 ->
        case measures do
          [removed, next | rest] ->
            # `next` survives (its id, not `removed`'s) and becomes the new
            # first — `removed`'s notes are prepended before its own.
            [merge_notes(next, removed.notes, next.notes) | rest] |> reindex_measures()

          [_only] ->
            measures
        end

      index ->
        removed = Enum.at(measures, index)
        previous = Enum.at(measures, index - 1)
        # `previous` survives — `removed`'s notes are appended after its own.
        merged = merge_notes(previous, previous.notes, removed.notes)

        measures
        |> List.replace_at(index - 1, merged)
        |> List.delete_at(index)
        |> reindex_measures()
    end
  end

  # Builds the merged measure that survives a remove_measure/2 fold: it
  # keeps `keep_measure`'s own id (not the removed measure's — the id is
  # only a local editor handle, but keeping the *surviving* one's is what
  # makes "the next measure becomes the new first" true rather than just
  # cosmetically true), with `notes_before ++ notes_after` renumbered from
  # their new list order.
  defp merge_notes(keep_measure, notes_before, notes_after) do
    notes =
      (notes_before ++ notes_after)
      |> Enum.with_index()
      |> Enum.map(fn {note, position} -> %{note | position: position} end)

    %{keep_measure | notes: notes}
  end

  # Splits `measure_id`'s notes at `column` (issue #12, "Quebrar compasso
  # aqui"): notes whose `position` is >= column move, in their original
  # relative order, into a brand-new measure inserted right after the one
  # being split, renumbered from 0 within that new measure. Notes that stay
  # behind keep their `position` unchanged. Every measure's `position` is
  # then recomputed from its list index so the whole tablature stays a
  # contiguous, 1-based sequence regardless of where the split landed.
  #
  # An unknown `measure_id` (stale DOM event) is a no-op: the list and
  # sequence counter come back untouched.
  defp split_measure(measures, measure_id, column, seq) do
    case Enum.find_index(measures, &(&1.id == measure_id)) do
      nil ->
        {measures, seq}

      index ->
        measure = Enum.at(measures, index)
        {kept_notes, moved_notes} = Enum.split_with(measure.notes, &(&1.position < column))

        moved_notes =
          moved_notes
          |> Enum.sort_by(& &1.position)
          |> Enum.with_index()
          |> Enum.map(fn {note, position} -> %{note | position: position} end)

        updated_measure = %{measure | notes: kept_notes}
        new_measure = %{id: "measure-#{seq}", position: 0, notes: moved_notes}

        measures =
          measures
          |> List.replace_at(index, updated_measure)
          |> List.insert_at(index + 1, new_measure)
          |> reindex_measures()

        {measures, seq + 1}
    end
  end

  defp reindex_measures(measures) do
    measures
    |> Enum.with_index(1)
    |> Enum.map(fn {measure, position} -> %{measure | position: position} end)
  end

  defp heading(:new), do: "Nova tablatura"
  defp heading(:edit), do: "Editar tablatura"

  defp save_flash(:new, tab), do: "Tablatura \"#{tab.title}\" criada."
  defp save_flash(:edit, tab), do: "Tablatura \"#{tab.title}\" atualizada."
end
