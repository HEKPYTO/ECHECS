defmodule Echecs.PGNTest do
  use ExUnit.Case
  alias Echecs.{Board, Game, PGN}

  test "parses and plays a simple game" do
    pgn = "1. e4 e5 2. Nf3 Nc6 3. Bb5"
    moves = PGN.parse_moves(pgn)

    assert moves == ["e4", "e5", "Nf3", "Nc6", "Bb5"]

    game = Game.new()
    result = PGN.replay(game, moves)

    assert match?(%Game{}, result)
    assert Board.at(result.board, Board.to_index("b5")) == {:white, :bishop}
  end

  test "plays castling" do
    pgn = "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O"
    moves = PGN.parse_moves(pgn)

    game = Game.new()
    result = PGN.replay(game, moves)

    assert match?(%Game{}, result)
    assert Board.at(result.board, Board.to_index("g1")) == {:white, :king}
    assert Board.at(result.board, Board.to_index("f1")) == {:white, :rook}
  end

  test "regression: Rd1d2 parsing issue" do
    pgn =
      "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 11. c4 c6 12. cxb5 axb5 13. Nc3 Bb7 14. Bg5 h6 15. Bh4 b4 16. Na4 c5 17. dxc5 dxc5 18. Bxf6 Bxf6 19. Rc1 Be7 20. Qc2 Qc7 21. Red1 Rfd8 22. Qc4 Rf8 23. Qxb4 Bc6 24. Qc4 Qb7 25. Nc3 Nb6 26. Qe2 Bf6 27. Rd6 Rfd8 28. Rcd1 Rxd6 29. Rxd6 Rd8 30. Rxd8+ Bxd8 31. Nxe5 Be8 32. Qd3 Bf6 33. Nc4 Nxc4 34. Qxc4 Bd4 35. Qd5 Qe7 36. Qa8 Kh7 37. Nd5 Qxe4 38. Nf6+ Bxf6 39. Qxe4+ g6 40. Qxe8"

    moves = PGN.parse_moves(pgn)
    game = Game.new()
    result = PGN.replay(game, moves)

    assert match?(%Game{}, result)
  end

  test "parses moves with check (+) and mate (#) symbols" do
    pgn = "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#"
    moves = PGN.parse_moves(pgn)

    assert moves == ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7#"]

    game = Game.new()
    result = PGN.replay(game, moves)

    assert match?(%Game{}, result)
    assert Game.checkmate?(result)
  end

  test "parses moves with promotion" do
    # White pawn on a7.
    # 1. a8=Q
    pgn = "1. a8=Q"
    # Need custom setup, PGN usually starts from startpos.
    # But parse_moves just returns strings.
    moves = PGN.parse_moves(pgn)
    assert moves == ["a8=Q"]

    # Can we replay from custom FEN?
    # PGN.replay takes a game struct.
    fen = "8/P7/8/8/8/8/k6K/8 w - - 0 1"
    game = Game.new(fen)

    result = PGN.replay(game, moves)
    assert Board.at(result.board, Board.to_index("a8")) == {:white, :queen}
  end

  test "parses disambiguated moves" do
    # 1. Nbd2
    pgn = "1. Nbd2"
    moves = PGN.parse_moves(pgn)
    assert moves == ["Nbd2"]

    # Test specific disambiguation logic
    # Rooks on a1, e1. Move to c1.
    # Rae1? Rac1.
    fen = "4k3/8/8/8/8/8/8/R3R2K w - - 0 1"
    game = Game.new(fen)

    # Test Rac1
    {:ok, move} = PGN.move_from_san(game, "Rac1")
    assert move.from == Board.to_index("a1")
    assert move.to == Board.to_index("c1")

    # Test Rec1
    {:ok, move2} = PGN.move_from_san(game, "Rec1")
    assert move2.from == Board.to_index("e1")
    assert move2.to == Board.to_index("c1")
  end
end
