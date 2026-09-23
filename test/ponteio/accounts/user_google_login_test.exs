defmodule Ponteio.Accounts.UserGoogleLoginTest do
  @moduledoc """
  Covers the `:register_with_google` action of `Ponteio.Accounts.User`
  (issue #5, PRD §6.1, SDD §2.1, `strategies :google`): create-or-link a
  `User` from the `user_info`/`oauth_tokens` an OAuth2 callback would hand
  to `AshAuthentication`, without any actual HTTP call — the `iss`/`sub`
  claims and e-mail are supplied directly as plain maps here, the same
  shape `AshAuthentication.Strategy.OAuth2.Plug.callback/2` builds after
  the (separately, HTTP-stubbed) token exchange and userinfo fetch. See
  `PonteioWeb.GoogleSignInTest` for the end-to-end HTTP flow.

  Exercised through `AshAuthentication.Strategy.action/3`, the same entry
  point the generated `AuthController` uses, per SDD §6 ("Resources:
  testes de ação via Ash.create!/... diretamente, sem passar por
  LiveView").
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User

  defp strategy, do: AshAuthentication.Info.strategy!(User, :google)

  defp register(user_info, uid \\ "sub-123") do
    AshAuthentication.Strategy.action(strategy(), :register, %{
      user_info: user_info,
      oauth_tokens: %{"access_token" => "irrelevant-for-this-test", "uid" => uid}
    })
  end

  describe "register_with_google" do
    test "creates a new, already-confirmed user with no password" do
      assert {:ok, user} =
               register(%{
                 "email" => "novo.no.google@ponteio.app",
                 "sub" => "google-sub-1",
                 "email_verified" => true
               })

      assert to_string(user.email) == "novo.no.google@ponteio.app"
      assert user.hashed_password == nil
      assert user.confirmed_at != nil
      assert user.__metadata__.token
    end

    test "a returning Google sign-in (same e-mail) links to the existing account, not a duplicate" do
      assert {:ok, first} =
               register(%{
                 "email" => "recorrente@ponteio.app",
                 "sub" => "google-sub-2",
                 "email_verified" => true
               })

      assert {:ok, second} =
               register(%{
                 "email" => "recorrente@ponteio.app",
                 "sub" => "google-sub-2",
                 "email_verified" => true
               })

      assert first.id == second.id

      assert Ponteio.Repo.aggregate(User, :count, :id) == 1
    end

    test "a Google sign-in whose verified e-mail matches an existing, confirmed password account links to it" do
      {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")

      # `prevent_hijacking?` (default true on the `google` strategy) only
      # auto-links a Google sign-in to an account that has already confirmed
      # this same e-mail through its own flow — otherwise an attacker could
      # take over an account by Google-signing-in with an e-mail its owner
      # never actually confirmed. So the existing account must be confirmed
      # here to exercise the "links, doesn't duplicate" path this test is for.
      existing =
        Ash.Seed.seed!(User, %{
          email: "ja-tinha-senha@ponteio.app",
          hashed_password: hashed_password,
          confirmed_at: DateTime.utc_now()
        })

      assert {:ok, linked} =
               register(%{
                 "email" => "ja-tinha-senha@ponteio.app",
                 "sub" => "google-sub-3",
                 "email_verified" => true
               })

      assert linked.id == existing.id
      # the password credential is left untouched by the Google link
      assert linked.hashed_password == hashed_password
    end
  end
end
