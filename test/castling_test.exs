defmodule Echecs.CastlingTest do
  use ExUnit.Case
  alias Echecs.{Board, Game, MoveGen}

  test "Basic Castling White Kingside" do
    # R3K2R w KQ - 0 1
    # White King e1, Rooks a1, h1. Empty between e1 and h1.
    game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    # e1 (60) -> g1 (62)
    assert Board.to_index("g1") in destinations
  end

  test "Basic Castling White Queenside" do
    game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    # e1 (60) -> c1 (58)
    assert Board.to_index("c1") in destinations
  end

  test "Basic Castling Black" do
    game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
    moves = MoveGen.legal_moves(game)
    destinations = Enum.map(moves, & &1.to)

    # e8 (4) -> g8 (6) (Kingside)
    # e8 (4) -> c8 (2) (Queenside)
    assert Board.to_index("g8") in destinations
    assert Board.to_index("c8") in destinations
  end

  test "Castling Blocked" do
    # White Knight on f1. White Bishop on c1.
    # r3k2r/8/8/8/8/8/8/R1B1KN1R w KQkq - 0 1
    game = Game.new("r3k2r/8/8/8/8/8/8/R1B1KN1R w KQkq - 0 1")

    moves = MoveGen.legal_moves(game)
    king_moves = Enum.filter(moves, fn m -> m.from == Board.to_index("e1") end)
    destinations = Enum.map(king_moves, & &1.to)

    # e1 -> g1 blocked by f1
    # e1 -> c1 blocked by c1
    refute Board.to_index("g1") in destinations
    refute Board.to_index("c1") in destinations
  end

  test "Castling Out of Check (Illegal)" do
    # White King e1. Black Rook e8 (Check).
    game = Game.new("4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    assert Game.in_check?(game)

    moves = MoveGen.legal_moves(game)
    king_moves = Enum.filter(moves, fn m -> m.from == Board.to_index("e1") end)
    destinations = Enum.map(king_moves, & &1.to)

    refute Board.to_index("g1") in destinations
    refute Board.to_index("c1") in destinations
  end

  test "Castling Through Check (Illegal)" do
    # White King e1. Black Rook f8 (Attacks f1, passing square for Kingside).
    # Also Attacks f-file.
    # Kingside: e1 -> f1 -> g1. f1 is attacked.
    game = Game.new("5r2/8/8/8/8/8/8/R3K2R w KQ - 0 1")

    moves = MoveGen.legal_moves(game)
    king_moves = Enum.filter(moves, fn m -> m.from == Board.to_index("e1") end)
    destinations = Enum.map(king_moves, & &1.to)

    refute Board.to_index("g1") in destinations

    # Queenside should be fine if d1 is not attacked.
    assert Board.to_index("c1") in destinations
  end

  test "Castling Into Check (Illegal)" do
    # White King e1. Black Rook g8 (Attacks g1, destination).
    game = Game.new("6r1/8/8/8/8/8/8/R3K2R w KQ - 0 1")

    moves = MoveGen.legal_moves(game)
    king_moves = Enum.filter(moves, fn m -> m.from == Board.to_index("e1") end)
    destinations = Enum.map(king_moves, & &1.to)

    refute Board.to_index("g1") in destinations
  end

  test "Loss of Rights: King Move" do
    game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")

    # Move King e1 -> e2
    {:ok, g2} = Echecs.make_move(game, Board.to_index("e1"), Board.to_index("e2"))

    # Rights should be gone for white
    assert g2.castling.white == []
    assert g2.castling.black == [:kingside, :queenside]

    # Force turn back to white for testing
    g2_white = %{g2 | turn: :white}

    # Move back e2 -> e1 (Still no rights)
    {:ok, g3} = Echecs.make_move(g2_white, Board.to_index("e2"), Board.to_index("e1"))
    assert g3.castling.white == []
  end

  test "Loss of Rights: Rook Move" do
    game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")

    # Move Rook h1 -> h2 (Kingside rook)
    {:ok, g2} = Echecs.make_move(game, Board.to_index("h1"), Board.to_index("h2"))

    # White Kingside right gone. Queenside remains.
    assert g2.castling.white == [:queenside]
  end

  test "Loss of Rights: Rook Capture" do
    # White King e1. Black Rook a8. White captures a8 (Rxa8).
    # Setup: White Rook a1 can capture Black Rook a8? No, too far.
    # Setup: White Rook a7 captures Black Rook a8.
    game = Game.new("r3k2r/R7/8/8/8/8/8/4K2R w Kkq - 0 1")

    # White captures a8
    {:ok, g2} = Echecs.make_move(game, Board.to_index("a7"), Board.to_index("a8"))

    # Black Queenside right gone (Rook captured). Kingside remains.
    assert g2.castling.black == [:kingside]
  end
end
