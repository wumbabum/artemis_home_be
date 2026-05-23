ExUnit.start()

# Manual checkout per test so async: false tests can share a connection
# and async: true tests get isolated ones. Tests that touch the DB call
# `Ecto.Adapters.SQL.Sandbox.checkout(Core.Repo)` in setup; pure-unit
# tests can ignore this.
Ecto.Adapters.SQL.Sandbox.mode(Core.Repo, :manual)
