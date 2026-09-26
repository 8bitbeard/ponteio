defmodule PonteioWeb.PageController do
  @moduledoc """
  `GET /` — home pública para visitante não autenticado (issue #48, PRD §6.1).

  Substitui o template default gerado pelo `mix phx.new` por uma home com
  identidade da Ponteio e CTAs para `/sign-in` e `/register`.

  O pipeline `:browser` (`lib/ponteio_web/router.ex`) já roda
  `AshAuthentication.Plug.Helpers.load_from_session/2`, então
  `conn.assigns[:current_user]` está disponível aqui sem precisar de
  LiveView nem de um `on_mount` dedicado. Quando presente, a visita a `/`
  redireciona direto para `/tabs` — a home de visitante nunca deve aparecer
  para quem já está autenticado.
  """

  use PonteioWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/tabs")
    else
      render(conn, :home)
    end
  end
end
