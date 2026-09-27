defmodule PonteioWeb.PageController do
  use PonteioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
