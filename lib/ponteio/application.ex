defmodule Ponteio.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PonteioWeb.Telemetry,
      Ponteio.Repo,
      {DNSCluster, query: Application.get_env(:ponteio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ponteio.PubSub},
      # AshOban's `:analyze_chords` trigger on `Ponteio.Tablatures.Tab`
      # (issue #20, SDD §3.4) needs Oban itself supervised — `AshOban.config/2`
      # takes our base `:ponteio, Oban` config (config/config.exs) and layers
      # in whatever queues/cron entries every domain's resources declare.
      {Oban, AshOban.config(Application.fetch_env!(:ponteio, :ash_domains), oban_config())},
      # Start to serve requests, typically the last entry
      PonteioWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :ponteio]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ponteio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PonteioWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config, do: Application.fetch_env!(:ponteio, Oban)
end
