defmodule Ponteio.Chords do
  @moduledoc """
  Domain for the curated chord shape catalog used to render diagrams and to
  suggest chords for a tablature (per SDD §1, §2.3). Besides the
  `ChordShape` read-only catalog resource, this module also hosts
  `candidates_for_window/2` (issue #15, "Calcular candidatos de acorde
  para uma janela de notas"; PRD §6.4 regra 1; SDD §3.1),
  `segment_measure/2` (issue #16, "Segmentar compasso automaticamente
  quando notas não cabem em um único acorde"; PRD §6.4 regra 2; SDD §3.2)
  and `rank_candidates/2` (issue #17, "Ranquear candidatos por menor
  deslocamento de mão"; PRD §6.4 regra 3; SDD §3.3) — the atomic matching
  operation, the segmentation built on top of it, and the ranking of a
  segment's candidates by hand-movement cost, respectively, all of which
  the whole suggestion engine (the `:run_chord_analysis` action, issue
  #20) relies on — plus `root_note_name/3` (issue #19, "Considerar
  capotraste na análise de acordes"; PRD §6.4 regra 5; SDD §2.3), the only
  place in the whole engine that does capo arithmetic (see that
  function's own doc for why the rest of the pipeline doesn't need to).
  These are plain Elixir functions, not Ash actions: they take/return
  plain data and have no policies, so they can be unit-tested without a
  database, Ash, or LiveView.
  """

  use Ash.Domain,
    otp_app: :ponteio

  resources do
    resource Ponteio.Chords.ChordShape do
      define :list_chord_shapes, action: :read
    end
  end

  # Standard tuning (E A D G B E, SDD §2.3 — a compile-time constant, not a
  # resource), as each open string's chromatic index (Dó = 0 .. Si = 11),
  # keyed by `Ponteio.Chords.ChordShape.root_string`'s 1 (high E) .. 6 (low
  # E) convention.
  @standard_tuning %{1 => 4, 2 => 11, 3 => 7, 4 => 2, 5 => 9, 6 => 4}

  # The twelve Portuguese chromatic note names, sharps only, index 0 (Dó)
  # through 11 (Si) — matches `@standard_tuning`'s indices.
  @note_names ~w(Dó Dó# Ré Ré# Mi Fá Fá# Sol Sol# Lá Lá# Si)

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

  @typedoc "A `candidate/0` ranked against the previous segment's position, per `rank_candidates/2`."
  @type ranked_candidate :: %{
          chord_shape: Ponteio.Chords.ChordShape.t(),
          base_fret: integer(),
          rank: 1..3
        }

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
  non-empty window; `segment_measure/2` is what decides how notes are
  grouped into windows in the first place.
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

  @typedoc """
  A note within the measure being segmented: same `string_number`/
  `fret_number` pair as `window_note`, plus `position` — its order of
  insertion within the measure (`Ponteio.Tablatures.Note.position`'s own
  convention), used to label the resulting segments' `start_position`/
  `end_position`. Works with `Ponteio.Tablatures.Note` structs directly
  (this module's tests build them in-memory, no DB involved) or any
  struct/map exposing these three keys.
  """
  @type measure_note :: %{
          position: non_neg_integer(),
          string_number: 1..6,
          fret_number: non_neg_integer()
        }

  @typedoc """
  One contiguous stretch of a measure's notes resolved by `segment_measure/2`:
  `start_position`/`end_position` are the covered notes' own `position`
  values (inclusive on both ends), `status` is `:chorded` when at least one
  chord candidate matched the segment's window and `:no_match` for the
  size-1 fallback when none did, and `candidates` carries whatever
  `candidates_for_window/2` returned for that window (always `[]` for a
  `:no_match` segment).
  """
  @type segment :: %{
          start_position: non_neg_integer(),
          end_position: non_neg_integer(),
          status: :chorded | :no_match,
          candidates: [candidate()]
        }

  @doc """
  Splits `notes` (a single measure's notes, in any order — sorted here by
  `position` before anything else) into the **fewest possible** contiguous
  `segment/0`s, each either "chorded" (some candidate in `chord_shapes`
  matches every note in the segment's window, per `candidates_for_window/2`)
  or, as a last-resort fallback restricted to a lone, otherwise-unmatched
  note, `:no_match` (PRD §6.4 regra 2; SDD §3.2).

  Solved with the dynamic-programming recurrence SDD §3.2 spells out —
  `dp[i]` = fewest segments covering the first `i` notes (in `position`
  order):

      dp[0] = 0
      para i de 1 até N:
        dp[i] = infinito
        para j de 0 até i-1:
          janela = notes[j..i)
          se candidates_for_window(janela, chord_shapes) não vazio, ou (i - j == 1):
            custo = dp[j] + 1
            se custo < dp[i]: dp[i] = custo; backtrack[i] = j
      reconstrói os segmentos a partir de backtrack[N]

  `O(N²)` windows are tried (each itself costing a `candidates_for_window/2`
  call), which SDD §8 calls out as acceptable for the expected size of a
  manually-edited measure. Ties (two `j`s reaching the same minimal `dp[i]`)
  keep the **first** one found — i.e. the widest matching window, since `j`
  is tried from `0` upward — mirroring the pseudocode's strict `<` update.

  Takes `chord_shapes` explicitly, same as `candidates_for_window/2`, so it
  stays a pure, DB-free function callable from plain ExUnit tests with
  in-memory `ChordShape` fixtures (SDD §6) — the `segment_measure(notes)`
  call shown in this issue's (#16) own write-up and in SDD §3.4's analysis
  flow elides this second argument for brevity, the same way SDD §3.4 also
  elides it from `candidates_for_window(segmento.notas)` despite that
  function's real, already-implemented arity being 2.

  An empty `notes` list returns `[]` — there is nothing to segment.
  """
  @spec segment_measure([measure_note()], [Ponteio.Chords.ChordShape.t()]) :: [segment()]
  def segment_measure(notes, chord_shapes)

  def segment_measure([], _chord_shapes), do: []

  def segment_measure(notes, chord_shapes) do
    sorted_notes = Enum.sort_by(notes, & &1.position)
    count = length(sorted_notes)

    segments_by_end = build_segments_by_end(sorted_notes, count, chord_shapes)

    count
    |> collect_segment_bounds(segments_by_end, [])
    |> Enum.map(&to_segment(&1, sorted_notes))
  end

  # Fills `dp`/`segments_by_end` for every prefix length `1..count`, per
  # the recurrence in `segment_measure/2`'s doc. Returns only the
  # `segments_by_end` map (`i => %{start:, status:, candidates:}` for the
  # best segment ending at `i`) — `dp` itself is just `Map.get(dp, j, 0)`
  # threaded through the reduce, not needed again once every `i` is filled.
  defp build_segments_by_end(sorted_notes, count, chord_shapes) do
    {_dp, segments_by_end} =
      Enum.reduce(1..count, {%{0 => 0}, %{}}, fn i, {dp, segments_by_end} ->
        best = best_segment_ending_at(sorted_notes, dp, i, chord_shapes)
        {Map.put(dp, i, best.cost), Map.put(segments_by_end, i, best)}
      end)

    segments_by_end
  end

  defp best_segment_ending_at(sorted_notes, dp, i, chord_shapes) do
    Enum.reduce(0..(i - 1), %{cost: :infinity, start: nil, status: nil, candidates: nil}, fn j,
                                                                                             best ->
      window_notes = Enum.slice(sorted_notes, j, i - j)
      candidates = candidates_for_window(to_window(window_notes), chord_shapes)

      cond do
        candidates != [] -> maybe_better(best, dp, j, :chorded, candidates)
        i - j == 1 -> maybe_better(best, dp, j, :no_match, [])
        true -> best
      end
    end)
  end

  defp maybe_better(current_best, dp, j, status, candidates) do
    cost = Map.fetch!(dp, j) + 1

    if cost < current_best.cost do
      %{cost: cost, start: j, status: status, candidates: candidates}
    else
      current_best
    end
  end

  defp to_window(notes), do: Enum.map(notes, &{&1.string_number, &1.fret_number})

  # Walks `backtrack` (here, `segments_by_end`'s `:start`) from `N` back to
  # `0`, collecting each segment's `{start_index, end_index}` bounds
  # (`end_index` exclusive) in playing order.
  defp collect_segment_bounds(0, _segments_by_end, acc), do: acc

  defp collect_segment_bounds(i, segments_by_end, acc) do
    %{start: j} = segment = Map.fetch!(segments_by_end, i)
    collect_segment_bounds(j, segments_by_end, [{j, i, segment} | acc])
  end

  defp to_segment(
         {start_index, end_index, %{status: status, candidates: candidates}},
         sorted_notes
       ) do
    %{
      start_position: Enum.at(sorted_notes, start_index).position,
      end_position: Enum.at(sorted_notes, end_index - 1).position,
      status: status,
      candidates: candidates
    }
  end

  @doc """
  Orders a `:chorded` segment's `candidates` (issue #17, "Ranquear
  candidatos por menor deslocamento de mão"; PRD §6.4 regra 3; SDD §3.3)
  by how little hand movement each would cost coming from
  `previous_position`, and returns the top 3 tagged with `rank` `1..3`:

      rank_candidates(candidatos, posicao_anterior):
        ordena candidatos por abs(candidato.base_fret - posicao_anterior)
        desempate: menor base_fret absoluto
        retorna os 3 primeiros, com rank 1..3

  `previous_position` is the **whole song's** last resolved segment
  position, not reset per measure (SDD §3.3, §8): the guitarist's hand
  doesn't "reset" at a measure boundary. The very first segment of a
  song uses `previous_position = 0` (open position) as its default
  reference — callers (the `:run_chord_analysis` action, issue #20) are
  responsible for threading that position across measures/segments; this
  function itself is stateless and only ranks the one list it's given.

  Ties (equal displacement from `previous_position`) are broken by the
  smallest absolute `base_fret` (SDD §8's open point on secondary tie-
  break), keeping `Enum.sort_by/2`'s stable ordering for anything still
  tied after that (mirroring `segment_measure/2`'s own tie-handling:
  whichever candidate came first in `candidates` wins).

  `candidates` is expected non-empty — an empty list (e.g. a `:no_match`
  segment) has nothing to rank and returns `[]`.
  """
  @spec rank_candidates([candidate()], integer()) :: [ranked_candidate()]
  def rank_candidates(candidates, previous_position) do
    candidates
    |> Enum.sort_by(fn %{base_fret: base_fret} ->
      {abs(base_fret - previous_position), abs(base_fret)}
    end)
    |> Enum.take(3)
    |> Enum.with_index(1)
    |> Enum.map(fn {candidate, rank} -> Map.put(candidate, :rank, rank) end)
  end

  @doc """
  Names the fundamental/root note actually sounding on the real neck for
  a `chord_shape` applied at `base_fret`, given the tab's current
  `capo_fret` (issue #19, "Considerar capotraste na análise de acordes";
  PRD §6.4 regra 5; SDD §2.3):

      nota = afinação_padrão[chord_shape.root_string] + base_fret + capo_fret  (mod 12)

  `chord_shape.root_string` picks which of the six standard-tuned open
  strings (`E A D G B E`, a compile-time constant per SDD §2.3, not a
  resource) carries the chord's root; `base_fret` is the neck position
  the shape was matched at (`candidate/0`'s own field); `capo_fret` is
  the owning `Ponteio.Tablatures.Tab.capo_fret` at analysis time.

  This is the **only** place in the whole engine that does capo
  arithmetic: `Note.fret_number` is already capo-relative by the time it
  reaches `candidates_for_window/2`/`segment_measure/2` (issue #11), so
  neither of those (nor `rank_candidates/2`) needs `capo_fret` at all —
  matching and ranking happen entirely in capo-relative terms. Naming the
  note the listener actually hears, though, requires translating that
  relative `base_fret` back onto the real neck, which is exactly what
  adding `capo_fret` here does (a capo raises every open string's pitch
  by its own fret count, so the true sounding position is `base_fret`
  frets *above the capo*, i.e. `base_fret + capo_fret` frets above the
  string's unclamped open pitch).

  Returns one of the twelve Portuguese chromatic note names (`"Dó"`,
  `"Dó#"`, `"Ré"`, `"Ré#"`, `"Mi"`, `"Fá"`, `"Fá#"`, `"Sol"`, `"Sol#"`,
  `"Lá"`, `"Lá#"`, `"Si"`), sharps only (no enharmonic flat spellings) —
  just the bare fundamental note (e.g. `"Sol"`), not the full chord name
  (e.g. not "Sol Maior"): composing this with `chord_shape.name`/
  `quality` into a full display label is the eventual caller's job
  (issue #23, "Exibir diagrama do acorde sugerido" — not yet built).
  """
  @spec root_note_name(
          Ponteio.Chords.ChordShape.t(),
          base_fret :: integer(),
          capo_fret :: integer()
        ) ::
          String.t()
  def root_note_name(chord_shape, base_fret, capo_fret) do
    open_string_index = Map.fetch!(@standard_tuning, chord_shape.root_string)
    note_index = Integer.mod(open_string_index + base_fret + capo_fret, 12)

    Enum.at(@note_names, note_index)
  end
end
