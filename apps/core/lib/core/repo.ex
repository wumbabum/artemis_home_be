defmodule Core.Repo do
  @moduledoc """
  Ecto repository for the BE. Backed by Postgres.

  Configuration is loaded per-env from `config/{dev,test,prod}.exs`
  and `config/runtime.exs`. The Repo is added to the supervision tree
  in a follow-up commit (SB2) once the per-env database config is
  in place; this module by itself does not open any connection.
  """

  use Ecto.Repo,
    otp_app: :core,
    adapter: Ecto.Adapters.Postgres
end
