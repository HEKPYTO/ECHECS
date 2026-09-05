defmodule Echecs do
  @moduledoc """
  Echecs is a pure Elixir chess library for move generation, validation, and game state management.

  This module is the main entry point: `new_game/0` and `new_game/1` build a `%Echecs.Game{}`
  from the start position or a FEN string, `legal_moves/1` lists legal moves,
  `make_move/4` applies one if legal (`{:ok, game}` / `{:error, :illegal_move}`),
  and `status/1` reports `:active`, `:checkmate`, `:stalemate` or `:draw`.
  Internals live in `Echecs.Game`, `Echecs.MoveGen` and `Echecs.Board`.
  """

  alias Echecs.{Game, MoveGen}

  @doc """
  Starts a new chess game with the standard starting position.
  """
  def new_game do
    Game.new()
  end

  @doc """
  Starts a new chess game from a given FEN string.
  """
  def new_game(fen) do
    Game.new(fen)
  end

  @doc """
  Returns a list of all legal moves for the current game state.
  """
  def legal_moves(%Game{} = game) do
    MoveGen.legal_moves(game)
  end

  @doc """
  Makes a move if it is legal.

  Returns `{:ok, new_game}` or `{:error, reason}`.
  """
  def make_move(%Game{} = game, from_sq, to_sq, promotion \\ nil) do
    moves = legal_moves(game)

    move =
      Enum.find(moves, fn m ->
        m.from == from_sq and m.to == to_sq and m.promotion == promotion
      end)

    if move do
      {:ok, Game.make_move(game, move)}
    else
      {:error, :illegal_move}
    end
  end

  @doc """
  Returns the current status of the game (:active, :checkmate, :stalemate, :draw).
  """
  def status(%Game{} = game) do
    cond do
      Game.checkmate?(game) -> :checkmate
      Game.stalemate?(game) -> :stalemate
      Game.draw?(game) -> :draw
      true -> :active
    end
  end
end
