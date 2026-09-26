defmodule PonteioWeb.TabLive.StudyMeasureComponentTest do
  @moduledoc """
  Covers `StudyMeasureComponent.study_row/1` directly: the continuous,
  several-compassos-per-row braço (one shared grid, bar-lines instead of
  separate cards), every `:suggested` segment's chip always showing its
  diagram regardless of how narrow its own span is or whether the same
  chord already appeared earlier in the tab, and the alternating "hand
  position" background tint — all added in response to user feedback on
  the initial four-per-row layout (chord chip overlapping the "e" string
  row; multi-chord/isolated-note compassos not exercised by the seed; no
  visual cue for which notes share a hand position; a narrow segment's
  diagram silently dropped in favor of a name-only fallback).

  Plain `ExUnit.Case` + `Phoenix.LiveViewTest.render_component/2`, no
  `Ponteio.DataCase`/`ConnCase` — same rationale as
  `ChordDiagramComponentTest`: `study_row/1` is a stateless function
  component, its fixtures plain in-memory structs (real `ChordSegment`/
  `ChordSuggestion`/`Measure`/`Note` structs, never persisted — the
  component only ever reads their fields, `displayed_suggestion/1`'s own
  struct-type match on `ChordSuggestion` aside).
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Ponteio.Chords.ChordShape
  alias Ponteio.Tablatures.ChordSegment
  alias Ponteio.Tablatures.ChordSuggestion
  alias Ponteio.Tablatures.Measure
  alias Ponteio.Tablatures.Note

  alias PonteioWeb.TabLive.StudyMeasureComponent

  @endpoint PonteioWeb.Endpoint

  defp e_major_open, do: chord_shape("e-major-open", "Maior", 6, [0, 0, 1, 2, 2, 0])
  defp a_minor_open, do: chord_shape("a-minor-open", "Menor", 5, [0, 1, 2, 2, 0, nil])

  defp chord_shape(slug, name, root_string, relative_frets) do
    %ChordShape{
      slug: slug,
      name: name,
      quality: :major,
      root_string: root_string,
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0,
      relative_frets: relative_frets
    }
  end

  defp note(string_number, fret_number, position),
    do: %Note{string_number: string_number, fret_number: fret_number, position: position}

  defp suggestion(chord_shape, base_fret, rank),
    do: %ChordSuggestion{chord_shape: chord_shape, base_fret: base_fret, rank: rank}

  defp suggested_segment(id, start_position, end_position, suggestions) do
    %ChordSegment{
      id: id,
      start_position: start_position,
      end_position: end_position,
      status: :suggested,
      chord_suggestions: suggestions,
      selected_suggestion: nil
    }
  end

  defp no_match_segment(id, position) do
    %ChordSegment{
      id: id,
      start_position: position,
      end_position: position,
      status: :no_match,
      chord_suggestions: [],
      selected_suggestion: nil
    }
  end

  defp measure(position, notes, chord_segments) do
    %Measure{
      id: Ecto.UUID.generate(),
      position: position,
      notes: notes,
      chord_segments: chord_segments
    }
  end

  describe "one continuous braço per row" do
    test "renders every compasso of the row, divided by a bar-line, not separate cards" do
      measure_1 =
        measure(1, [note(1, 0, 0)], [
          suggested_segment("seg-1", 0, 0, [suggestion(e_major_open(), 0, 1)])
        ])

      measure_2 =
        measure(2, [note(1, 0, 0)], [
          suggested_segment("seg-2", 0, 0, [suggestion(a_minor_open(), 0, 1)])
        ])

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [measure_1, measure_2],
          capo_fret: 0
        )

      assert html =~ "study-measure-#{measure_1.id}"
      assert html =~ "study-measure-#{measure_2.id}"
      assert html =~ "Compasso 1"
      assert html =~ "Compasso 2"
      # The bar-line convention (`docs/mockup-telas.html`'s `.tab-cell.bar-line`):
      # a border-right on the last column of every compasso, including a
      # padded one — never a second, independent card/border per compasso.
      assert html =~ "border-r-2"
      refute html =~ "Compasso sem notas"
    end
  end

  describe "every suggested segment always shows its diagram" do
    test "a chord that fills a whole (padded) measure shows its diagram, name and rank line" do
      segment = suggested_segment("seg-full", 0, 0, [suggestion(e_major_open(), 0, 1)])

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [measure(1, [note(1, 0, 0)], [segment])],
          capo_fret: 0
        )

      assert html =~ "Mi Maior"
      assert html =~ "1 de 1 sugestões"
      assert html =~ "chord-diagram-seg-full"
    end

    test "a chord too narrow to comfortably fit still shows its diagram, not a name-only fallback" do
      # Two real notes only: a 1-note chorded segment that does NOT reach
      # the measure's last note (the no_match note after it does) — stays
      # at its literal (narrow) span instead of being padded. Explicit
      # product requirement: the diagram always renders regardless.
      chorded = suggested_segment("seg-narrow", 0, 0, [suggestion(e_major_open(), 0, 1)])
      no_match = no_match_segment("seg-nm", 1)

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [measure(1, [note(1, 0, 0), note(2, 5, 1)], [chorded, no_match])],
          capo_fret: 0
        )

      assert html =~ "Mi Maior"
      assert html =~ "chord-diagram-seg-narrow"
    end

    test "the same chord repeated across compassos shows its diagram every time" do
      seg_1 = suggested_segment("seg-rep-1", 0, 0, [suggestion(e_major_open(), 0, 1)])
      seg_2 = suggested_segment("seg-rep-2", 0, 0, [suggestion(e_major_open(), 0, 1)])

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [
            measure(1, [note(1, 0, 0)], [seg_1]),
            measure(2, [note(1, 0, 0)], [seg_2])
          ],
          capo_fret: 0
        )

      assert html =~ "chord-diagram-seg-rep-1"
      assert html =~ "chord-diagram-seg-rep-2"
    end

    test "a no_match segment always shows its label, even a narrow one — issue #22's own acceptance criterion" do
      chorded = suggested_segment("seg-a", 0, 0, [suggestion(e_major_open(), 0, 1)])
      no_match = no_match_segment("seg-nm", 1)

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [measure(1, [note(1, 0, 0), note(2, 5, 1)], [chorded, no_match])],
          capo_fret: 0
        )

      assert html =~ "sem sugestão"
      assert html =~ "border-dashed"
    end
  end

  describe "which notes share a hand position" do
    test "two chords in one compasso get different, alternating background tints" do
      chord_a = suggested_segment("seg-a", 0, 2, [suggestion(e_major_open(), 0, 1)])
      chord_b = suggested_segment("seg-b", 3, 5, [suggestion(a_minor_open(), 0, 1)])

      notes = [
        note(4, 2, 0),
        note(5, 2, 1),
        note(6, 0, 2),
        note(1, 0, 3),
        note(2, 1, 4),
        note(3, 2, 5)
      ]

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [measure(1, notes, [chord_a, chord_b])],
          capo_fret: 0
        )

      assert html =~ "bg-primary/10"
      assert html =~ "bg-base-content/5"
    end

    test "an isolated no_match note between two chords renders as its own untinted, dashed segment" do
      chord_a = suggested_segment("seg-a", 0, 0, [suggestion(e_major_open(), 0, 1)])
      isolated = no_match_segment("seg-nm", 1)
      chord_b = suggested_segment("seg-b", 2, 2, [suggestion(a_minor_open(), 0, 1)])

      notes = [note(1, 0, 0), note(1, 10, 1), note(1, 0, 2)]

      html =
        render_component(&StudyMeasureComponent.study_row/1,
          measures: [measure(1, notes, [chord_a, isolated, chord_b])],
          capo_fret: 0
        )

      # The isolated note (fret 10) is a genuine third segment (not merged
      # into either neighboring chord — `chorded_spans/1` only ever tints
      # `:suggested` segments, so this one contributes neither tint class
      # itself), rendered with the dashed no-suggestion bracket alongside
      # both chords' own tints.
      assert html =~ "10"
      assert html =~ "border-dashed"
      assert html =~ "bg-primary/10"
      assert html =~ "bg-base-content/5"
    end
  end
end
