defmodule Ponteio.Chords do
  @moduledoc """
  Domain for the curated chord shape catalog used to render diagrams and to
  suggest chords for a tablature (per SDD §1, §2.3). Empty of business logic
  for now beyond the `ChordShape` read-only catalog resource — the matching
  algorithm described in SDD §3 lands in a future issue.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Chords.ChordShape do
      define :list_chord_shapes, action: :read
    end
  end
end
