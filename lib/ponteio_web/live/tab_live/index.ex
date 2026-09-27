defmodule PonteioWeb.TabLive.Index do
  use PonteioWeb, :live_view

  alias Ponteio.Tablatures
  alias Ponteio.Tablatures.Tab

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Tablaturas")
     |> assign(:form, new_form())
     |> stream(:tabs, Tablatures.list_tabs!())}
  end

  defp new_form, do: Tab |> AshPhoenix.Form.for_create(:create, as: "tab") |> to_form()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Tablaturas
        <:subtitle>
          Crie uma tablatura e adicione notas para testar o motor de posições de mão.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="tab-form"
        phx-change="validate"
        phx-submit="create"
        class="flex items-start gap-2"
      >
        <div class="flex-1">
          <.input field={@form[:title]} placeholder="Título da tablatura" autocomplete="off" />
        </div>
        <.button variant="primary" id="create-tab">Criar</.button>
      </.form>

      <ul id="tabs" phx-update="stream" class="divide-y divide-base-300 mt-4">
        <li id="tabs-empty" class="hidden only:block py-3 text-sm text-base-content/60">
          Nenhuma tablatura ainda.
        </li>
        <li
          :for={{dom_id, tab} <- @streams.tabs}
          id={dom_id}
          class="flex items-center justify-between py-3"
        >
          <.link navigate={~p"/tabs/#{tab}"} class="link link-hover font-medium">{tab.title}</.link>
          <button
            id={"delete-tab-#{tab.id}"}
            type="button"
            phx-click="delete"
            phx-value-id={tab.id}
            data-confirm="Excluir esta tablatura?"
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-trash" class="size-4" />
          </button>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"tab" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("create", %{"tab" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, tab} -> {:noreply, push_navigate(socket, to: ~p"/tabs/#{tab}")}
      {:error, form} -> {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tab = Tablatures.get_tab!(id)
    Tablatures.destroy_tab!(tab)
    {:noreply, stream_delete(socket, :tabs, tab)}
  end
end
