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
  and `ChordSuggestion` were added by issue #20 ("Disparo assíncrono da
  análise de acordes com status visível") as the persisted output of
  `Tab`'s `:run_chord_analysis` action — see that action's own description
  and `Ponteio.Tablatures.Changes.RunChordAnalysis`.

  Neither `Measure`/`Note` nor `ChordSegment`/`ChordSuggestion` has a code
  interface entry — no LiveView calls their actions directly.
  `TabLive.Editor`'s note-entry grid (issues #11-#13) keeps edits as local
  assigns, and `upsert_measure_notes` (issue #14) is what persists that
  tree in bulk on save, via `Ponteio.Tablatures.Changes.UpsertMeasureNotes`
  calling `Ash.create!`/`Ash.destroy!` on `Measure`/`Note` directly.
  Likewise, `RunChordAnalysis` (issue #20) is the sole, internal-only
  caller of `ChordSegment`/`ChordSuggestion`'s actions — none of the four
  resources warrants a code interface entry for a caller that only ever
  exists once, inside this same domain.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Tablatures.Tab do
      define :create_tab, action: :create
      define :list_tabs_for_user, action: :read
      define :update_tab, action: :update
      define :delete_tab, action: :destroy
      define :upsert_measure_notes, action: :upsert_measure_notes, args: [:measures]
    end

    resource Ponteio.Tablatures.Measure
    resource Ponteio.Tablatures.Note
    resource Ponteio.Tablatures.ChordSegment
    resource Ponteio.Tablatures.ChordSuggestion
  end
end
