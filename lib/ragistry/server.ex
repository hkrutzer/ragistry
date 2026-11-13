defmodule Ragistry.Server do
  @moduledoc false

  def id(name, node \\ node()) do
    {String.to_atom(Atom.to_string(node) <> "_" <> Atom.to_string(name)), node}
  end
end
