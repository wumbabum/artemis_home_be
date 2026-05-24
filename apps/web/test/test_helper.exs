ExUnit.start()

# Web tests share Core.Repo; mirror Core's manual Sandbox mode so async:
# true tests get isolated connections and async: false tests can opt into
# `shared` ownership for endpoint-spawned request processes.
Ecto.Adapters.SQL.Sandbox.mode(Core.Repo, :manual)
