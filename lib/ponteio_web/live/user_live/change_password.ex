defmodule PonteioWeb.UserLive.ChangePassword do
  @moduledoc """
  `GET /account/password` — lets an authenticated user change their current
  password (issue #4, PRD §6.1, third acceptance criterion).

  Builds an `AshPhoenix.Form` around the `:change_password` action of
  `Ponteio.Accounts.User` (current password + new password + confirmation),
  per SDD §4's convention of driving LiveView forms straight off Ash actions.

  `:change_password` triggers the `log_out_everywhere` add-on, which revokes
  every token for the user — including the one backing the current session.
  So on success we send the user to `/sign-in` (a full redirect, so the
  now-invalid token is re-checked on the next request) instead of trying to
  keep them signed in.
  """

  use PonteioWeb, :live_view

  on_mount {PonteioWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    form = build_form(socket.assigns.current_user)

    {:ok, assign(socket, form: form, page_title: "Trocar senha")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-2xl font-semibold">Trocar senha</h1>
      <p class="text-base-content/70">
        Informe sua senha atual e a nova senha desejada.
      </p>

      <.form
        for={@form}
        id="change-password-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-2"
      >
        <.input
          field={@form[:current_password]}
          type="password"
          label="Senha atual"
          autocomplete="current-password"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Nova senha"
          autocomplete="new-password"
          required
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirmar nova senha"
          autocomplete="new-password"
          required
        />

        <.button variant="primary" phx-disable-with="Salvando...">
          Salvar nova senha
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
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Senha alterada com sucesso. Faça login novamente.")
         |> redirect(to: ~p"/sign-in")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp build_form(user) do
    user
    |> AshPhoenix.Form.for_update(:change_password, actor: user)
    |> to_form()
  end
end
