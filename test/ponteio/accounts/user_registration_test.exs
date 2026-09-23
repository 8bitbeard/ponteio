defmodule Ponteio.Accounts.UserRegistrationTest do
  @moduledoc """
  Covers the `:register_with_password` action of `Ponteio.Accounts.User`
  (per issue #2, PRD §6.1, SDD §2.1): sign up with e-mail + senha via the
  `AshAuthentication` `:password` strategy.

  Exercised through `AshAuthentication.Strategy.action/3`, the same entry
  point used by the generated `AuthController`/`sign_in_route` LiveView, per
  SDD §6 ("Resources: testes de ação via Ash.create!/... diretamente, sem
  passar por LiveView").
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User

  defp strategy, do: AshAuthentication.Info.strategy!(User, :password)

  defp register(params) do
    AshAuthentication.Strategy.action(strategy(), :register, params)
  end

  describe "register_with_password" do
    test "creates a user with a valid e-mail and password" do
      assert {:ok, user} =
               register(%{
                 "email" => "nova@ponteio.app",
                 "password" => "supersecret123",
                 "password_confirmation" => "supersecret123"
               })

      assert to_string(user.email) == "nova@ponteio.app"
      assert user.hashed_password != "supersecret123"
      assert user.hashed_password != nil
      # confirmation add-on requires interaction before the account is
      # considered fully confirmed, per SDD §2.1 ("add-ons confirmation").
      assert user.confirmed_at == nil
    end

    test "rejects a duplicate e-mail (unique identity)" do
      assert {:ok, _user} =
               register(%{
                 "email" => "duplicada@ponteio.app",
                 "password" => "supersecret123",
                 "password_confirmation" => "supersecret123"
               })

      assert {:error, error} =
               register(%{
                 "email" => "duplicada@ponteio.app",
                 "password" => "outrasenha123",
                 "password_confirmation" => "outrasenha123"
               })

      assert error_on_field?(error, :email)
    end

    test "rejects an e-mail that only differs by case (citext identity)" do
      assert {:ok, _user} =
               register(%{
                 "email" => "MaiuUsculo@ponteio.app",
                 "password" => "supersecret123",
                 "password_confirmation" => "supersecret123"
               })

      assert {:error, error} =
               register(%{
                 "email" => "maiuusculo@ponteio.app",
                 "password" => "supersecret123",
                 "password_confirmation" => "supersecret123"
               })

      assert error_on_field?(error, :email)
    end

    test "rejects a password shorter than the minimum length" do
      assert {:error, error} =
               register(%{
                 "email" => "curtinha@ponteio.app",
                 "password" => "short1",
                 "password_confirmation" => "short1"
               })

      assert error_on_field?(error, :password)
    end

    test "rejects a password/confirmation mismatch" do
      assert {:error, error} =
               register(%{
                 "email" => "confere@ponteio.app",
                 "password" => "supersecret123",
                 "password_confirmation" => "outrasenha123"
               })

      assert error_on_field?(error, :password_confirmation)
    end

    test "rejects missing e-mail or password" do
      assert {:error, _error} = register(%{"password" => "supersecret123"})
      assert {:error, _error} = register(%{"email" => "sem-senha@ponteio.app"})
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
