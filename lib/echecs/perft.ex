defmodule Echecs.Perft do
  @moduledoc """
  Optimized perft (performance test) implementation.
  Uses integer-packed moves, bulk counting at depth 1, and stripped make_move.
  """

  alias Echecs.{Game, MoveGen}
  require Echecs.Move

  @doc """
  Standard perft with bulk counting at depth 1 and stripped make_move.
  """
  def perft(_game, 0), do: 1

  def perft(game, 1) do
    length(MoveGen.legal_moves_int(game))
  end

  def perft(game, depth) do
    MoveGen.legal_moves_int(game)
    |> Enum.reduce(0, fn move, count ->
      count + perft(Game.make_move_perft(game, move), depth - 1)
    end)
  end

  @doc """
  Perft with ETS-based transposition table.
  Requires Zobrist hash, so uses make_move_int instead of make_move_perft.
  """
  def perft_with_tt(game, depth) do
    tt = :ets.new(:perft_tt, [:set, :public])

    try do
      do_perft_tt(game, depth, tt)
    after
      :ets.delete(tt)
    end
  end

  defp do_perft_tt(_game, 0, _tt), do: 1

  defp do_perft_tt(game, 1, _tt) do
    length(MoveGen.legal_moves_int(game))
  end

  defp do_perft_tt(game, depth, tt) do
    key = {game.zobrist_hash, depth}

    case :ets.lookup(tt, key) do
      [{^key, count}] ->
        count

      [] ->
        count =
          MoveGen.legal_moves_int(game)
          |> Enum.reduce(0, fn move, acc ->
            acc + do_perft_tt(Game.make_move_int(game, move), depth - 1, tt)
          end)

        :ets.insert(tt, {key, count})
        count
    end
  end

  @doc """
  Parallel perft: distributes root moves across BEAM schedulers.
  """
  def perft_parallel(game, depth) when depth >= 3 do
    MoveGen.legal_moves_int(game)
    |> Task.async_stream(
      fn move ->
        perft(Game.make_move_perft(game, move), depth - 1)
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.reduce(0, fn {:ok, count}, acc -> acc + count end)
  end

  def perft_parallel(game, depth), do: perft(game, depth)

  @doc """
  Divide: returns per-root-move node counts (useful for debugging).
  """
  def divide(game, depth) do
    MoveGen.legal_moves_int(game)
    |> Enum.map(fn move ->
      from = Echecs.Move.unpack_from(move)
      to = Echecs.Move.unpack_to(move)
      count = if depth <= 1, do: 1, else: perft(Game.make_move_perft(game, move), depth - 1)

      {Echecs.Board.to_algebraic(from) <> Echecs.Board.to_algebraic(to), count}
    end)
    |> Enum.sort()
  end
end
