defmodule Ponteio.Accounts.UserChangePasswordTest do
  @moduledoc """
  Covers the `:change_password` action of `Ponteio.Accounts.User` (issue #4,
  PRD §6.1's third acceptance criterion: "Usuário autenticado consegue
  trocar a senha atual"). Exercised via `Ash.update/2` directly on the
  resource (SDD §6), the same call `PonteioWeb.UserLive.ChangePassword`'s
  `AshPhoenix.Form` makes.
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User

  @password "supersecret123"
  @new_password "outrasenha456"

  defp strategy, do: AshAuthentication.Info.strategy!(User, :password)

  defp register(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(@password)

    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp sign_in(params), do: AshAuthentication.Strategy.action(strategy(), :sign_in, params)

  defp change_password(user, params, opts) do
    user
    |> Ash.Changeset.for_update(:change_password, params, opts)
    |> Ash.update()
  end

  describe "change_password" do
    test "updates the password when the current password is correct" do
      user = register("trocalogada@ponteio.app")

      assert {:ok, updated} =
               change_password(
                 user,
                 %{
                   current_password: @password,
                   password: @new_password,
                   password_confirmation: @new_password
                 },
                 actor: user
               )

      assert updated.hashed_password != user.hashed_password

      assert {:ok, _} = sign_in(%{email: user.email, password: @new_password})
      assert {:error, _} = sign_in(%{email: user.email, password: @password})
    end

    test "rejects an incorrect current password" do
      user = register("senhaerradalogada@ponteio.app")

      assert {:error, error} =
               change_password(
                 user,
                 %{
                   current_password: "senha-errada-qualquer",
                   password: @new_password,
                   password_confirmation: @new_password
                 },
                 actor: user
               )

      assert error_on_field?(error, :current_password)

      # the password must remain unchanged
      assert {:ok, _} = sign_in(%{email: user.email, password: @password})
    end

    test "rejects a password/confirmation mismatch" do
      user = register("conferelogada@ponteio.app")

      assert {:error, error} =
               change_password(
                 user,
                 %{
                   current_password: @password,
                   password: @new_password,
                   password_confirmation: "outravalor789"
                 },
                 actor: user
               )

      assert error_on_field?(error, :password_confirmation)
    end

    test "a user cannot change another user's password (policy)" do
      user = register("vitima@ponteio.app")
      attacker = register("atacante@ponteio.app")

      assert {:error, %Ash.Error.Forbidden{}} =
               change_password(
                 user,
                 %{
                   current_password: @password,
                   password: @new_password,
                   password_confirmation: @new_password
                 },
                 actor: attacker
               )

      # the victim's password must remain unchanged
      assert {:ok, _} = sign_in(%{email: user.email, password: @password})
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
