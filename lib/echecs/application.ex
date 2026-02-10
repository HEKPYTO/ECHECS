defmodule Echecs.Application do
  @moduledoc false

  use Application

  alias Echecs.Bitboard.{Magic, Precomputed}
  alias Echecs.Zobrist

  @impl true
  def start(_type, _args) do
    Magic.init()
    Precomputed.init()
    Zobrist.init()

    children = []

    opts = [strategy: :one_for_one, name: Echecs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
