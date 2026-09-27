defmodule PonteioWeb.TabLiveTest do
  use PonteioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ponteio.Tablatures

  defp tab!(title \\ "Radical Dreamer"), do: Tablatures.create_tab!(title)

  describe "Index" do
    test "creating a tab opens it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tabs")

      assert {:error, {:live_redirect, %{to: "/tabs/" <> _id}}} =
               view |> form("#tab-form", tab: %{title: "Radical Dreamer"}) |> render_submit()

      assert [%{title: "Radical Dreamer"}] = Tablatures.list_tabs!()
    end

    test "a blank title shows an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tabs")

      assert view |> form("#tab-form", tab: %{title: ""}) |> render_submit() =~ "is required"
      assert Tablatures.list_tabs!() == []
    end

    test "deleting a tab removes it from the list", %{conn: conn} do
      tab = tab!()
      {:ok, view, _html} = live(conn, ~p"/tabs")

      view |> element("#delete-tab-#{tab.id}") |> render_click()

      refute has_element?(view, "#tabs-#{tab.id}")
      assert Tablatures.list_tabs!() == []
    end
  end

  describe "Show" do
    test "adding notes shows the hand positions for the measure", %{conn: conn} do
      tab = tab!()
      {:ok, view, _html} = live(conn, ~p"/tabs/#{tab}")

      view |> element("#add-measure") |> render_click()
      [measure] = Tablatures.list_measures!(tab.id)

      view
      |> form("#add-notes-#{measure.id}-0", notes: "E3 D0 G2 E3 B0 D0 G2 A0 D2 G2 A0 B0 D2 G2")
      |> render_submit()

      [first_note | _] = Tablatures.get_measure!(tab.id, measure.id).notes

      assert has_element?(view, "#note-#{first_note.id}", "E3")
      assert has_element?(view, "#analysis-#{measure.id}", "Gadd9")
      assert has_element?(view, "#analysis-#{measure.id}", "Asus2")
    end

    test "invalid notes show an error and add nothing", %{conn: conn} do
      tab = tab!()
      measure = Tablatures.add_measure!(tab.id)
      {:ok, view, _html} = live(conn, ~p"/tabs/#{tab}")

      html = view |> form("#add-notes-#{measure.id}-0", notes: "E3 Z1") |> render_submit()

      assert html =~ "Nota inválida: Z1"
      assert Tablatures.get_measure!(tab.id, measure.id).notes == []
    end

    test "clicking a note removes it", %{conn: conn} do
      tab = tab!()
      measure = Tablatures.add_notes!(Tablatures.add_measure!(tab.id), "E3 D0", load: [:notes])
      [first, second] = measure.notes
      {:ok, view, _html} = live(conn, ~p"/tabs/#{tab}")

      view |> element("#note-#{first.id}") |> render_click()

      refute has_element?(view, "#note-#{first.id}")
      assert has_element?(view, "#note-#{second.id}")
    end

    test "deleting a measure renumbers the rest", %{conn: conn} do
      tab = tab!()
      [first, _second] = for _ <- 1..2, do: Tablatures.add_measure!(tab.id)
      {:ok, view, _html} = live(conn, ~p"/tabs/#{tab}")

      view |> element("#delete-measure-#{first.id}") |> render_click()

      assert [%{position: 0}] = Tablatures.list_measures!(tab.id)
      assert render(view) =~ "Compasso 1"
      refute render(view) =~ "Compasso 2"
    end
  end
end
