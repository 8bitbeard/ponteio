defmodule Ponteio.Tablatures do
  @moduledoc """
  Domain for tablatures and their internal structure — measures, notes, and
  chord suggestion results (per SDD §1, §2.2).

  Intentionally empty in this foundational issue — the `Tab`, `Measure`,
  `Note`, `ChordSegment`, and `ChordSuggestion` resources are added in
  future issues, once the corresponding user stories are scoped.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
  end
end
