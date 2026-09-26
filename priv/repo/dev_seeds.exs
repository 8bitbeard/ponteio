# Dev-only demo data. NOT part of `mix setup`/`ecto.setup` (those only run
# `priv/repo/seeds.exs`, the production-safe `ChordShape` catalog) — this
# script creates a fake user-owned `Tab`, so it must be run manually:
#
#     mix run priv/repo/dev_seeds.exs
#
# Requires at least one confirmed `Ponteio.Accounts.User` to already exist
# (created via the app's own sign-up flow) — this script attaches the demo
# tablature to the oldest one it finds rather than registering a new
# account itself (`:register_with_password` requires e-mail confirmation,
# which is out of scope for a seed script).
#
# Ensures the `ChordShape` catalog (`priv/repo/seeds.exs`) is present first
# — the chord-analysis engine has nothing to match against otherwise — then
# creates a tablature with four measures exercising every segmentation
# shape `Ponteio.Chords.segment_measure/2` can produce against the real
# seeded catalog (verified against it, not hand-derived — see each
# measure's own comment below for how):
#
#   1. Mi Maior — a whole compasso, one unambiguous chord.
#   2. Lá Menor — same, a second unambiguous chord.
#   3. Two chords in one compasso — the bottom half (strings D A E) of an
#      open E shape, ambiguous between Maior/Menor (neither differs on
#      those three strings alone — a real "N de 2 sugestões" case), then
#      the top half (strings e B G) of an open Lá Menor.
#   4. Chord → isolated note → chord — the top half of Ré Maior, then a
#      lone note (string 1, fret 10) that matches nothing in the catalog
#      at any base_fret (so it can never merge into a neighboring window
#      either — `Ponteio.Chords.candidates_for_window/2`'s subset match
#      requires *every* note in a window to match), then the top half of
#      Lá Maior.
#
# `Tab.run_chord_analysis` resolves each into exactly the segments listed
# above. Idempotent: reruns destroy the previous demo tab (by title +
# owner) before recreating it.

require Ash.Query

Code.require_file("seeds.exs", __DIR__)

alias Ponteio.Accounts.User
alias Ponteio.Tablatures
alias Ponteio.Tablatures.Tab

owner =
  User
  |> Ash.Query.sort(id: :asc)
  |> Ash.Query.limit(1)
  |> Ash.read_one!(authorize?: false)

unless owner do
  raise """
  No user found — sign up through the app first (a demo tab needs an
  owner), then rerun `mix run priv/repo/dev_seeds.exs`.
  """
end

tab_title = "Progressão Seed (Mi - Lá m - Mi/m+Lá m - Ré+Lá)"

Tab
|> Ash.Query.filter(title == ^tab_title and user_id == ^owner.id)
|> Ash.read!(authorize?: false)
|> Enum.each(&Ash.destroy!(&1, authorize?: false))

tab =
  Tab
  |> Ash.Changeset.for_create(:create, %{title: tab_title, artist: "Ponteio Seeds"}, actor: owner)
  |> Ash.create!()

# Each measure's notes are, string for string, real open-position shapes
# from `priv/repo/seeds.exs` — string 1 = high e .. string 6 = low E, per
# `Note.string_number`'s convention.
measures_params = [
  # Mi Maior (open-e-major: 0 0 1 2 2 0)
  %{
    position: 1,
    notes: [
      %{string_number: 1, fret_number: 0, position: 0},
      %{string_number: 2, fret_number: 0, position: 1},
      %{string_number: 3, fret_number: 1, position: 2},
      %{string_number: 4, fret_number: 2, position: 3},
      %{string_number: 5, fret_number: 2, position: 4},
      %{string_number: 6, fret_number: 0, position: 5}
    ]
  },
  # Lá menor (open-a-minor: 0 1 2 2 0 x — string 6 muted, no note)
  %{
    position: 2,
    notes: [
      %{string_number: 1, fret_number: 0, position: 0},
      %{string_number: 2, fret_number: 1, position: 1},
      %{string_number: 3, fret_number: 2, position: 2},
      %{string_number: 4, fret_number: 2, position: 3},
      %{string_number: 5, fret_number: 0, position: 4}
    ]
  },
  # Two chords: strings D/A/E (2 2 0) of open-e-major/menor (ambiguous —
  # both shapes agree on these three strings), then strings e/B/G (0 1 2)
  # of open-a-minor.
  %{
    position: 3,
    notes: [
      %{string_number: 4, fret_number: 2, position: 0},
      %{string_number: 5, fret_number: 2, position: 1},
      %{string_number: 6, fret_number: 0, position: 2},
      %{string_number: 1, fret_number: 0, position: 3},
      %{string_number: 2, fret_number: 1, position: 4},
      %{string_number: 3, fret_number: 2, position: 5}
    ]
  },
  # Chord (strings e/B/G of open-d-major: 2 3 2) → isolated note (string 1,
  # fret 10 — matches nothing in the catalog at any base_fret, verified) →
  # chord (strings e/B/G of open-a-major: 0 2 2).
  %{
    position: 4,
    notes: [
      %{string_number: 1, fret_number: 2, position: 0},
      %{string_number: 2, fret_number: 3, position: 1},
      %{string_number: 3, fret_number: 2, position: 2},
      %{string_number: 1, fret_number: 10, position: 3},
      %{string_number: 1, fret_number: 0, position: 4},
      %{string_number: 2, fret_number: 2, position: 5},
      %{string_number: 3, fret_number: 2, position: 6}
    ]
  }
]

{:ok, tab} = Tablatures.upsert_measure_notes(tab, measures_params, actor: owner)

# `:run_chord_analysis` normally only runs via the `:analyze_chords`
# AshOban trigger (issue #20) once this script's own `mix run` process has
# already exited — called directly here (a plain Ash action, `actor: owner`
# satisfies the same `user_id == actor(:id)` policy any other update does)
# so the `ChordSegment`/`ChordSuggestion` rows exist immediately.
tab =
  tab
  |> Ash.Changeset.for_update(:run_chord_analysis, %{}, actor: owner)
  |> Ash.update!()

segments =
  Ponteio.Tablatures.Measure
  |> Ash.Query.filter(tab_id == ^tab.id)
  |> Ash.Query.sort(position: :asc)
  |> Ash.Query.load(chord_segments: [:selected_suggestion, chord_suggestions: [:chord_shape]])
  |> Ash.read!(authorize?: false)

IO.puts("Seeded tab #{inspect(tab.title)} (#{tab.id}), status: #{tab.status}")

Enum.each(segments, fn measure ->
  Enum.each(measure.chord_segments, fn segment ->
    label =
      case segment.status do
        :no_match ->
          "sem sugestão"

        :suggested ->
          segment.chord_suggestions
          |> Enum.sort_by(& &1.rank)
          |> Enum.map(fn suggestion ->
            root =
              Ponteio.Chords.root_note_name(
                suggestion.chord_shape,
                suggestion.base_fret,
                tab.capo_fret
              )

            "#{root} #{suggestion.chord_shape.name}"
          end)
          |> Enum.join(" ou ")
      end

    IO.puts(
      "  compasso #{measure.position} [#{segment.start_position}-#{segment.end_position}]: #{label}"
    )
  end)
end)
