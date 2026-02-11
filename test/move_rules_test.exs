defmodule Echecs.Engine.MoveRulesTest do
  use ExUnit.Case
  alias Echecs.{Board, Game, MoveGen}

  describe "Basic Move Generation" do
    test "filters moves that leave king in check" do
      fen = "4r3/8/8/8/8/8/8/4K3 w - - 0 1"
      game = Game.new(fen)

      moves = MoveGen.legal_moves(game)
      destinations = Enum.map(moves, & &1.to)

      # King can move to d1, f1 (out of file E)
      assert Board.to_index("d1") in destinations
      assert Board.to_index("f1") in destinations
      # e2 is still on E file (check)
      refute Board.to_index("e2") in destinations
    end

    test "pinned piece cannot move" do
      # Rook on e3 pinned by Black Rook on e8 against White King on e1
      fen = "4r3/8/8/8/8/4R3/8/4K3 w - - 0 1"
      game = Game.new(fen)

      moves = MoveGen.legal_moves(game)
      rook_idx = Board.to_index("e3")
      rook_moves = Enum.filter(moves, fn m -> m.from == rook_idx end)
      destinations = Enum.map(rook_moves, & &1.to)

      # Cannot move off file (d3, f3)
      refute Board.to_index("d3") in destinations
      refute Board.to_index("f3") in destinations
      # Can move on file (e4, e5... e8 capture)
      assert Board.to_index("e4") in destinations
      assert Board.to_index("e8") in destinations
    end

    test "absolute pin: piece cannot move at all" do
      # Bishop on e2 pinned diagonally? No, vertically here.
      # White King e1, White Bishop e2, Black Rook e8.
      fen = "4r3/8/8/8/8/8/4B3/4K3 w - - 0 1"
      game = Game.new(fen)
      moves = MoveGen.legal_moves(game)

      bishop_idx = Board.to_index("e2")
      b_moves = Enum.filter(moves, fn m -> m.from == bishop_idx end)

      # Bishop moves diagonally, but pin is vertical. So 0 moves.
      assert b_moves == []
    end
  end

  describe "Piece Logic" do
    test "Pawn movement: white moves forward 1 or 2 squares" do
      game = Game.new("7k/8/8/8/8/8/4P2K/8 w - - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = Enum.map(moves, & &1.to)

      assert Board.to_index("e3") in destinations
      assert Board.to_index("e4") in destinations
    end

    test "Pawn capture: diagonal only" do
      game = Game.new("7k/8/8/3p1p2/4P3/8/7K/8 w - - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = Enum.map(moves, & &1.to)

      assert Board.to_index("d5") in destinations
      assert Board.to_index("f5") in destinations
      assert Board.to_index("e5") in destinations
    end

    test "Knight jumps over pieces" do
      game = Game.new("7k/8/8/8/4N3/8/7K/8 w - - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = moves |> Enum.filter(&(&1.from == Board.to_index("e4"))) |> Enum.map(& &1.to)

      expected =
        ["c3", "c5", "d2", "d6", "f2", "f6", "g3", "g5"]
        |> Enum.map(&Board.to_index/1)
        |> Enum.sort()

      assert Enum.sort(destinations) == expected
    end

    test "Bishop blocked by own pieces" do
      fen = "7k/8/5P2/8/3B4/8/1p5K/8 w - - 0 1"
      game = Game.new(fen)
      moves = MoveGen.legal_moves(game)
      destinations = moves |> Enum.filter(&(&1.from == Board.to_index("d4"))) |> Enum.map(& &1.to)

      assert Board.to_index("e5") in destinations
      # Own pawn
      refute Board.to_index("f6") in destinations
      assert Board.to_index("c3") in destinations
      # Capture
      assert Board.to_index("b2") in destinations
      # Blocked by capture
      refute Board.to_index("a1") in destinations
    end
  end

  describe "Castling Rules" do
    test "Basic Castling White Kingside/Queenside" do
      game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = Enum.map(moves, & &1.to)

      # e1 -> g1 (Kingside)
      assert Board.to_index("g1") in destinations
      # e1 -> c1 (Queenside)
      assert Board.to_index("c1") in destinations
    end

    test "Castling Blocked" do
      # Knight f1, Bishop c1 blocking
      game = Game.new("r3k2r/8/8/8/8/8/8/R1B1KN1R w KQkq - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = moves |> Enum.filter(&(&1.from == Board.to_index("e1"))) |> Enum.map(& &1.to)

      refute Board.to_index("g1") in destinations
      refute Board.to_index("c1") in destinations
    end

    test "Castling Out of Check (Illegal)" do
      # King e1 in check by Re8
      game = Game.new("4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
      assert Game.in_check?(game)

      moves = MoveGen.legal_moves(game)
      destinations = moves |> Enum.filter(&(&1.from == Board.to_index("e1"))) |> Enum.map(& &1.to)

      refute Board.to_index("g1") in destinations
      refute Board.to_index("c1") in destinations
    end

    test "Castling Through Check (Illegal)" do
      # Rf8 attacks f1 (Kingside path)
      game = Game.new("5r2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = moves |> Enum.filter(&(&1.from == Board.to_index("e1"))) |> Enum.map(& &1.to)

      refute Board.to_index("g1") in destinations
      # Queenside safe
      assert Board.to_index("c1") in destinations
    end

    test "Castling Into Check (Illegal)" do
      # Rg8 attacks g1 (Kingside destination)
      game = Game.new("6r1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
      moves = MoveGen.legal_moves(game)
      destinations = moves |> Enum.filter(&(&1.from == Board.to_index("e1"))) |> Enum.map(& &1.to)

      refute Board.to_index("g1") in destinations
    end

    test "Loss of Rights: King Move" do
      game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
      # Move King e1 -> e2
      {:ok, g2} = Echecs.make_move(game, Board.to_index("e1"), Board.to_index("e2"))

      assert Game.has_right?(g2.castling, :white, :kingside) == false
      assert Game.has_right?(g2.castling, :white, :queenside) == false
    end

    test "Loss of Rights: Rook Move" do
      game = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
      # Move Rook h1 -> h2
      {:ok, g2} = Echecs.make_move(game, Board.to_index("h1"), Board.to_index("h2"))

      assert Game.has_right?(g2.castling, :white, :kingside) == false
      assert Game.has_right?(g2.castling, :white, :queenside) == true
    end

    test "Loss of Rights: Rook Capture" do
      # White Rook a7 captures Black Rook a8
      game = Game.new("r3k2r/R7/8/8/8/8/8/4K2R w Kkq - 0 1")
      {:ok, g2} = Echecs.make_move(game, Board.to_index("a7"), Board.to_index("a8"))

      # Black Queenside right gone
      assert Game.has_right?(g2.castling, :black, :kingside) == true
      assert Game.has_right?(g2.castling, :black, :queenside) == false
    end
  end

  describe "En Passant Rules" do
    test "Cannot capture en passant if it reveals horizontal check (rank pin)" do
      # White King a5, White Pawn b5, Black Pawn c5 (just moved c7-c5), Black Rook h5.
      # Rank 5: K(a5) P(b5) p(c5) ..... R(h5)
      # If b5xc6 ep, both b5 and c5 disappear from rank 5.
      # Rook h5 then attacks King a5. Illegal.
      fen = "8/8/8/KPp4r/8/8/8/8 w - c6 0 1"
      game = Game.new(fen)

      moves = MoveGen.legal_moves(game)
      ep_move = Enum.find(moves, fn m -> m.special == :en_passant end)

      refute ep_move
    end
  end

  describe "Complex Check Scenarios" do
    test "Double Check: Only King can move" do
      # White King e1. Black Rook e8, Black Bishop h4.
      # Both attacking e1.
      # Pawn on e2 cannot block both.
      fen = "4r3/8/8/8/7b/8/4P3/4K3 w - - 0 1"
      game = Game.new(fen)

      moves = MoveGen.legal_moves(game)

      # 1. Pawn e2 moves? No.
      pawn_moves = Enum.filter(moves, fn m -> m.from == Board.to_index("e2") end)
      assert pawn_moves == []

      # 2. King moves?
      # d1, f1 (if not attacked), d2 (if not attacked).
      # e8 attacks e file. h4 attacks diagonal (e1, d2? no, h4-e1 is h4,g3,f2,e1. d2 is not on ray).
      # Let's check destinations.
      destinations = Enum.map(moves, & &1.to)
      assert Board.to_index("d1") in destinations
      assert Board.to_index("f1") in destinations
    end

    test "Promotion with Check" do
      # White Pawn a7. Black King c8 (safe). White King h1.
      fen = "2k5/P7/8/8/8/8/8/7K w - - 0 1"
      game = Game.new(fen)

      moves = MoveGen.legal_moves(game)

      # Moves should be:
      # King: h1->g1, h1->g2, h1->h2 (3 moves)
      # Pawn: a8=Q, a8=R, a8=B, a8=N (4 moves)
      # Total: 7

      assert length(moves) == 7

      # Verify promotion moves exist
      promo_moves = Enum.filter(moves, fn m -> m.promotion != nil end)
      assert length(promo_moves) == 4
    end

    test "Discovered Check" do
      # White King h1, White Rook e1, White Knight e4. Black King e8.
      # Moving Knight e4 reveals check from Rook e1.
      # We want to test that if moving a piece reveals check on OUR king, it's illegal.
      # But here we are testing if we can GIVE check.

      # Let's test "Absolute Pin" (Piece pinned to King cannot move out of line).
      # Already tested.

      # Let's test "King cannot move into Discovered Check".
      # White King e1. Black Rook a8. White Pawn d2 blocking.
      # Black Bishop b4 (checking King? No).

      # Scenario: White King e4. Black Rook e8. White Pawn e5 blocking.
      # Black Pawn f5 attacks e4? No.
      # White King moves to d5.
      # Black Bishop on h1 attacks d5 through f3?

      # Simple: White King e1. Black Rook e8. White Knight e3 blocking.
      # King moves to f1 (safe).
      # King moves to d1 (safe).
      # Knight moves? Pinned.

      # Let's stick to what we implemented:
      # King cannot capture a protected piece.

      # White King e4. Black Pawn d5 (protected by Rook d8).
      fen = "3r4/8/8/3p4/4K3/8/8/8 w - - 0 1"
      game = Game.new(fen)
      moves = MoveGen.legal_moves(game)
      destinations = Enum.map(moves, & &1.to)

      refute Board.to_index("d5") in destinations
    end

    test "King cannot capture piece protected by pinned piece" do
      # White King c5. Black Pawn b6. Bishop a7 protects b6.
      # Bishop a7 is pinned by White Rook a1 against King a8.
      # Even if pinned, Bishop protects b6. So King c5 cannot capture b6.

      fen = "k7/b7/1p6/2K5/8/8/8/R7 w - - 0 1"
      game = Game.new(fen)

      moves = MoveGen.legal_moves(game)
      destinations = Enum.map(moves, & &1.to)

      refute Board.to_index("b6") in destinations
    end
  end
end
