defmodule Ponteio.Tablatures do
  @moduledoc """
  Domain for tablatures and their internal structure — measures, notes, and
  chord suggestion results (per SDD §1, §2.2).

  Holds the `Tab` resource, created by issue #6 and extended with listing
  (issue #7), metadata editing (issue #8), and deletion (issue #9).
  `Measure` and `Note` were added by issue #11 ("Inserir notas no editor de
  tablatura") — `Measure` as the technical prerequisite `Note` needs to
  exist (its full "+Adicionar compasso"/"quebrar compasso" UI is issue
  #12's scope), `Note` as that issue's actual new resource. `ChordSegment`
  and `ChordSuggestion` are added in future issues, once the corresponding
  user stories are scoped.

  Neither `Measure` nor `Note` has a code interface entry yet — no caller
  invokes their actions directly; `TabLive.Editor`'s note-entry grid (issue
  #11) keeps edits as local assigns, and `upsert_measure_notes` (issue
  #14) is what will eventually call into them in bulk and warrant one.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Tablatures.Tab do
      define :create_tab, action: :create
      define :list_tabs_for_user, action: :read
      define :update_tab, action: :update
      define :delete_tab, action: :destroy
    end

    resource Ponteio.Tablatures.Measure
    resource Ponteio.Tablatures.Note
  end
end
