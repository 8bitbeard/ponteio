defmodule Ponteio.Accounts.UserPasswordResetTest do
  @moduledoc """
  Covers the "esqueci minha senha" flow of `Ponteio.Accounts.User` (issue #4,
  PRD §6.1, SDD §2.1 add-on `resettable`): requesting a reset token by
  e-mail and setting a new password from that token.

  Exercised through `AshAuthentication.Strategy.action/3` — the same entry
  point the generated `/reset` and `/password-reset/:token` LiveViews
  (`sign_in_route`/`reset_route` in the router) use — per SDD §6 ("Resources:
  testes de ação via Ash.create!/... diretamente, sem passar por LiveView").
  """

  use Ponteio.DataCase, async: true

  import Swoosh.TestAssertions

  alias Ponteio.Accounts.User

  @password "supersecret123"
  @new_password "outrasenha456"

  defp strategy, do: AshAuthentication.Info.strategy!(User, :password)

  defp register(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(@password)

    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp request_reset(email),
    do: AshAuthentication.Strategy.action(strategy(), :reset_request, %{"email" => email})

  defp reset(params), do: AshAuthentication.Strategy.action(strategy(), :reset, params)

  defp sign_in(params), do: AshAuthentication.Strategy.action(strategy(), :sign_in, params)

  # Pulls the reset token out of the link the sender embeds in the e-mail
  # body (`Ponteio.Accounts.User.Senders.SendPasswordResetEmail`, which
  # points at `/password-reset/:token`).
  defp token_from_sent_email do
    {:email, email} = assert_email_sent()
    [_, token] = Regex.run(~r{/password-reset/([^"<\s]+)}, email.html_body)
    token
  end

  describe "request_password_reset_token" do
    test "sends a reset e-mail with a token link for an existing user" do
      register("recupera@ponteio.app")

      assert :ok = request_reset("recupera@ponteio.app")

      {:email, email} = assert_email_sent()
      assert to_string(email.subject) =~ "Reset"
      assert Enum.any?(email.to, fn {_name, address} -> address == "recupera@ponteio.app" end)
    end

    test "does not error for an unknown e-mail (avoids account enumeration)" do
      assert :ok = request_reset("naoexiste@ponteio.app")

      refute_email_sent()
    end
  end

  describe "reset_password_with_token" do
    test "sets a new password given a valid reset token, invalidating the old one" do
      user = register("trocar@ponteio.app")
      :ok = request_reset(to_string(user.email))
      token = token_from_sent_email()

      assert {:ok, updated} =
               reset(%{
                 "reset_token" => token,
                 "password" => @new_password,
                 "password_confirmation" => @new_password
               })

      assert updated.id == user.id
      assert updated.hashed_password != user.hashed_password

      assert {:ok, _} = sign_in(%{email: user.email, password: @new_password})
      assert {:error, _} = sign_in(%{email: user.email, password: @password})
    end

    test "rejects an invalid/garbage token" do
      assert {:error, _reason} =
               reset(%{
                 "reset_token" => "not-a-real-token",
                 "password" => @new_password,
                 "password_confirmation" => @new_password
               })
    end

    test "rejects a password/confirmation mismatch" do
      user = register("confere-reset@ponteio.app")
      :ok = request_reset(to_string(user.email))
      token = token_from_sent_email()

      assert {:error, error} =
               reset(%{
                 "reset_token" => token,
                 "password" => @new_password,
                 "password_confirmation" => "outravalor789"
               })

      assert error_on_field?(error, :password_confirmation)
    end

    test "a reset token can only be used once" do
      user = register("usaunicavez@ponteio.app")
      :ok = request_reset(to_string(user.email))
      token = token_from_sent_email()

      assert {:ok, _updated} =
               reset(%{
                 "reset_token" => token,
                 "password" => @new_password,
                 "password_confirmation" => @new_password
               })

      assert {:error, _reason} =
               reset(%{
                 "reset_token" => token,
                 "password" => "maisumaoutra999",
                 "password_confirmation" => "maisumaoutra999"
               })
    end
  end

  defp error_on_field?(%{errors: errors}, field) when is_list(errors) do
    Enum.any?(errors, fn error -> Map.get(error, :field) == field end)
  end

  defp error_on_field?(error, field) when is_exception(error) do
    error
    |> List.wrap()
    |> Enum.any?(fn e -> Map.get(e, :field) == field end)
  end
end
