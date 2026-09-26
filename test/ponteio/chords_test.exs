defmodule Ponteio.ChordsTest do
  @moduledoc """
  Covers `Ponteio.Chords.candidates_for_window/2` (issue #15, "Calcular
  candidatos de acorde para uma janela de notas"; PRD §6.4 regra 1; SDD
  §3.1), `segment_measure/2` (issue #16; PRD §6.4 regra 2; SDD §3.2) and
  `rank_candidates/2` (issue #17, "Ranquear candidatos por menor
  deslocamento de mão"; PRD §6.4 regra 3; SDD §3.3) — the atomic
  subset-matching operation the whole chord-suggestion engine is built
  on top of, plus the segmentation and ranking layered on it.

  Plain ExUnit, no `Ponteio.DataCase`: this function is pure Elixir (not
  an Ash action) and its fixtures are plain `%ChordShape{}` structs built
  in-memory, per SDD §6 ("não depende de banco, Ash ou LiveView").
  """

  use ExUnit.Case, async: true

  alias Ponteio.Chords
  alias Ponteio.Chords.ChordShape

  # E maior aberto: E(6)=0, B(5)=2, E(4)=2, G(3)=1, B(2)=0, e(1)=0.
  # relative_frets is ordered high E (string 1) .. low E (string 6).
  defp e_major_open do
    %ChordShape{
      slug: "e-major-open",
      name: "Maior",
      quality: :major,
      root_string: 6,
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0,
      relative_frets: [0, 0, 1, 2, 2, 0]
    }
  end

  # A maior, pestana móvel (formato "E" na 5ª corda como raiz): mesma
  # forma relativa do E maior aberto, mas movível em qualquer base_fret
  # de 1 a 12 (a corda 6, se tocada, fica abafada nessa forma — nil).
  defp barre_major_shape do
    %ChordShape{
      slug: "barre-major-e-shape",
      name: "Maior",
      quality: :major,
      root_string: 5,
      movable: true,
      min_base_fret: 1,
      max_base_fret: 12,
      relative_frets: [0, 0, 1, 2, 2, nil]
    }
  end

  # Outra forma aberta hipotética, só para exercitar "múltiplos
  # candidatos de shapes distintos": casa nas mesmas duas primeiras
  # cordas do E maior aberto (por isso bate na mesma janela reduzida),
  # mas com um formato diferente nas demais cordas (irrelevantes pois
  # não aparecem na janela dos testes que a usam).
  defp other_open_shape_matching_strings_one_and_two do
    %ChordShape{
      slug: "other-open-shape",
      name: "Maior",
      quality: :major,
      root_string: 4,
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0,
      relative_frets: [0, 0, 3, 4, 5, nil]
    }
  end

  # C maior aberto: E(6)=abafada, A(5)=3, D(4)=2, G(3)=0, B(2)=1, e(1)=0.
  defp c_major_open do
    %ChordShape{
      slug: "c-major-open",
      name: "Maior",
      quality: :major,
      root_string: 5,
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0,
      relative_frets: [0, 1, 0, 2, 3, nil]
    }
  end

  describe "candidates_for_window/2" do
    test "returns no candidates when no shape matches the window" do
      # Nota isolada na corda 1, casa 5: nenhum dos shapes abaixo produz
      # essa nota em nenhum base_fret dentro da própria janela.
      window = [{1, 5}]

      assert Chords.candidates_for_window(window, [e_major_open(), c_major_open()]) == []
    end

    test "returns exactly one candidate when only one shape/base_fret matches" do
      # Janela parcial do C maior aberto: só a corda 3 (casa 0) e a corda 2
      # (casa 1) tocadas nesse trecho. Bate por subconjunto no C maior
      # aberto; não bate no E maior aberto (que espera casa 1 na corda 3).
      window = [{3, 0}, {2, 1}]

      assert [%{chord_shape: matched, base_fret: 0}] =
               Chords.candidates_for_window(window, [e_major_open(), c_major_open()])

      assert matched.slug == "c-major-open"
    end

    test "matches by subset: strings the shape defines but the window doesn't play don't block the match" do
      # Janela com uma única nota do E maior aberto (corda 1, casa 0):
      # as outras 5 cordas do shape não aparecem na janela e não impedem
      # o match, por ser correspondência por subconjunto (PRD §6.4 regra 1).
      window = [{1, 0}]

      assert [%{chord_shape: matched, base_fret: 0}] =
               Chords.candidates_for_window(window, [e_major_open()])

      assert matched.slug == "e-major-open"
    end

    test "a note on a string the shape mutes at every base_fret never matches" do
      # C maior aberto abafa a corda 6 (relative_frets index 5 == nil);
      # qualquer nota tocada na corda 6 descarta esse shape, mesmo que as
      # demais notas da janela batam.
      window = [{6, 0}, {5, 3}]

      assert Chords.candidates_for_window(window, [c_major_open()]) == []
    end

    test "returns one candidate per base_fret a movable shape's window pins to" do
      # Para uma janela não-vazia, cada nota fixa um único base_fret
      # possível por shape (fret == relative_fret + base_fret tem só uma
      # solução) — aqui a janela só bate com a forma móvel em base_fret 3.
      window = [{1, 3}, {2, 3}]

      assert [%{chord_shape: matched, base_fret: 3}] =
               Chords.candidates_for_window(window, [barre_major_shape()])

      assert matched.slug == "barre-major-e-shape"
    end

    test "returns multiple candidates across distinct shapes matching the same window" do
      # Janela compatível tanto com o E maior aberto quanto com a outra
      # forma aberta fictícia (que só compartilha as duas primeiras
      # cordas com o E maior) — ambas casam em base_fret 0.
      window = [{1, 0}, {2, 0}]

      candidates =
        Chords.candidates_for_window(
          window,
          [e_major_open(), other_open_shape_matching_strings_one_and_two()]
        )

      assert length(candidates) == 2
      assert Enum.all?(candidates, &(&1.base_fret == 0))

      slugs = Enum.map(candidates, & &1.chord_shape.slug)
      assert "e-major-open" in slugs
      assert "other-open-shape" in slugs
    end

    test "an empty window vacuously matches every base_fret of every shape" do
      # Sem notas para checar, todo par {shape, base_fret} passa —
      # documentado no @doc de candidates_for_window/2. Isso é o único
      # jeito de um MESMO shape aparecer em múltiplos base_frets num
      # único retorno, já que uma janela não-vazia fixa no máximo um
      # base_fret por shape (ver teste anterior).
      candidates = Chords.candidates_for_window([], [barre_major_shape()])

      assert length(candidates) == 12
      assert Enum.map(candidates, & &1.base_fret) |> Enum.sort() == Enum.to_list(1..12)
    end
  end

  describe "segment_measure/2" do
    # A `measure_note()` doesn't have to be a `Ponteio.Tablatures.Note`
    # struct — this module's own moduledoc says these functions "take/
    # return plain data" — so a plain map with the three keys the
    # typedoc requires is enough, and keeps this test file DB/Ash-free
    # like `candidates_for_window/2`'s (SDD §6).
    defp note(string_number, fret_number, position) do
      %{string_number: string_number, fret_number: fret_number, position: position}
    end

    test "an empty measure has no segments" do
      assert Chords.segment_measure([], [e_major_open(), c_major_open()]) == []
    end

    test "a measure whose notes all fit a single candidate is one chorded segment" do
      # Strings 1, 2 and 6 all at fret 0: matches the E maior aberto shape
      # (index 0, 1 and 5 of its relative_frets are all 0) as a single
      # window; the C maior aberto shape mutes string 6, so it can never
      # be a candidate here regardless of grouping.
      notes = [note(1, 0, 0), note(2, 0, 1), note(6, 0, 2)]

      assert [segment] = Chords.segment_measure(notes, [e_major_open(), c_major_open()])

      assert segment.start_position == 0
      assert segment.end_position == 2
      assert segment.status == :chorded
      assert [%{chord_shape: matched, base_fret: 0}] = segment.candidates
      assert matched.slug == "e-major-open"
    end

    test "a measure that needs a chord change midway is two chorded segments" do
      # Positions 0-1 (strings 1 and 2 at fret 0) only fit E maior aberto;
      # positions 2-3 (strings 3 and 2, fret 0 and 1) only fit C maior
      # aberto (same window as the `candidates_for_window/2` test above).
      # The two windows can't be merged into one: string 2 would need to
      # be fret 0 (from position 1) and fret 1 (from position 3) at once,
      # which no single `{shape, base_fret}` pair can satisfy — forcing
      # the chord change the dynamic programming recurrence must find.
      notes = [note(1, 0, 0), note(2, 0, 1), note(3, 0, 2), note(2, 1, 3)]

      assert [first, second] =
               Chords.segment_measure(notes, [e_major_open(), c_major_open()])

      assert first.start_position == 0
      assert first.end_position == 1
      assert first.status == :chorded
      assert [%{chord_shape: first_match}] = first.candidates
      assert first_match.slug == "e-major-open"

      assert second.start_position == 2
      assert second.end_position == 3
      assert second.status == :chorded
      assert [%{chord_shape: second_match}] = second.candidates
      assert second_match.slug == "c-major-open"
    end

    test "an isolated note with no candidate forces a 3rd, no_match segment" do
      # Same chorded E/C aberto windows as the previous test, but with a
      # note at position 2 (string 1, fret 5) sandwiched between them that
      # no shape can ever produce at base_fret 0 (both shapes are fixed at
      # min/max_base_fret 0) — it can't join either neighbor into a wider
      # matching window, and a `no_match` window is only ever accepted at
      # size 1, so it must surface as its own segment.
      notes = [
        note(1, 0, 0),
        note(2, 0, 1),
        note(1, 5, 2),
        note(3, 0, 3),
        note(2, 1, 4)
      ]

      assert [first, isolated, third] =
               Chords.segment_measure(notes, [e_major_open(), c_major_open()])

      assert first.start_position == 0
      assert first.end_position == 1
      assert first.status == :chorded

      assert isolated.start_position == 2
      assert isolated.end_position == 2
      assert isolated.status == :no_match
      assert isolated.candidates == []

      assert third.start_position == 3
      assert third.end_position == 4
      assert third.status == :chorded
      assert [%{chord_shape: third_match}] = third.candidates
      assert third_match.slug == "c-major-open"
    end

    test "notes out of insertion order are sorted by position before segmenting" do
      notes = [note(2, 0, 1), note(1, 0, 0)]

      assert [segment] = Chords.segment_measure(notes, [e_major_open()])

      assert segment.start_position == 0
      assert segment.end_position == 1
      assert segment.status == :chorded
    end
  end

  describe "rank_candidates/2" do
    # These candidates only need a `chord_shape`/`base_fret` pair — the
    # tests only care about ordering by `base_fret` displacement, so the
    # `chord_shape` value itself is an arbitrary, distinguishable atom
    # rather than a full `%ChordShape{}` fixture like the other describe
    # blocks build (SDD §3.3's algorithm never inspects `chord_shape`).
    defp candidate(chord_shape, base_fret) do
      %{chord_shape: chord_shape, base_fret: base_fret}
    end

    test "orders candidates by ascending absolute displacement from the previous position" do
      candidates = [
        candidate(:far, 10),
        candidate(:near, 3),
        candidate(:middle, 6)
      ]

      assert Chords.rank_candidates(candidates, 2) == [
               %{chord_shape: :near, base_fret: 3, rank: 1},
               %{chord_shape: :middle, base_fret: 6, rank: 2},
               %{chord_shape: :far, base_fret: 10, rank: 3}
             ]
    end

    test "ties on displacement are broken by the smallest absolute base_fret" do
      # previous_position = 5: :low (base_fret 2) and :high (base_fret 8)
      # are both 3 away from 5, but |2| < |8|, so :low ranks first.
      candidates = [candidate(:high, 8), candidate(:low, 2)]

      assert Chords.rank_candidates(candidates, 5) == [
               %{chord_shape: :low, base_fret: 2, rank: 1},
               %{chord_shape: :high, base_fret: 8, rank: 2}
             ]
    end

    test "only the top 3 candidates are returned when there are more than 3" do
      candidates = [
        candidate(:d, 9),
        candidate(:a, 0),
        candidate(:c, 6),
        candidate(:b, 3)
      ]

      assert [first, second, third] = Chords.rank_candidates(candidates, 0)

      assert {first.chord_shape, first.rank} == {:a, 1}
      assert {second.chord_shape, second.rank} == {:b, 2}
      assert {third.chord_shape, third.rank} == {:c, 3}
    end

    test "the first segment of a song ranks against previous_position 0" do
      candidates = [candidate(:open, 0), candidate(:barre, 3)]

      assert Chords.rank_candidates(candidates, 0) == [
               %{chord_shape: :open, base_fret: 0, rank: 1},
               %{chord_shape: :barre, base_fret: 3, rank: 2}
             ]
    end

    test "an empty candidate list (e.g. a no_match segment) ranks to an empty list" do
      assert Chords.rank_candidates([], 0) == []
    end
  end

  describe "root_note_name/3" do
    # root_string 6 = low E (open string index 4, "Mi") — see e_major_open/0.
    test "an open shape (base_fret 0) with no capo names the open string's own note" do
      assert Chords.root_note_name(e_major_open(), 0, 0) == "Mi"
    end

    # root_string 5 = A (open string index 9, "Lá") — see barre_major_shape/0.
    test "a barre shape's root reflects its base_fret with no capo" do
      # Lá (9) + base_fret 3 = 12 -> mod 12 = 0 -> Dó.
      assert Chords.root_note_name(barre_major_shape(), 3, 0) == "Dó"
    end

    test "the capo shifts the named root note by its own fret count" do
      # Mi (4) + base_fret 0 + capo_fret 2 = 6 -> Fá#.
      assert Chords.root_note_name(e_major_open(), 0, 2) == "Fá#"
    end

    test "two tabs with the same relative notes but different capo_fret name different roots" do
      # Same chord_shape/base_fret (as a same-relative-notes reanalysis
      # would produce, PRD §6.4 regra 5's own "Testes esperados"), only
      # capo_fret differs.
      shape = e_major_open()

      assert Chords.root_note_name(shape, 0, 0) == "Mi"
      assert Chords.root_note_name(shape, 0, 3) == "Sol"
    end

    test "wraps around the chromatic scale past Si back to Dó" do
      # Si (11) + base_fret 1 + capo_fret 0 = 12 -> mod 12 = 0 -> Dó.
      shape = %{c_major_open() | root_string: 2}
      assert Chords.root_note_name(shape, 1, 0) == "Dó"
    end
  end
end
