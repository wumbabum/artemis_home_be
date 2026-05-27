defmodule Core.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        Core.Repo,
        {Core.Auth.JwksCache, name: Core.Auth.JwksCache}
      ] ++ state_cache_child()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Core.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tests stand up their own StateCache instances with isolated names
  # and table identifiers; the supervised default would collide on
  # the `:cover_state` ETS table. `:core, :start_state_cache` is
  # `true` in dev/prod (set in `config/config.exs` defaults) and
  # `false` in test (see `config/test.exs`).
  defp state_cache_child do
    if Application.get_env(:core, :start_state_cache, true) do
      [{Core.Blinds.StateCache, []}]
    else
      []
    end
  end
end
