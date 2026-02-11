defmodule Echecs.Engine.PerftTest do
  use ExUnit.Case
  alias Echecs.{Game, MoveGen}

  @moduledoc """
  Perft (Performance Test) suite.
  Verifies the move generator by counting leaf nodes at fixed depths.
  This is the gold standard for move generation correctness.
  """

  # Perft function
  def perft(game, depth) do
    if depth == 0 do
      1
    else
      moves = MoveGen.legal_moves(game)

      Enum.reduce(moves, 0, fn move, count ->
        next_game = Game.make_move(game, move)
        count + perft(next_game, depth - 1)
      end)
    end
  end

  describe "Perft Positions" do
    # Allow time for calculation
    @tag timeout: 60_000
    test "Position 1: Start Position" do
      game = Game.new()

      # Depth 1: 20
      assert perft(game, 1) == 20
      # Depth 2: 400
      assert perft(game, 2) == 400
      # Depth 3: 8,902
      assert perft(game, 3) == 8_902
      # Depth 4: 197,281
      assert perft(game, 4) == 197_281
    end

    @tag timeout: 60_000
    test "Position 2: Kiwipete" do
      # Tricky position: pins, en passant, checks
      fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
      game = Game.new(fen)

      # Depth 1: 48
      assert perft(game, 1) == 48
      # Depth 2: 2039
      assert perft(game, 2) == 2_039
      # Depth 3: 97,862
      assert perft(game, 3) == 97_862
    end

    @tag timeout: 60_000
    test "Position 3: Rook Check/Castling" do
      fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
      game = Game.new(fen)

      # Depth 1: 14
      assert perft(game, 1) == 14
      # Depth 2: 191
      assert perft(game, 2) == 191
      # Depth 3: 2812
      assert perft(game, 3) == 2_812
    end

    @tag timeout: 60_000
    test "Position 4: Promotions" do
      fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
      game = Game.new(fen)

      # Depth 1: 6
      assert perft(game, 1) == 6
      # Depth 2: 264
      assert perft(game, 2) == 264
      # Depth 3: 9467
      assert perft(game, 3) == 9_467
    end

    @tag timeout: 60_000
    test "Position 5: Checkmate/Stalemate" do
      fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
      game = Game.new(fen)

      # Depth 1: 44
      assert perft(game, 1) == 44
      # Depth 2: 1486
      assert perft(game, 2) == 1_486
      # Depth 3: 62,379
      assert perft(game, 3) == 62_379
    end

    @tag timeout: 60_000
    test "Position 6: Complex Middle Game" do
      fen = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"
      game = Game.new(fen)

      # Depth 1: 46
      assert perft(game, 1) == 46
      # Depth 2: 2079
      assert perft(game, 2) == 2_079
      # Depth 3: 89,890
      assert perft(game, 3) == 89_890
    end
  end
end
