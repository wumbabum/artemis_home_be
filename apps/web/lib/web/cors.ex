defmodule Web.Cors do
  @moduledoc """
  Resolves the CORS allow-list at request time so changes to the
  `:web, :cors_allowed_origins` application env (sourced from
  `CORS_ALLOWED_ORIGINS` in `runtime.exs`) take effect on the next
  request rather than requiring an endpoint restart.

  Used by `Web.Endpoint`'s `CORSPlug` configuration via
  `&Web.Cors.origins/1`.
  """

  @spec origins(Plug.Conn.t()) :: [String.t()]
  def origins(_conn) do
    Application.fetch_env!(:web, :cors_allowed_origins)
  end
end
