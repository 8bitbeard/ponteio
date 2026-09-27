defmodule Ponteio.Repo do
  use Ecto.Repo,
    otp_app: :ponteio,
    adapter: Ecto.Adapters.Postgres
end
