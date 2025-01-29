defmodule Ragistry.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    :ra_system.default_config()
    |> Map.merge(Application.get_env(:ragistry, :ra_config, %{}))
    |> :ra_system.start()
  end
end
