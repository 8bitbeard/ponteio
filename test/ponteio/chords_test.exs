defmodule Ponteio.ChordsTest do
  @moduledoc """
  Covers `Ponteio.Chords.candidates_for_window/2` (issue #15, "Calcular
  candidatos de acorde para uma janela de notas"; PRD §6.4 regra 1; SDD
  §3.1) — the atomic subset-matching operation the whole chord-suggestion
  engine is built on top of.

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
end
