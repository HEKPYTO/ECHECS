defmodule Echecs.PieceLogicTest do
  use ExUnit.Case
  alias Echecs.{Board, Game, MoveGen}

  # --- Pawn Tests ---
  test "Pawn movement: white moves forward 1 or 2 squares" do
    # White King h1, Black King h8. White Pawn e2.
    game = Game.new("7k/8/8/8/8/8/4P2K/8 w - - 0 1")
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    assert Board.to_index("e3") in destinations
    assert Board.to_index("e4") in destinations
  end

  test "Pawn movement: black moves forward 1 or 2 squares" do
    # White King h1, Black King h8. Black Pawn e7.
    game = Game.new("7k/4p3/8/8/8/8/7K/8 b - - 0 1")
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    assert Board.to_index("e6") in destinations
    assert Board.to_index("e5") in destinations
  end

  test "Pawn capture: diagonal only" do
    # White King h1, Black King h8. White Pawn e4. Black Pawn d5, f5.
    game = Game.new("7k/8/8/3p1p2/4P3/8/7K/8 w - - 0 1")
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    assert Board.to_index("d5") in destinations
    assert Board.to_index("f5") in destinations
    assert Board.to_index("e5") in destinations
  end

  test "Pawn blocked" do
    # White King h1, Black King h8. White Pawn e2, Black Pawn e3.
    game = Game.new("7k/8/8/8/8/4p3/4P2K/8 w - - 0 1")
    moves = MoveGen.legal_moves(game)

    # Only pawn moves are blocked. King can move.
    pawn_idx = Board.to_index("e2")
    pawn_moves = Enum.filter(moves, fn m -> m.from == pawn_idx end)

    assert pawn_moves == []
  end

  # --- Knight Tests ---
  test "Knight jumps over pieces" do
    # White King h1, Black King h8. White Knight e4 surrounded.
    game = Game.new("7k/8/8/8/4N3/8/7K/8 w - - 0 1")
    moves = MoveGen.legal_moves(game)

    knight_idx = Board.to_index("e4")
    k_moves = Enum.filter(moves, fn m -> m.from == knight_idx end)
    destinations = Enum.map(k_moves, & &1.to)

    expected =
      ["c3", "c5", "d2", "d6", "f2", "f6", "g3", "g5"]
      |> Enum.map(&Board.to_index/1)
      |> Enum.sort()

    assert Enum.sort(destinations) == expected
  end

  test "Knight corner case" do
    # Knight a1. White King h1. Black King h8.
    game = Game.new("7k/8/8/8/8/8/7K/N7 w - - 0 1")
    moves = MoveGen.legal_moves(game)

    knight_idx = Board.to_index("a1")
    k_moves = Enum.filter(moves, fn m -> m.from == knight_idx end)
    destinations = Enum.map(k_moves, & &1.to)

    expected = ["b3", "c2"] |> Enum.map(&Board.to_index/1) |> Enum.sort()
    assert Enum.sort(destinations) == expected
  end

  # --- Bishop Tests ---
  test "Bishop moves diagonally and is blocked" do
    # White King h1, Black King h8. Bishop d4.
    fen = "7k/8/5P2/8/3B4/8/1p5K/8 w - - 0 1"
    game = Game.new(fen)
    moves = MoveGen.legal_moves(game)

    bishop_idx = Board.to_index("d4")
    b_moves = Enum.filter(moves, fn m -> m.from == bishop_idx end)
    destinations = Enum.map(b_moves, & &1.to)

    assert Board.to_index("e5") in destinations
    # Own piece
    refute Board.to_index("f6") in destinations

    assert Board.to_index("c3") in destinations
    # Capture
    assert Board.to_index("b2") in destinations
    # Behind capture
    refute Board.to_index("a1") in destinations

    assert Board.to_index("c5") in destinations
    assert Board.to_index("a7") in destinations
  end

  # --- Rook Tests ---
  test "Rook moves orthogonally" do
    # White King h1, Black King h8. Rook d4.
    fen = "7k/8/8/8/3R4/8/7K/8 w - - 0 1"
    game = Game.new(fen)
    moves = MoveGen.legal_moves(game)

    rook_idx = Board.to_index("d4")
    r_moves = Enum.filter(moves, fn m -> m.from == rook_idx end)
    destinations = Enum.map(r_moves, & &1.to)

    # 7 up, 7 down, 7 left, 7 right -> 14 moves.
    assert length(destinations) == 14
  end

  # --- Queen Tests ---
  test "Queen combines Rook and Bishop" do
    # White King h1. Queen d4.
    fen = "7k/8/8/8/3Q4/8/7K/8 w - - 0 1"
    game = Game.new(fen)
    moves = MoveGen.legal_moves(game)

    q_idx = Board.to_index("d4")
    q_moves = Enum.filter(moves, fn m -> m.from == q_idx end)

    # 14 (rook) + 13 (bishop) = 27
    assert length(q_moves) == 27
  end

  # --- King Tests ---
  test "King moves one square" do
    # King d4. Black King h8.
    fen = "7k/8/8/8/3K4/8/8/8 w - - 0 1"
    game = Game.new(fen)
    moves = MoveGen.legal_moves(game)

    # d4 King -> c3, c4, c5, d3, d5, e3, e4, e5 (8 squares)
    assert length(moves) == 8
  end

  test "King cannot move into check" do
    # White King d4. Black Rook d8.
    fen = "3r4/8/8/8/3K4/8/8/8 w - - 0 1"
    game = Game.new(fen)
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    # Cannot stay on d file (d3, d5).
    # d4 -> c3, c4, c5, e3, e4, e5. (6 moves)
    # But wait, c4 and e4 are safe. c3, c5, e3, e5 are safe.
    # d3, d5 illegal.

    refute Board.to_index("d3") in destinations
    refute Board.to_index("d5") in destinations
    assert Board.to_index("c4") in destinations
    assert length(destinations) == 6
  end

  # --- Edge Cases ---
  test "Pinned piece logic (absolute pin)" do
    # White King e1, White Bishop e2, Black Rook e8.
    # Bishop cannot move.
    fen = "4r3/8/8/8/8/8/4B3/4K3 w - - 0 1"
    game = Game.new(fen)
    moves = MoveGen.legal_moves(game)

    bishop_idx = Board.to_index("e2")
    b_moves = Enum.filter(moves, fn m -> m.from == bishop_idx end)

    # Pinned absolutely
    assert b_moves == []
  end
end
