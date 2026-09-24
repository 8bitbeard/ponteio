defmodule PonteioWeb.TabLive.Index do
  @moduledoc """
  `GET /tabs` — "Minhas tablaturas" (issue #7, PRD §6.2, SDD §4, §7).

  Lists the authenticated actor's own tablatures via
  `Ponteio.Tablatures.list_tabs_for_user/1` (SDD §5) — scoping to the owner
  comes entirely from the `Tab` resource's read policy (SDD §2.2), not from
  a manual filter here.

  The row's "Editar" shortcut uses `~p"/tabs/\#{tab.id}/edit"` now that
  issue #8 ("Editar metadados") added that route. "Estudar" is still a
  plain path (not the `~p` sigil): `/tabs/:id/study` doesn't exist yet —
  it lands with issue #22 ("Visualizar tablatura completa"). `~p` is
  compile-time verified against the router, so using it here for a route
  that doesn't exist yet would fail to compile; a plain path keeps the
  shortcut visible now (matching the mockup, Tela 1) and starts working
  the moment that issue adds its route.

  "Excluir" (issue #9, PRD §6.2) requires confirmation via the browser's
  native `data-confirm` prompt (an explicit acceptance criterion) before it
  even pushes the `"delete"` LiveView event, then deletes through
  `Ponteio.Tablatures.delete_tab/2` (SDD §2.2) — scoped to the
  authenticated actor both by fetching the record with `Ash.get!/3` and by
  the `Tab` resource's own `:destroy` policy, so a forged id for another
  user's tablature raises (via `Ash.get!/3`) rather than silently
  succeeding or deleting the wrong tablature.
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  alias Ponteio.Tablatures
  alias Ponteio.Tablatures.Tab

  @impl true
  def mount(_params, _session, socket) do
    {:ok, tabs} = Tablatures.list_tabs_for_user(actor: socket.assigns.current_user)

    {:ok, assign(socket, tabs: tabs, page_title: "Minhas tablaturas")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user
    tab = Ash.get!(Tab, id, actor: user, domain: Ponteio.Tablatures)

    case Tablatures.delete_tab(tab, actor: user) do
      :ok ->
        {:ok, tabs} = Tablatures.list_tabs_for_user(actor: user)

        {:noreply,
         socket
         |> put_flash(:info, "Tablatura \"#{tab.title}\" excluída.")
         |> assign(tabs: tabs)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Não foi possível excluir a tablatura.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between gap-4">
        <h1 class="text-2xl font-semibold">Minhas tablaturas</h1>
        <.link navigate={~p"/tabs/new"} class="btn btn-primary">+ Nova tablatura</.link>
      </div>

      <p :if={@tabs == []} id="tabs-empty-state" class="text-base-content/70">
        Você ainda não tem nenhuma tablatura.
      </p>

      <.table :if={@tabs != []} id="tabs" rows={@tabs}>
        <:col :let={tab} label="Título">{tab.title}</:col>
        <:col :let={tab} label="Artista">{tab.artist}</:col>
        <:col :let={tab} label="Capotraste">{capo_label(tab.capo_fret)}</:col>
        <:col :let={tab} label="Status">
          <span class={["badge", status_badge_class(tab.status)]}>
            {status_label(tab.status)}
          </span>
        </:col>
        <:action :let={tab}>
          <.link :if={tab.status == :ready} navigate={"/tabs/#{tab.id}/study"} class="link">
            Estudar
          </.link>
          <.link navigate={~p"/tabs/#{tab.id}/edit"} class="link">Editar</.link>
          <.link
            phx-click="delete"
            phx-value-id={tab.id}
            data-confirm="Excluir esta tablatura? Essa ação não pode ser desfeita."
            class="link text-error"
          >
            Excluir
          </.link>
        </:action>
      </.table>

      <.link navigate={~p"/account/password"} class="link">Trocar senha</.link>
    </Layouts.app>
    """
  end

  defp capo_label(0), do: "Sem capo"
  defp capo_label(fret), do: "Capo #{fret}ª"

  defp status_label(:draft), do: "Rascunho"
  defp status_label(:analyzing), do: "Analisando"
  defp status_label(:ready), do: "Pronta"

  defp status_badge_class(:draft), do: "badge-ghost"
  defp status_badge_class(:analyzing), do: "badge-warning"
  defp status_badge_class(:ready), do: "badge-success"
end
