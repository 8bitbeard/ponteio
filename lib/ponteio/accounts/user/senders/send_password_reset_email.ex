defmodule Ponteio.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender
  use PonteioWeb, :verified_routes

  import Swoosh.Email

  alias Ponteio.Mailer

  @impl true
  def send(user, token, _) do
    new()
    # NOTE: placeholder sender address — swap for a real domain/mailbox
    # once outbound email delivery is configured (out of scope for #2).
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    url = url(~p"/password-reset/#{params[:token]}")

    """
    <p>Click this link to reset your password:</p>
    <p><a href="#{url}">#{url}</a></p>
    """
  end
end
