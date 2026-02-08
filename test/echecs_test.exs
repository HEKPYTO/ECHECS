defmodule EchecsTest do
  use ExUnit.Case
  alias Echecs.{Board, Game, MoveGen}

  test "starts a new game" do
    game = Echecs.new_game()
    assert game.turn == :white
    assert Echecs.status(game) == :active
  end

  test "makes a legal move" do
    game = Echecs.new_game()
    from = Echecs.Board.to_index("e2")
    to = Echecs.Board.to_index("e4")

    assert {:ok, next_game} = Echecs.make_move(game, from, to)

    assert next_game.turn == :black
    assert Echecs.Board.at(next_game.board, to) == {:white, :pawn}
    assert Echecs.Board.at(next_game.board, from) == nil
  end

  test "rejects illegal move" do
    game = Echecs.new_game()
    from = Echecs.Board.to_index("e2")
    to = Echecs.Board.to_index("e5")

    assert {:error, :illegal_move} == Echecs.make_move(game, from, to)
  end

  test "detects checkmate (Fool's Mate)" do
    game = Echecs.new_game()

    {:ok, g1} = Echecs.make_move(game, Board.to_index("f2"), Board.to_index("f3"))
    {:ok, g2} = Echecs.make_move(g1, Board.to_index("e7"), Board.to_index("e5"))
    {:ok, g3} = Echecs.make_move(g2, Board.to_index("g2"), Board.to_index("g4"))
    {:ok, g4} = Echecs.make_move(g3, Board.to_index("d8"), Board.to_index("h4"))

    assert Echecs.status(g4) == :checkmate
    assert Game.checkmate?(g4)
    assert not Game.stalemate?(g4)
  end

  test "detects stalemate" do
    # FEN for a known stalemate position: 7k/5Q2/8/8/8/8/8/K7 b - - 0 1
    # (Black to move, King at h8 is trapped by Queen at f7, King at a1)
    # Wait, King at h8. Queen at f7 covers g8, h7, g7.
    # King at h8 can go to:
    # - g8: covered by Q
    # - g7: covered by Q
    # - h7: covered by Q
    # No other pieces for black. Stalemate.

    fen = "7k/5Q2/8/8/8/8/8/K7 b - - 0 1"
    game = Echecs.new_game(fen)

    assert Echecs.status(game) == :stalemate
    assert Game.stalemate?(game)
    assert not Game.checkmate?(game)
  end

  test "detects en passant" do
    # Setup: White pawn e5, Black pawn d7.
    # 1... d5 (double step)
    # 2. exd6 (en passant)

    fen = "rnbqkbnr/pp1ppppp/8/4P3/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
    game = Echecs.new_game(fen)

    # Black plays d7-d5
    from = Board.to_index("d7")
    to = Board.to_index("d5")
    {:ok, g1} = Echecs.make_move(game, from, to)

    # Verify en_passant target is set
    # d7(12) -> d5(28). Target is d6(20).
    assert g1.en_passant == Board.to_index("d6")

    # White captures en passant: e5-d6
    from_ep = Board.to_index("e5")
    to_ep = Board.to_index("d6")

    # Check if move is legal
    moves = MoveGen.legal_moves(g1)
    ep_move = Enum.find(moves, fn m -> m.from == from_ep and m.to == to_ep end)
    assert ep_move != nil
    assert ep_move.special == :en_passant

    {:ok, g2} = Echecs.make_move(g1, from_ep, to_ep)

    # Check board state:
    # Pawn at d6
    assert Board.at(g2.board, to_ep) == {:white, :pawn}
    # Pawn at d5 (captured) is gone
    assert Board.at(g2.board, to) == nil
  end

  test "pawn promotion" do
    # White pawn at a7, about to promote
    fen = "8/P7/8/8/8/8/k6K/8 w - - 0 1"
    game = Echecs.new_game(fen)

    from = Board.to_index("a7")
    to = Board.to_index("a8")

    # Try to move without promotion specified (should likely fail or default? Logic says we need to specify)
    # My make_move logic in Echecs.ex finds a matching move.
    # MoveGen generates 4 moves for this (Q, R, B, N).
    # If I pass nil promotion, it won't match any of them.

    assert {:error, :illegal_move} == Echecs.make_move(game, from, to, nil)

    # Promote to Queen
    {:ok, g_queen} = Echecs.make_move(game, from, to, :queen)
    assert Board.at(g_queen.board, to) == {:white, :queen}

    # Promote to Knight
    {:ok, g_knight} = Echecs.make_move(game, from, to, :knight)
    assert Board.at(g_knight.board, to) == {:white, :knight}
  end

  test "draw by insufficient material" do
    # K vs K
    fen = "8/8/8/8/8/8/k6K/8 w - - 0 1"
    game = Echecs.new_game(fen)
    assert Echecs.status(game) == :draw

    # K+N vs K
    fen = "8/8/8/8/8/8/k6K/5N2 w - - 0 1"
    game = Echecs.new_game(fen)
    assert Echecs.status(game) == :draw

    # K+B vs K
    fen = "8/8/8/8/8/8/k6K/5B2 w - - 0 1"
    game = Echecs.new_game(fen)
    assert Echecs.status(game) == :draw
  end

  test "3-fold repetition" do
    game = Echecs.new_game()

    # 1. Ng1-f3 Ng8-f6
    # 2. Nf3-g1 Nf6-g8
    # 3. Ng1-f3 Ng8-f6
    # 4. Nf3-g1 Nf6-g8 (Repetition)

    moves = [
      {"g1", "f3"},
      {"g8", "f6"},
      {"f3", "g1"},
      {"f6", "g8"},
      {"g1", "f3"},
      {"g8", "f6"},
      {"f3", "g1"},
      {"f6", "g8"}
    ]

    final_game =
      Enum.reduce(moves, game, fn {f, t}, g ->
        {:ok, next} = Echecs.make_move(g, Board.to_index(f), Board.to_index(t))
        next
      end)

    assert Echecs.status(final_game) == :draw
    assert Game.draw?(final_game)
  end
end
