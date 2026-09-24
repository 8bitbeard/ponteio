defmodule Ponteio.Tablatures do
  @moduledoc """
  Domain for tablatures and their internal structure — measures, notes, and
  chord suggestion results (per SDD §1, §2.2).

  Holds the `Tab` resource, created by issue #6 and extended with listing
  (issue #7). `Measure`, `Note`, `ChordSegment`, and `ChordSuggestion` are
  added in future issues, once the corresponding user stories are scoped.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Tablatures.Tab do
      define :create_tab, action: :create
      define :list_tabs_for_user, action: :read
    end
  end
end
