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
  For `:edit`, the tablature is loaded first (scoped to its owner by the
  resource's read policy — a non-owner or unknown id surfaces as a 404 via
  `Ash.get!/3`, not a silent form) and the form comes pre-filled from it.

  ## The measure/note grid (issue #11)

  Below the metadata form, the editor renders a grid of compassos (see
  `PonteioWeb.TabLive.MeasureEditorComponent`) for entering notes as
  corda/casa pairs. As explained in issue #11/#12/#14's "Persistência"
  notes, this grid does **not** round-trip to `Ponteio.Tablatures.Measure`/
  `Note` on every note typed — it keeps the whole editor's compassos/notas
  as local assigns (`@measures`) here in the LiveView, and only the future
  `upsert_measure_notes` bulk action (issue #14) will persist that tree in
  one shot when the user saves. That's also why `:new` and `:edit` both
  start from the same single, empty "Compasso 1" — issue #12 ("Inserir
  marcadores de compasso") is what adds the "+Adicionar compasso" affordance
  for more than one; until then there's nothing to load from the database
  either way (no `Measure` row is ever written by this issue).
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  alias Ponteio.Tablatures.Tab
  alias PonteioWeb.TabLive.MeasureEditorComponent

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign_for_action(socket.assigns.live_action, params)
     |> assign(measures: [%{id: "measure-1", position: 1, notes: []}], editing: nil)}
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
      />
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
    tab = Ash.get!(Tab, id, actor: user, domain: Ponteio.Tablatures)
    form = build_update_form(tab, user)

    assign(socket, form: form, page_title: "Editar tablatura")
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

  defp heading(:new), do: "Nova tablatura"
  defp heading(:edit), do: "Editar tablatura"

  defp save_flash(:new, tab), do: "Tablatura \"#{tab.title}\" criada."
  defp save_flash(:edit, tab), do: "Tablatura \"#{tab.title}\" atualizada."
end
