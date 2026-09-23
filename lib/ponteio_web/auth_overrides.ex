defmodule PonteioWeb.AuthOverrides do
  @moduledoc """
  UI overrides for the `AshAuthentication.Phoenix` generated sign-in /
  register / reset-password views. Empty for now — the default markup is
  used as-is; customize here once the auth screens get their own visual
  design pass.
  """

  use AshAuthentication.Phoenix.Overrides

  # configure your UI overrides here

  # First argument to `override` is the component name you are overriding.
  # The body contains any number of configurations you wish to override
  # Below are some examples

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  # override AshAuthentication.Phoenix.Components.Banner do
  #   set :image_url, "https://media.giphy.com/media/g7GKcSzwQfugw/giphy.gif"
  #   set :text_class, "bg-red-500"
  # end

  # override AshAuthentication.Phoenix.Components.SignIn do
  #  set :show_banner, false
  # end

  @doc """
  Translates the generated sign-in page's copy for the Google button
  (issue #5, acceptance criterion "Botão \"Entrar com Google\""), passed
  as `gettext_fn` to `sign_in_route` in the router. Leaves every other
  string as-is (English default) — no other auth page copy is in scope
  of this issue.
  """
  @spec translate(String.t(), keyword) :: String.t()
  def translate(msgid, bindings \\ [])
  def translate("Sign in with Google", _bindings), do: "Entrar com Google"
  def translate(msgid, _bindings), do: msgid
end
