defmodule Echecs.FenTest do
  use ExUnit.Case
  alias Echecs.{Board, FEN}

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  test "parses starting FEN correctly" do
    game = FEN.parse(@start_fen)

    assert game.turn == :white
    assert game.castling == %{white: [:kingside, :queenside], black: [:kingside, :queenside]}
    assert game.en_passant == nil
    assert game.halfmove == 0
    assert game.fullmove == 1

    # Check some pieces
    # a8
    assert Board.at(game.board, 0) == {:black, :rook}
    # e8
    assert Board.at(game.board, 4) == {:black, :king}
    # h1
    assert Board.at(game.board, 63) == {:white, :rook}
    # e1
    assert Board.at(game.board, 60) == {:white, :king}
    # e4 (empty)
    assert Board.at(game.board, 28) == nil
  end

  test "parses custom FEN correctly" do
    # Sicilian Defense: 1. e4 c5
    fen = "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"
    game = FEN.parse(fen)

    assert game.turn == :white
    assert game.castling == %{white: [:kingside, :queenside], black: [:kingside, :queenside]}
    assert game.en_passant == Board.to_index("c6")
    assert game.halfmove == 0
    assert game.fullmove == 2

    assert Board.at(game.board, Board.to_index("e4")) == {:white, :pawn}
    assert Board.at(game.board, Board.to_index("c5")) == {:black, :pawn}
  end
end
