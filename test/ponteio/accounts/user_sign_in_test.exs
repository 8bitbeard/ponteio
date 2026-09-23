defmodule Ponteio.Accounts.UserSignInTest do
  @moduledoc """
  Covers login via the `:password` strategy of `Ponteio.Accounts.User`
  (issue #3, PRD §6.1, SDD §2.1, §7): authenticate with e-mail + senha and
  get back a generic error on invalid credentials, without revealing
  whether the e-mail or the password was wrong.

  Exercised through `AshAuthentication.Strategy.action/3`, the same entry
  point the generated sign-in screen (`AshAuthentication.Phoenix.SignInLive`,
  mounted at `/sign-in` by `sign_in_route` in the router) uses to validate
  credentials, per SDD §6 ("Resources: testes de ação via Ash.create!/...
  diretamente, sem passar por LiveView").
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User

  @password "supersecret123"

  defp strategy, do: AshAuthentication.Info.strategy!(User, :password)

  defp register(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(@password)

    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp sign_in(params), do: AshAuthentication.Strategy.action(strategy(), :sign_in, params)

  describe "sign_in_with_password" do
    test "authenticates with the correct e-mail and password" do
      register("valida@ponteio.app")

      assert {:ok, user} = sign_in(%{email: "valida@ponteio.app", password: @password})

      assert to_string(user.email) == "valida@ponteio.app"
      assert user.__metadata__.token
    end

    test "authenticates regardless of the e-mail's case (citext identity)" do
      register("MaiuUsculo@ponteio.app")

      assert {:ok, _user} = sign_in(%{email: "maiuusculo@ponteio.app", password: @password})
    end

    test "rejects a wrong password with a generic error" do
      register("senhaerrada@ponteio.app")

      assert {:error, error} =
               sign_in(%{email: "senhaerrada@ponteio.app", password: "outrasenha123"})

      assert generic_authentication_error?(error)
    end

    test "rejects an unknown e-mail with the same generic error as a wrong password" do
      register("existe@ponteio.app")

      assert {:error, wrong_password_error} =
               sign_in(%{email: "existe@ponteio.app", password: "outrasenha123"})

      assert {:error, unknown_email_error} =
               sign_in(%{email: "naoexiste@ponteio.app", password: @password})

      assert generic_authentication_error?(wrong_password_error)
      assert generic_authentication_error?(unknown_email_error)

      # Neither error carries a `field`, and both render the same message -
      # so the caller (the sign-in screen) cannot tell whether the e-mail or
      # the password was the problem, per issue #3's acceptance criteria.
      assert Exception.message(wrong_password_error) == Exception.message(unknown_email_error)
    end

    test "rejects missing e-mail or password" do
      register("semsenha@ponteio.app")

      assert {:error, _error} = sign_in(%{password: @password})
      assert {:error, _error} = sign_in(%{email: "semsenha@ponteio.app"})
    end
  end

  # An `AshAuthentication.Errors.AuthenticationFailed` with no `field` set -
  # the library's own generic "authentication failed" shape, distinct from a
  # field-specific validation error (which would name `:email` or `:password`
  # and therefore leak which one was wrong).
  defp generic_authentication_error?(%AshAuthentication.Errors.AuthenticationFailed{field: nil}),
    do: true

  defp generic_authentication_error?(%{errors: errors}) when is_list(errors) do
    Enum.all?(errors, &generic_authentication_error?/1)
  end

  defp generic_authentication_error?(_), do: false
end
