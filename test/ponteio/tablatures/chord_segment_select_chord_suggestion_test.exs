defmodule Ponteio.Tablatures.ChordSegmentSelectChordSuggestionTest do
  @moduledoc """
  Covers `ChordSegment`'s `:select_chord_suggestion` action and its
  `Ponteio.Tablatures.select_chord_suggestion/3` code interface (issue
  #21, "Usuário escolhe entre sugestões de acorde ambíguas"; PRD §6.4
  regra 3; SDD §5) — persisting the user's pick among a segment's ranked
  candidates, independent of the reanalysis-preservation logic covered in
  `TabRunChordAnalysisTest` (this issue's other "Testes esperados" item).
  """

  use Ponteio.DataCase, async: true

  alias Ponteio.Accounts.User
  alias Ponteio.Chords.ChordShape
  alias Ponteio.Tablatures
  alias Ponteio.Tablatures.ChordSegment
  alias Ponteio.Tablatures.ChordSuggestion
  alias Ponteio.Tablatures.Measure
  alias Ponteio.Tablatures.Tab

  defp seed_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")
    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end

  defp seed_chord_shape!(slug) do
    Ash.Seed.seed!(ChordShape, %{
      slug: slug,
      name: "Maior",
      quality: :major,
      root_string: 1,
      relative_frets: List.duplicate(nil, 6) |> List.replace_at(0, 0),
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0
    })
  end

  defp seed_tab!(owner) do
    Ash.Seed.seed!(Tab, %{title: "Wave", artist: "Tom Jobim", user_id: owner.id})
  end

  defp seed_measure!(tab) do
    Ash.Seed.seed!(Measure, %{tab_id: tab.id, position: 1})
  end

  defp seed_chord_segment!(measure, attrs \\ %{}) do
    Ash.Seed.seed!(
      ChordSegment,
      Map.merge(
        %{measure_id: measure.id, start_position: 0, end_position: 0, status: :suggested},
        attrs
      )
    )
  end

  defp seed_chord_suggestion!(chord_segment, chord_shape, attrs \\ %{}) do
    Ash.Seed.seed!(
      ChordSuggestion,
      Map.merge(
        %{
          chord_segment_id: chord_segment.id,
          chord_shape_id: chord_shape.id,
          base_fret: 0,
          rank: 1
        },
        attrs
      )
    )
  end

  describe "select_chord_suggestion/3" do
    test "persists the actor's chosen candidate on selected_suggestion_id" do
      owner = seed_user("dono@ponteio.app")
      chord_shape = seed_chord_shape!("shape-select-ok")
      tab = seed_tab!(owner)
      measure = seed_measure!(tab)
      chord_segment = seed_chord_segment!(measure)

      rank_1 = seed_chord_suggestion!(chord_segment, chord_shape, %{rank: 1, base_fret: 0})
      rank_2 = seed_chord_suggestion!(chord_segment, chord_shape, %{rank: 2, base_fret: 3})

      assert {:ok, updated} =
               Tablatures.select_chord_suggestion(chord_segment, rank_2, actor: owner)

      assert updated.selected_suggestion_id == rank_2.id
      assert updated.selected_suggestion_id != rank_1.id

      persisted = Ash.get!(ChordSegment, chord_segment.id, actor: owner)
      assert persisted.selected_suggestion_id == rank_2.id
    end

    test "fails when the chord_suggestion belongs to a different chord_segment" do
      owner = seed_user("outro-segmento@ponteio.app")
      chord_shape = seed_chord_shape!("shape-select-mismatch")
      tab = seed_tab!(owner)
      measure = seed_measure!(tab)

      chord_segment_a = seed_chord_segment!(measure, %{start_position: 0, end_position: 0})
      chord_segment_b = seed_chord_segment!(measure, %{start_position: 1, end_position: 1})

      foreign_suggestion = seed_chord_suggestion!(chord_segment_b, chord_shape)

      assert {:error, _error} =
               Tablatures.select_chord_suggestion(chord_segment_a, foreign_suggestion,
                 actor: owner
               )

      persisted = Ash.get!(ChordSegment, chord_segment_a.id, actor: owner)
      assert persisted.selected_suggestion_id == nil
    end

    test "rejects a non-owner actor" do
      owner = seed_user("dono-policy@ponteio.app")
      intruder = seed_user("intruso-policy@ponteio.app")
      chord_shape = seed_chord_shape!("shape-select-policy")
      tab = seed_tab!(owner)
      measure = seed_measure!(tab)
      chord_segment = seed_chord_segment!(measure)
      suggestion = seed_chord_suggestion!(chord_segment, chord_shape)

      assert {:error, _error} =
               Tablatures.select_chord_suggestion(chord_segment, suggestion, actor: intruder)

      persisted = Ash.get!(ChordSegment, chord_segment.id, actor: owner)
      assert persisted.selected_suggestion_id == nil
    end
  end
end
