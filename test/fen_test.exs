defmodule Echecs.FenTest do
  use ExUnit.Case
  alias Echecs.{Board, FEN}
  import Bitwise

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  test "parses starting FEN correctly" do
    game = FEN.parse(@start_fen)

    assert game.turn == :white
    # 15 = all castling rights (KQkq)
    assert game.castling == 15
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
    assert game.castling == 15
    assert game.en_passant == Board.to_index("c6")
    assert game.halfmove == 0
    assert game.fullmove == 2

    assert Board.at(game.board, Board.to_index("e4")) == {:white, :pawn}
    assert Board.at(game.board, Board.to_index("c5")) == {:black, :pawn}
  end

  test "parses FEN with no castling rights" do
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1"
    game = FEN.parse(fen)
    assert game.castling == 0
  end

  test "parses FEN with partial castling rights" do
    # White King side only (K), Black Queen side only (q) -> 1 (K) + 8 (q) = 9?
    # Wait, my bitmask: K=1, Q=2, k=4, q=8.
    # So Kq = 1 + 8 = 9.
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w Kq - 0 1"
    game = FEN.parse(fen)

    # Check flags individually to be sure
    # K
    assert (game.castling &&& 1) != 0
    # Q
    assert (game.castling &&& 2) == 0
    # k
    assert (game.castling &&& 4) == 0
    # q
    assert (game.castling &&& 8) != 0
  end

  test "parses FEN with move counters" do
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 10 25"
    game = FEN.parse(fen)
    assert game.halfmove == 10
    assert game.fullmove == 25
  end

  test "parses minimal FEN (Kings only)" do
    fen = "8/8/8/4k3/8/4K3/8/8 w - - 0 1"
    game = FEN.parse(fen)

    # Check board has pieces
    assert Board.at(game.board, Board.to_index("e3")) == {:white, :king}
    assert Board.at(game.board, Board.to_index("e5")) == {:black, :king}

    # Check emptiness elsewhere (sample)
    assert Board.at(game.board, 0) == nil
  end

  test "round trip FEN (parse -> string -> parse)" do
    original_fen = "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"
    game = FEN.parse(original_fen)
    generated_fen = FEN.to_string(game)

    assert generated_fen == original_fen
  end
end
