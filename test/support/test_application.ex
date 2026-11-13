defmodule Ragistry.TestApplication do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: Ragistry.TestSupervisor)
  end
end
