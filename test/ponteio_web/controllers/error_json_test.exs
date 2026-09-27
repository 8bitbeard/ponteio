defmodule PonteioWeb.ErrorJSONTest do
  use PonteioWeb.ConnCase, async: true

  test "renders 404" do
    assert PonteioWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert PonteioWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
