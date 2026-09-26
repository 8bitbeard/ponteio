defmodule PonteioWeb.TabLive.StudyTest do
  @moduledoc """
  Covers `GET /tabs/:id/study` (issue #22, "Visualizar tablatura completa
  com acordes sobrepostos"; PRD §6.5, SDD §7): besides route protection and
  issue #10's "authorization denial, never a crash" scoping (same pattern
  as `TabLive.Editor`/`TabLive.Index`), this module asserts the screen
  renders every compasso and every already-computed `ChordSegment`
  (`:suggested` and `:no_match` alike) at once, with no pagination or
  extra interaction needed to reveal them — this issue's own stated
  "Testes esperados".

  Uses the real `:analyze_chords` AshOban trigger (same
  `AshOban.Test.schedule_and_run_triggers/2` harness as
  `Ponteio.Tablatures.TabRunChordAnalysisTest`) to produce genuine
  `ChordSegment`/`ChordSuggestion` rows, rather than hand-seeding them —
  exercising this LiveView's whole nested, sorted `Ash.load!/3` call
  against real relationship data.

  The last `describe` block covers issue #24 ("Atualização automática do
  modo de estudo após conclusão da análise"): the LiveView's reaction to
  `Ponteio.Tablatures.Changes.RunChordAnalysis`'s own `"tab:\#{tab_id}"`
  broadcasts (issue #20), asserted the same way that module's own test
  synchronizes with a subscriber process — sending the broadcast (or, for
  the completion case, running the real trigger, which broadcasts for
  real) and then calling `render/1`, a synchronous `GenServer` call to the
  LiveView process that only returns once every message already queued
  ahead of it (the broadcast(s) sent moments before, from this same test
  process) has been handled.
  """

  use PonteioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ponteio.Accounts.User
  alias Ponteio.Chords.ChordShape
  alias Ponteio.Tablatures.Measure
  alias Ponteio.Tablatures.Note
  alias Ponteio.Tablatures.Tab

  test "redirects an unauthenticated visitor to /sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/tabs/#{Ecto.UUID.generate()}/study")
  end

  describe "with an authenticated session" do
    setup :register_and_log_in_user

    test "an unknown tab id redirects to /tabs with a flash error, not a crash", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/tabs", flash: flash}}} =
               live(conn, ~p"/tabs/#{Ecto.UUID.generate()}/study")

      assert flash["error"] =~ "não tem permissão"
    end

    test "another user's tab id redirects to /tabs with a flash error, not the tab's content", %{
      conn: conn
    } do
      other_user = seed_user("outro@ponteio.app")

      their_tab =
        Tab
        |> Ash.Changeset.for_create(
          :create,
          %{title: "Oceano", artist: "Djavan"},
          actor: other_user
        )
        |> Ash.create!()

      assert {:error, {:redirect, %{to: "/tabs", flash: flash}}} =
               live(conn, ~p"/tabs/#{their_tab.id}/study")

      assert flash["error"] =~ "não tem permissão"
    end

    test "renders every compasso and every already-computed chord segment at once", %{
      conn: conn,
      user: user
    } do
      seed_chord_shape!("shape-estudo", 1, 3)

      tab =
        Tab
        |> Ash.Changeset.for_create(
          :create,
          %{title: "Águas de Março", artist: "Tom Jobim", capo_fret: 2},
          actor: user
        )
        |> Ash.create!()

      measure =
        Measure
        |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 1}, authorize?: false)
        |> Ash.create!()

      # position 0 (string 1, fret 3) matches the seeded shape (:suggested,
      # base_fret 0); position 1 (string 2) matches nothing, falling back to
      # a lone :no_match segment (PRD §6.4 regra 4) — same construction as
      # `Ponteio.Tablatures.TabRunChordAnalysisTest`'s equivalent case.
      Note
      |> Ash.Changeset.for_create(
        :create,
        %{measure_id: measure.id, string_number: 1, fret_number: 3, position: 0},
        authorize?: false
      )
      |> Ash.create!()

      Note
      |> Ash.Changeset.for_create(
        :create,
        %{measure_id: measure.id, string_number: 2, fret_number: 5, position: 1},
        authorize?: false
      )
      |> Ash.create!()

      assert %{success: 2, failure: 0} =
               AshOban.Test.schedule_and_run_triggers({Tab, :analyze_chords})

      {:ok, lv, html} = live(conn, ~p"/tabs/#{tab.id}/study")

      assert html =~ "Águas de Março"
      assert html =~ "Tom Jobim"
      assert html =~ "Capo na 2ª casa"
      assert has_element?(lv, "#study-measure-#{measure.id}")
      assert html =~ "Compasso 1"

      # The :suggested segment's chip: root note name reflects the tab's
      # own capo_fret (string 1, standard-tuning index 4, base_fret 0,
      # capo_fret 2 -> (4 + 0 + 2) mod 12 = 6 -> "Fá#",
      # `Ponteio.Chords.root_note_name/3`'s own arithmetic), composed with
      # the seeded shape's "Maior" quality label.
      assert html =~ "Fá# Maior"
      assert html =~ "1 de 1 sugestões"

      # The :no_match segment renders its own "sem sugestão" chip, visible
      # simultaneously with the suggested one above — no extra click/
      # navigation needed to reveal either (this issue's third acceptance
      # criterion).
      assert html =~ "sem sugestão"

      # No diagram (issue #23) and no interactive picker (issue #21's own
      # UI half) leak into this screen yet.
      refute html =~ "<select"
    end

    test "a tab with more than one compasso renders all of them in one scrollable page", %{
      conn: conn,
      user: user
    } do
      tab =
        Tab
        |> Ash.Changeset.for_create(
          :create,
          %{title: "Oceano", artist: "Djavan"},
          actor: user
        )
        |> Ash.create!()

      measure_1 =
        Measure
        |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 1}, authorize?: false)
        |> Ash.create!()

      measure_2 =
        Measure
        |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 2}, authorize?: false)
        |> Ash.create!()

      {:ok, lv, _html} = live(conn, ~p"/tabs/#{tab.id}/study")

      assert has_element?(lv, "#study-measure-#{measure_1.id}")
      assert has_element?(lv, "#study-measure-#{measure_2.id}")
    end
  end

  describe "live updates while chord analysis runs (issue #24)" do
    setup :register_and_log_in_user

    test "shows a visible indicator while :analyzing, without navigating", %{
      conn: conn,
      user: user
    } do
      tab =
        Tab
        |> Ash.Changeset.for_create(
          :create,
          %{title: "Chega de Saudade", artist: "João Gilberto"},
          actor: user
        )
        |> Ash.create!()

      {:ok, lv, html} = live(conn, ~p"/tabs/#{tab.id}/study")
      refute html =~ "Analisando"
      refute has_element?(lv, "#analyzing-banner")

      Phoenix.PubSub.broadcast(Ponteio.PubSub, "tab:#{tab.id}", :analyzing)

      html = render(lv)
      assert html =~ "Analisando"
      assert has_element?(lv, "#analyzing-banner")

      # Still the same mounted process, on the same page — no
      # redirect/push_navigate happened.
      assert render(lv) =~ "Chega de Saudade"
    end

    test "reloads chord_segments/chord_suggestions after {:analysis_completed, tab_id}, without navigating",
         %{conn: conn, user: user} do
      seed_chord_shape!("shape-live-update", 1, 3)

      tab =
        Tab
        |> Ash.Changeset.for_create(:create, %{title: "Águas de Março", artist: "Tom Jobim"},
          actor: user
        )
        |> Ash.create!()

      measure =
        Measure
        |> Ash.Changeset.for_create(:create, %{tab_id: tab.id, position: 1}, authorize?: false)
        |> Ash.create!()

      Note
      |> Ash.Changeset.for_create(
        :create,
        %{measure_id: measure.id, string_number: 1, fret_number: 3, position: 0},
        authorize?: false
      )
      |> Ash.create!()

      # Mounted *before* the tab has ever been analyzed: no chord chip
      # exists yet in the initial render.
      {:ok, lv, html} = live(conn, ~p"/tabs/#{tab.id}/study")
      refute html =~ "Maior"

      # Runs the real trigger (same harness as
      # `Ponteio.Tablatures.TabRunChordAnalysisTest`) — it broadcasts both
      # `:analyzing` and `{:analysis_completed, tab.id}` for real, on the
      # exact topic this LiveView subscribed to in `mount/3`.
      assert %{success: 2, failure: 0} =
               AshOban.Test.schedule_and_run_triggers({Tab, :analyze_chords})

      html = render(lv)

      # The newly persisted suggestion now shows up without any
      # navigation/reload of the page.
      assert html =~ "Maior"
      assert html =~ "1 de 1 sugestões"

      # And the transient :analyzing indicator is gone again, now that the
      # reloaded tab carries the final `status: :ready`.
      refute html =~ "Analisando"
    end
  end

  defp seed_chord_shape!(slug, string_number, fret_number) do
    relative_frets = List.duplicate(nil, 6) |> List.replace_at(string_number - 1, fret_number)

    Ash.Seed.seed!(ChordShape, %{
      slug: slug,
      name: "Maior",
      quality: :major,
      root_string: string_number,
      relative_frets: relative_frets,
      movable: false,
      min_base_fret: 0,
      max_base_fret: 0
    })
  end

  defp seed_user(email) do
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash("supersecret123")
    Ash.Seed.seed!(User, %{email: email, hashed_password: hashed_password})
  end
end
