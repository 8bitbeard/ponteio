defmodule PonteioWeb.TabLive.ChordDiagramComponentTest do
  @moduledoc """
  Covers `ChordDiagramComponent.chord_diagram/1` directly (issue #23,
  "Exibir diagrama do acorde sugerido"; PRD §6.5; SDD §4) — this issue's
  own "Testes esperados": the component renders correctly for an open
  shape (`base_fret = 0`), a barre shape (`base_fret > 0`), and a shape
  with muted strings (`nil` in `relative_frets`).

  Plain `ExUnit.Case` + `Phoenix.LiveViewTest.render_component/2`, no
  `Ponteio.DataCase`/`ConnCase`: the component is a stateless function
  component rendered from a plain in-memory `%ChordShape{}` struct (same
  fixture style as `Ponteio.ChordsTest`), needing only `@endpoint` for
  `render_component/2` to work — no database, Ash, or live connection
  involved. Assertions target `data-marker`/`data-string`/`data-row`
  attributes (via `LazyHTML`, per this repo's testing guidelines) rather
  than exact SVG pixel geometry, which is an implementation detail.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Ponteio.Chords.ChordShape
  alias PonteioWeb.TabLive.ChordDiagramComponent

  @endpoint PonteioWeb.Endpoint

  # E maior aberto: E(6)=0, A(5)=2, D(4)=2, G(3)=1, B(2)=0, e(1)=0 — no
  # muted strings, `base_fret = 0` (SDD §2.3's open-shape convention).
  # `relative_frets` stored high e (string 1) .. low E (string 6).
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

  # "A-shape" barre, movable: A(5)=root(0), D(4)=2, G(3)=2, B(2)=2, e(1)=0,
  # low E(6) muted (`nil`) — exercises both a barre (`base_fret > 0`) and
  # a muted string in the same shape, same seeded data shape as
  # `priv/repo/seeds.exs`'s `barre-a-shape-major`.
  defp a_shape_barre_major do
    %ChordShape{
      slug: "barre-a-shape-major",
      name: "Maior",
      quality: :major,
      root_string: 5,
      movable: true,
      min_base_fret: 1,
      max_base_fret: 9,
      relative_frets: [0, 2, 2, 2, 0, nil]
    }
  end

  describe "an open shape (base_fret = 0)" do
    setup do
      html =
        render_component(&ChordDiagramComponent.chord_diagram/1,
          chord_shape: e_major_open(),
          base_fret: 0,
          id: "diagram-open"
        )

      %{document: LazyHTML.from_fragment(html)}
    end

    test "draws a fretted dot for every non-open, non-muted string", %{document: document} do
      dots = LazyHTML.query(document, "circle[data-marker='fretted']")

      assert Enum.count(dots) == 3

      # string 3 (G) relative_fret 1 -> real fret 1 (base_fret 0, row ==
      # relative_fret directly); strings 4 and 5 (D, A) relative_fret 2 ->
      # real fret 2.
      assert row_for(dots, "3") == "1"
      assert row_for(dots, "4") == "2"
      assert row_for(dots, "5") == "2"
    end

    test "marks the remaining strings open, not fretted", %{document: document} do
      open_marks = LazyHTML.query(document, "text[data-marker='open']")

      assert Enum.count(open_marks) == 3
      assert Enum.sort(LazyHTML.attribute(open_marks, "data-string")) == ["1", "2", "6"]
    end

    test "has no muted string and no base-fret label", %{document: document} do
      assert Enum.empty?(LazyHTML.query(document, "[data-marker='muted']"))
      assert Enum.empty?(LazyHTML.query(document, "[data-marker='base-fret']"))
    end

    test "carries the given id on the root svg", %{document: document} do
      assert Enum.count(LazyHTML.query_by_id(document, "diagram-open")) == 1
    end
  end

  describe "a barre shape with a muted string (base_fret > 0)" do
    setup do
      html =
        render_component(&ChordDiagramComponent.chord_diagram/1,
          chord_shape: a_shape_barre_major(),
          base_fret: 3
        )

      %{document: LazyHTML.from_fragment(html)}
    end

    test "draws the low E string muted, not open and not fretted", %{document: document} do
      muted = LazyHTML.query(document, "text[data-marker='muted']")

      assert Enum.count(muted) == 1
      assert LazyHTML.attribute(muted, "data-string") == ["6"]
      assert Enum.empty?(LazyHTML.query(document, "text[data-marker='open']"))
    end

    test "draws the barre itself (relative_fret 0) as a fretted dot in the first row, not open",
         %{
           document: document
         } do
      dots = LazyHTML.query(document, "circle[data-marker='fretted']")

      # strings 5 (A, root) and 1 (e), relative_fret 0 -> row 1 (base_fret
      # > 0, so offset 0 is the barre itself, not an open string).
      assert row_for(dots, "5") == "1"
      assert row_for(dots, "1") == "1"

      # strings 4, 3, 2, relative_fret 2 -> row 3.
      assert row_for(dots, "4") == "3"
      assert row_for(dots, "3") == "3"
      assert row_for(dots, "2") == "3"

      assert Enum.count(dots) == 5
    end

    test "shows the base_fret as a neck-position label", %{document: document} do
      label = LazyHTML.query(document, "[data-marker='base-fret']")

      assert Enum.count(label) == 1
      assert LazyHTML.text(label) =~ "3"
    end
  end

  test "root svg carries an accessible label naming the chord and its neck position" do
    open_html =
      render_component(&ChordDiagramComponent.chord_diagram/1,
        chord_shape: e_major_open(),
        base_fret: 0
      )

    barre_html =
      render_component(&ChordDiagramComponent.chord_diagram/1,
        chord_shape: a_shape_barre_major(),
        base_fret: 3
      )

    assert open_html =~ "posição aberta"
    assert barre_html =~ "3ª casa"
  end

  defp row_for(dots, string) do
    dots
    |> LazyHTML.filter("[data-string='#{string}']")
    |> LazyHTML.attribute("data-row")
    |> List.first()
  end
end
