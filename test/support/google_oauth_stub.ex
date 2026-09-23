defmodule Ponteio.Support.GoogleOAuthStub do
  @moduledoc """
  Test-only `Assent.HTTPAdapter` that stubs Google's OAuth2 token exchange
  and userinfo endpoints (issue #5), so the automated suite never depends
  on real Google credentials or hits the network.

  Wired up as `config :ash_authentication, :http_adapter` in
  `config/test.exs` — `AshAuthentication.Strategy.OAuth2.Plug` reads that
  config to pick which HTTP adapter `Assent` uses for the whole OAuth2
  callback flow (token exchange + userinfo fetch).

  Instead of any shared/global stub state (which would be unsafe under
  `async: true`), the fake Google account's e-mail travels round-trip
  inside the authorization `code` a test sends to the callback endpoint
  and, from there, inside the fake access token — see `code_for/1`.
  """

  @behaviour Assent.HTTPAdapter

  alias Assent.HTTPAdapter.HTTPResponse

  @code_prefix "stub-google-code:"
  @token_prefix "stub-google-token:"

  @doc """
  Builds the fake authorization `code` a test should pass as the `code`
  query param on a `GET /auth/user/google/callback` request, so the stub
  can hand back userinfo for the given `email` (and a stable `sub`
  derived from it) without any shared process state.
  """
  @spec code_for(String.t()) :: String.t()
  def code_for(email), do: @code_prefix <> email

  @impl true
  def request(:post, url, body, _headers, _opts) do
    if url =~ "/oauth2/v4/token" do
      email =
        body
        |> URI.decode_query()
        |> Map.fetch!("code")
        |> String.trim_leading(@code_prefix)

      json_response(%{
        "access_token" => @token_prefix <> email,
        "token_type" => "Bearer",
        "expires_in" => 3600
      })
    else
      {:error, "GoogleOAuthStub: unexpected POST #{url}"}
    end
  end

  def request(:get, url, _body, headers, _opts) do
    if url =~ "/oauth2/v3/userinfo" do
      {_, "Bearer " <> token} = List.keyfind(headers, "authorization", 0)
      email = String.trim_leading(token, @token_prefix)

      json_response(%{
        "sub" => "google-" <> Base.url_encode64(email, padding: false),
        "email" => email,
        "email_verified" => true,
        "name" => "Stub Google User"
      })
    else
      {:error, "GoogleOAuthStub: unexpected GET #{url}"}
    end
  end

  defp json_response(map) do
    {:ok,
     %HTTPResponse{
       status: 200,
       headers: [{"content-type", "application/json"}],
       body: Jason.encode!(map)
     }}
  end
end
