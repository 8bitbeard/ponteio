defmodule Ponteio.Chords do
  @moduledoc """
  Domain for the curated chord shape catalog used to render diagrams and to
  suggest chords for a tablature (per SDD §1, §2.3). Besides the
  `ChordShape` read-only catalog resource, this module also hosts
  `candidates_for_window/2` (issue #15, "Calcular candidatos de acorde
  para uma janela de notas"; PRD §6.4 regra 1; SDD §3.1) — the atomic
  matching operation the whole suggestion engine (segmentation, ranking,
  the `:run_chord_analysis` action) is built on top of. It is a plain
  Elixir function, not an Ash action: it takes/returns plain data and has
  no policies, so it can be unit-tested without a database, Ash, or
  LiveView.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Chords.ChordShape do
      define :list_chord_shapes, action: :read
    end
  end

  @typedoc """
  A note within the window being analyzed: which string (1 = high E ..
  6 = low E, same convention as `ChordShape.root_string`/`Note.string_number`)
  and which fret it is played at. The fret is already relative to whatever
  capo is in effect — callers of this function are responsible for that
  translation (SDD §3.1's window is a plain `{corda, casa}` pair, not a
  `Note` struct), this function does no capo arithmetic itself.
  """
  @type window_note :: {string_number :: 1..6, fret_number :: non_neg_integer()}

  @typedoc "A `{chord_shape, base_fret}` pair matched against a window."
  @type candidate :: %{chord_shape: Ponteio.Chords.ChordShape.t(), base_fret: integer()}

  @doc """
  Returns every `%{chord_shape:, base_fret:}` candidate from `chord_shapes`
  that can produce every note in `window` at some `base_fret` between the
  shape's `min_base_fret` and `max_base_fret` (SDD §3.1):

      para cada chord_shape no catálogo:
        para cada base_fret entre min_base_fret e max_base_fret:
          instancia o shape: expected_fret[corda] = relative_frets[corda] + base_fret
          se TODA nota da janela satisfaz nota.casa == expected_fret[nota.corda]:
            adiciona {chord_shape, base_fret} aos candidatos

  Matching is **by subset**, not exact-set equality (PRD §6.4 regra 1,
  SDD §3.1): a shape's strings that don't appear in `window` (not played
  in that stretch) never block a match, and a muted string (`nil` in
  `relative_frets`) can never satisfy a note — a window note on a muted
  string always rules that `{shape, base_fret}` pair out.

  An empty `window` matches every `{shape, base_fret}` combination
  (vacuously true) — callers are expected to only call this with a
  non-empty window; `segment_measure/1` (a later issue) is what decides
  how notes are grouped into windows in the first place.
  """
  @spec candidates_for_window([window_note()], [Ponteio.Chords.ChordShape.t()]) :: [candidate()]
  def candidates_for_window(window, chord_shapes) do
    for chord_shape <- chord_shapes,
        base_fret <- chord_shape.min_base_fret..chord_shape.max_base_fret,
        matches_window?(window, chord_shape, base_fret) do
      %{chord_shape: chord_shape, base_fret: base_fret}
    end
  end

  defp matches_window?(window, chord_shape, base_fret) do
    Enum.all?(window, fn {string_number, fret_number} ->
      case expected_fret(chord_shape, string_number, base_fret) do
        nil -> false
        expected_fret -> fret_number == expected_fret
      end
    end)
  end

  defp expected_fret(chord_shape, string_number, base_fret) do
    case Enum.at(chord_shape.relative_frets, string_number - 1) do
      nil -> nil
      relative_fret -> relative_fret + base_fret
    end
  end
end
