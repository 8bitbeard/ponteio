defmodule PonteioWeb.TabLive.Index do
  @moduledoc """
  `GET /tabs` — "Minhas tablaturas" (SDD §4, §7).

  Placeholder listing screen: this LiveView only establishes the protected
  route for `tabs` (accessible exclusively to an authenticated session, per
  the acceptance criteria of issue #3 "Login com e-mail e senha" / PRD §6.1).
  The actual tablature listing/CRUD described in SDD §4 (`TabLive.Index`)
  is implemented by the `epic:tablatures` issues (#6-#9).
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Minhas tablaturas</h1>
      <p class="text-base-content/70">
        Bem-vindo(a), {@current_user.email}. A listagem de tablaturas será implementada em breve.
      </p>
      <.link navigate={~p"/account/password"} class="link">Trocar senha</.link>
    </Layouts.app>
    """
  end
end
