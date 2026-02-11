defmodule Echecs.Game.GameRulesTest do
  use ExUnit.Case
  alias Echecs.{Game, PGN}

  describe "Draw Conditions" do
    test "Stalemate" do
      # Black king at h8, White Queen at f7, White king at h6.
      # Black to move. King has no moves. Not in check.
      fen = "7k/5Q2/7K/8/8/8/8/8 b - - 0 1"
      game = Game.new(fen)

      assert Game.stalemate?(game)
      assert not Game.checkmate?(game)
      assert not Game.in_check?(game)
    end

    test "Insufficient Material: K vs K" do
      game = Game.new("8/8/8/4k3/8/4K3/8/8 w - - 0 1")
      assert Game.draw?(game)
    end

    test "Insufficient Material: K+N vs K" do
      game = Game.new("8/8/8/4k3/8/4K1N1/8/8 w - - 0 1")
      assert Game.draw?(game)
    end

    test "Insufficient Material: K vs K+B" do
      game = Game.new("8/8/8/4k3/8/4K1b1/8/8 w - - 0 1")
      assert Game.draw?(game)
    end

    test "Insufficient Material: K+B vs K+B (same color squares) -> Draw" do
      # White B on c4 (light), Black B on f1 (light)
      fen = "8/8/8/8/2B5/2k5/8/2K2b2 w - - 0 1"
      game = Game.new(fen)
      assert Game.draw?(game)
    end

    test "Sufficient Material: K+N vs K+N (NOT Draw)" do
      # Knights can mate (helpmate)
      fen = "8/8/8/8/2N5/2n5/8/2K1k3 w - - 0 1"
      game = Game.new(fen)
      assert not Game.draw?(game)
    end

    test "Sufficient Material: K+N vs K+B (NOT Draw)" do
      fen = "8/8/8/8/2B5/2n5/8/2K1k3 w - - 0 1"
      game = Game.new(fen)
      assert not Game.draw?(game)
    end
  end

  describe "Checkmate" do
    test "Back Rank Mate" do
      # White Rook a8, Black King g8. Pawns f7,g7,h7 blocking escape.
      fen = "R5k1/5ppp/8/8/8/8/8/4K3 b - - 0 1"
      game = Game.new(fen)

      assert Game.checkmate?(game)
      assert not Game.stalemate?(game)
    end

    test "Smothered Mate (Knight)" do
      # FEN: Black King h8. Black Rook g8. Black Pawn h7.
      # White Knight f7.
      fen = "6rk/5Npp/8/8/8/8/8/7K b - - 0 1"
      game = Game.new(fen)

      assert Game.checkmate?(game)
    end
  end

  describe "50-move Rule" do
    test "Draw after 50 moves (100 halfmoves) without pawn move or capture" do
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

  defp make_moves(game, moves) do
    Enum.reduce(moves, game, fn san, g ->
      {:ok, move} = PGN.move_from_san(g, san)
      Game.make_move(g, move)
    end)
  end
end
