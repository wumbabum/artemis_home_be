defmodule Web.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Web.Telemetry,
      # PubSub is normally started by the Ecto app in an umbrella, but this
      # umbrella has no Ecto app, so the web app starts it directly.
      {Phoenix.PubSub, name: Web.PubSub},
      # Start a worker by calling: Web.Worker.start_link(arg)
      # {Web.Worker, arg},
      # Start to serve requests, typically the last entry
      Web.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Web.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Web.Endpoint.config_change(changed, removed)
    :ok
  end
end
