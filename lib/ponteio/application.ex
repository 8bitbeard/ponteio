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
      # Start a worker by calling: Ponteio.Worker.start_link(arg)
      # {Ponteio.Worker, arg},
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
end
