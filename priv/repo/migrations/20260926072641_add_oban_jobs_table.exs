defmodule Ponteio.Repo.Migrations.AddObanJobsTable do
  @moduledoc """
  Creates the tables Oban needs (`oban_jobs`, `oban_peers`, etc.) to back
  the AshOban trigger on `Ponteio.Tablatures.Tab` (issue #20, "Disparo
  assíncrono da análise de acordes com status visível"; SDD §3.4) — see
  `Oban.Migration`'s own moduledoc for what this wraps.
  """

  use Ecto.Migration

  def up, do: Oban.Migrations.up()

  # Oban's own down migration only reaches back to its first version, per
  # `Oban.Migration`'s documented usage (rolling all the way back is rarely
  # what's wanted for a versioned migration set like this one).
  def down, do: Oban.Migrations.down(version: 1)
end
