# Mocks reachable from web app tests. Each Mox.defmock guards against
# re-definition because the same names are also defined in
# apps/core/test/support/mocks.ex; depending on test execution order
# (running just `mix test apps/web/...` vs the full umbrella) either
# file may be the first to compile in :test env.
unless Code.ensure_loaded?(Core.Auth.SessionTokenMock) do
  Mox.defmock(Core.Auth.SessionTokenMock, for: Core.Auth.SessionToken)
end

unless Code.ensure_loaded?(Core.Auth.Auth0VerifierMock) do
  Mox.defmock(Core.Auth.Auth0VerifierMock, for: Core.Auth.Auth0Verifier)
end

unless Code.ensure_loaded?(Core.Auth.ManagementApiMock) do
  Mox.defmock(Core.Auth.ManagementApiMock, for: Core.Auth.ManagementApi)
end
