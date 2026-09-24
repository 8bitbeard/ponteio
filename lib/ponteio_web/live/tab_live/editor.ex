defmodule PonteioWeb.TabLive.Editor do
  @moduledoc """
  `GET /tabs/new` and `GET /tabs/:id/edit` — "Editor" screen, both the
  creation (issue #6) and metadata-edit (issue #8) flows, per PRD §6.2,
  SDD §4, §7.

  The two routes share this module, differentiated by `live_action`
  (`:new` vs `:edit`, SDD §7): the metadata form (title, artist, capo
  position) is identical either way, backed by an `AshPhoenix.Form` around
  the `Ponteio.Tablatures.Tab` resource's `:create` or `:update` action.
  For `:edit`, the tablature is loaded first (scoped to its owner by the
  resource's read policy — a non-owner or unknown id surfaces as a 404 via
  `Ash.get!/3`, not a silent form) and the form comes pre-filled from it.

  The measure/note grid from the mockup's Editor screen belongs to a
  future issue once the `Measure`/`Note` resources exist.
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  alias Ponteio.Tablatures.Tab

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign_for_action(socket, socket.assigns.live_action, params)}
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
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply, assign(socket, form: form)}
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

  defp heading(:new), do: "Nova tablatura"
  defp heading(:edit), do: "Editar tablatura"

  defp save_flash(:new, tab), do: "Tablatura \"#{tab.title}\" criada."
  defp save_flash(:edit, tab), do: "Tablatura \"#{tab.title}\" atualizada."
end
