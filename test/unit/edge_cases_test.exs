defmodule Echecs.EdgeCasesTest do
  use ExUnit.Case
  alias Echecs.Game

  describe "Draw conditions" do
    test "Stalemate" do
      # Black king at h8, White Queen at f7, White king at h6.
      # Black to move. King has no moves. Not in check.
      fen = "7k/5Q2/7K/8/8/8/8/8 b - - 0 1"
      game = Game.new(fen)

      assert Game.stalemate?(game)
      assert not Game.checkmate?(game)
      assert not Game.in_check?(game)
    end

    test "Insufficient Material - K vs K" do
      fen = "8/8/8/8/8/8/4k3/4K3 w - - 0 1"
      game = Game.new(fen)
      assert Game.draw?(game)
    end

    test "Insufficient Material - K+N vs K" do
      fen = "8/8/8/8/8/5n2/4k3/4K3 w - - 0 1"
      game = Game.new(fen)
      assert Game.draw?(game)
    end

    test "Insufficient Material - K+B vs K" do
      fen = "8/8/8/8/8/5b2/4k3/4K3 w - - 0 1"
      game = Game.new(fen)
      assert Game.draw?(game)
    end

    test "Insufficient Material - K+B vs K+B (same color)" do
      # White Bishop on c4 (light), Black Bishop on f1 (light)
      # Kings on safe squares
      fen = "8/8/8/8/2B5/2k5/8/2K2b2 w - - 0 1"
      game = Game.new(fen)
      assert Game.draw?(game)
    end

    test "Insufficient Material - K+B vs K+B (different color) is NOT draw" do
      # White Bishop on c4 (light), Black Bishop on e1 (dark)
      fen = "8/8/8/8/2B5/2k5/8/2K1b3 w - - 0 1"
      game = Game.new(fen)
      assert not Game.draw?(game)
    end
  end

  describe "50-move rule" do
    test "Draw after 50 moves without pawn move or capture" do
      game = Game.new()
      # Manually set halfmove to 100
      game = %{game | halfmove: 100}
      assert Game.draw?(game)
    end

    test "Not draw at 99 moves" do
      game = Game.new()
      game = %{game | halfmove: 99}
      assert not Game.draw?(game)
    end
  end

  describe "Repetition" do
    test "Three-fold repetition" do
      game = Game.new()

      # 1. Nf3 Nf6
      # 2. Ng1 Ng8 (return to start)

      # Start position (count=1)

      # Move 1
      game = make_moves(game, ["Nf3", "Nf6"])
      # Move 2 (return)
      game = make_moves(game, ["Ng1", "Ng8"])
      # Position repeated (count=2)

      assert not Game.draw?(game)

      # Move 3 (repeat)
      game = make_moves(game, ["Nf3", "Nf6"])
      # Move 4 (return)
      game = make_moves(game, ["Ng1", "Ng8"])
      # Position repeated (count=3)

      assert Game.draw?(game)
    end
  end

  describe "Castling rules" do
    test "Cannot castle through check" do
      # White King e1, Rook h1. Black Knight e3 (attacks f1).
      # f1 is path for kingside castle.
      fen = "r3k2r/8/8/8/8/4n3/8/R3K2R w KQkq - 0 1"
      game = Game.new(fen)

      moves = Echecs.MoveGen.legal_moves(game)
      # Check if O-O is in moves
      kingside = Enum.find(moves, fn m -> m.special == :kingside_castle end)
      refute kingside
    end

    test "Cannot castle out of check" do
      # White King e1 (in check by Nd3), Rook h1.
      # Nd3 attacks e1 (60).
      fen = "r3k2r/8/8/8/8/3n4/8/R3K2R w KQkq - 0 1"
      game = Game.new(fen)

      assert Game.in_check?(game)

      moves = Echecs.MoveGen.legal_moves(game)
      kingside = Enum.find(moves, fn m -> m.special == :kingside_castle end)
      queenside = Enum.find(moves, fn m -> m.special == :queenside_castle end)

      refute kingside
      refute queenside
    end
  end

  describe "En Passant legality" do
    test "Cannot capture en passant if it reveals check" do
      # White King e4, White Pawn e5.
      # Black Rook e8 (pins pawn on e5).
      # Black Pawn d5 (just moved d7-d5).
      # En passant target d6.

      fen = "4r3/8/8/3pP3/4K3/8/8/8 w - d6 0 1"
      game = Game.new(fen)

      moves = Echecs.MoveGen.legal_moves(game)

      # Target move: e5xd6 ep
      ep_move = Enum.find(moves, fn m -> m.special == :en_passant end)
      refute ep_move
    end
  end

  defp make_moves(game, moves) do
    Enum.reduce(moves, game, fn san, g ->
      {:ok, move} = Echecs.PGN.move_from_san(g, san)
      Game.make_move(g, move)
    end)
  end
end
