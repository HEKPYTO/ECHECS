defmodule Echecs.Perft do
  @moduledoc """
  Performance-test helpers for validating move generation.
  """

  alias Echecs.{Board, Game, MoveGen}

  require Echecs.Move

  @doc """
  Counts leaf nodes from the given game state.
  """
  @spec perft(Game.t(), non_neg_integer()) :: non_neg_integer()
  def perft(%Game{} = game, depth) do
    perft_fast(game.board, game.turn, game.castling, game.en_passant, game.king_pos, depth)
  end

  @doc """
  Counts leaf nodes from raw position fields.
  """
  @spec perft_fast(
          Board.board_tuple(),
          Echecs.Piece.color(),
          non_neg_integer(),
          Board.square() | nil,
          non_neg_integer()
        ) :: non_neg_integer()
  def perft_fast(board, turn, castling, en_passant, depth) do
    perft_fast(board, turn, castling, en_passant, Game.king_positions(board), depth)
  end

  @doc false
  @spec perft_fast(
          Board.board_tuple(),
          Echecs.Piece.color(),
          non_neg_integer(),
          Board.square() | nil,
          Game.king_pos(),
          non_neg_integer()
        ) :: non_neg_integer()
  def perft_fast(_board, _turn, _castling, _en_passant, _king_pos, 0), do: 1

  def perft_fast(board, turn, castling, en_passant, _king_pos, 1) do
    length(MoveGen.legal_moves_int(board, turn, castling, en_passant))
  end

  def perft_fast(board, turn, castling, en_passant, king_pos, depth) do
    MoveGen.legal_moves_int(board, turn, castling, en_passant)
    |> Enum.reduce(0, fn move, count ->
      {new_board, new_turn, new_castling, new_en_passant, new_king_pos} =
        Game.advance_position(board, turn, castling, en_passant, king_pos, move)

      count +
        perft_fast(new_board, new_turn, new_castling, new_en_passant, new_king_pos, depth - 1)
    end)
  end

  @doc """
  Counts leaf nodes with an ETS-backed transposition table.
  """
  @spec perft_with_tt(Game.t(), non_neg_integer()) :: non_neg_integer()
  def perft_with_tt(%Game{} = game, depth) do
    tt = :ets.new(:perft_tt, [:set, :public])

    try do
      do_perft_tt(game, depth, tt)
    after
      :ets.delete(tt)
    end
  end

  @doc """
  Distributes root nodes across schedulers.
  """
  @spec perft_parallel(Game.t(), non_neg_integer()) :: non_neg_integer()
  def perft_parallel(%Game{} = game, depth) when depth >= 3 do
    MoveGen.legal_moves_int(game.board, game.turn, game.castling, game.en_passant)
    |> Task.async_stream(
      fn move ->
        {new_board, new_turn, new_castling, new_en_passant, new_king_pos} =
          Game.advance_position(
            game.board,
            game.turn,
            game.castling,
            game.en_passant,
            game.king_pos,
            move
          )

        perft_fast(new_board, new_turn, new_castling, new_en_passant, new_king_pos, depth - 1)
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.reduce(0, fn {:ok, count}, acc -> acc + count end)
  end

  def perft_parallel(%Game{} = game, depth), do: perft(game, depth)

  @doc """
  Returns per-root-move node counts for debugging.
  """
  @spec divide(Game.t(), non_neg_integer()) :: [{String.t(), non_neg_integer()}]
  def divide(%Game{} = game, depth) do
    MoveGen.legal_moves_int(game.board, game.turn, game.castling, game.en_passant)
    |> Enum.map(fn move ->
      from = Echecs.Move.unpack_from(move)
      to = Echecs.Move.unpack_to(move)

      count =
        if depth <= 1 do
          1
        else
          {new_board, new_turn, new_castling, new_en_passant, new_king_pos} =
            Game.advance_position(
              game.board,
              game.turn,
              game.castling,
              game.en_passant,
              game.king_pos,
              move
            )

          perft_fast(new_board, new_turn, new_castling, new_en_passant, new_king_pos, depth - 1)
        end

      {Board.to_algebraic(from) <> Board.to_algebraic(to), count}
    end)
    |> Enum.sort()
  end

  defp do_perft_tt(_game, 0, _tt), do: 1

  defp do_perft_tt(%Game{} = game, 1, _tt) do
    length(MoveGen.legal_moves_int(game.board, game.turn, game.castling, game.en_passant))
  end

  defp do_perft_tt(%Game{} = game, depth, tt) do
    key = {game.zobrist_hash, depth}

    case :ets.lookup(tt, key) do
      [{^key, count}] ->
        count

      [] ->
        count =
          MoveGen.legal_moves_int(game.board, game.turn, game.castling, game.en_passant)
          |> Enum.reduce(0, fn move, acc ->
            acc + do_perft_tt(Game.make_move_int(game, move), depth - 1, tt)
          end)

        :ets.insert(tt, {key, count})
        count
    end
  end
end
