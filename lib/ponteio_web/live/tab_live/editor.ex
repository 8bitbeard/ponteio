defmodule PonteioWeb.TabLive.Editor do
  @moduledoc """
  `GET /tabs/new` — "Editor" screen, creation flow (issue #6, PRD §6.2,
  SDD §4, §7).

  Builds an `AshPhoenix.Form` around the `Ponteio.Tablatures.Tab` resource's
  `:create` action for the tablature's metadata (title, artist, capo
  position) — the measure/note grid from the mockup's Editor screen belongs
  to a future issue once the `Measure`/`Note` resources exist.

  Per SDD §7, `TabLive.Editor` also serves `GET /tabs/:id/edit` (via
  `live_action :edit`) once issue #8 ("Editar metadados de uma tablatura")
  implements it — this module only handles `:new` for now.
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    form = build_form(socket.assigns.current_user)

    {:ok, assign(socket, form: form, page_title: "Nova tablatura")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between gap-4">
        <h1 class="text-2xl font-semibold">Nova tablatura</h1>
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
         |> put_flash(:info, "Tablatura \"#{tab.title}\" criada.")
         |> redirect(to: ~p"/tabs")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp build_form(user) do
    Ponteio.Tablatures.Tab
    |> AshPhoenix.Form.for_create(:create, actor: user, domain: Ponteio.Tablatures)
    |> to_form()
  end
end
