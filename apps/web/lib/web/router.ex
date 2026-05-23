defmodule Web.Router do
  use Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug :accepts, ["json"]
    plug Web.Plugs.RequireSession
  end

  scope "/api", Web do
    pipe_through :api

    post "/sessions", SessionController, :create
  end

  scope "/api", Web do
    pipe_through :authenticated

    get "/me/ping", MeController, :ping
  end
end
