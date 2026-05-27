defmodule Web.Router do
  use Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug :accepts, ["json"]
    plug Web.Plugs.RequireSession
  end

  # Authenticated + role-gated. Guests can read blinds state but not
  # trigger HA service calls.
  pipeline :writable_role do
    plug Web.Plugs.RequireRole, allowed: ~w(admin resident)
  end

  scope "/api", Web do
    pipe_through :api

    post "/sessions", SessionController, :create
  end

  scope "/api", Web do
    pipe_through :authenticated

    get "/me/ping", MeController, :ping
    post "/admin/register-home", AdminController, :register_home

    get "/home", HomeController, :show

    get "/blinds", BlindsController, :index
    get "/blinds/states", BlindsController, :states
  end

  scope "/api", Web do
    pipe_through [:authenticated, :writable_role]

    post "/blinds/:id/position", BlindsController, :set_position
    post "/blinds/:id/open", BlindsController, :open
    post "/blinds/:id/close", BlindsController, :close
    post "/blinds/:id/stop", BlindsController, :stop
  end
end
