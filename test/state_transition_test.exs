defmodule Echecs.StateTransitionTest do
  use ExUnit.Case

  alias Echecs.{Game, Move, MoveGen, Perft, PGN, Zobrist}

  test "new game seeds hash and history consistently" do
    game = Game.new()

    assert game.zobrist_hash ==
             Zobrist.hash(game.board, game.turn, game.castling, game.en_passant)

    assert game.history == [game.zobrist_hash]
  end

  test "incremental hash matches recomputation across a deterministic line" do
    line = PGN.parse_moves("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7")

    final_game =
      Enum.reduce(line, Game.new(), fn san, game ->
        {:ok, move} = PGN.move_from_san(game, san)
        next_game = Game.make_move(game, move)

        assert next_game.zobrist_hash ==
                 Zobrist.hash(
                   next_game.board,
                   next_game.turn,
                   next_game.castling,
                   next_game.en_passant
                 )

        assert hd(next_game.history) == next_game.zobrist_hash
        assert Enum.all?(next_game.history, &is_integer/1)

        next_game
      end)

    assert length(final_game.history) == length(line) + 1
  end

  test "hash distinguishes castling and en passant state" do
    castling_full = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    castling_none = Game.new("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")
    en_passant = Game.new("8/8/8/8/3pP3/8/8/8 b - e3 0 1")
    no_en_passant = Game.new("8/8/8/8/3pP3/8/8/8 b - - 0 1")

    refute castling_full.zobrist_hash == castling_none.zobrist_hash
    refute en_passant.zobrist_hash == no_en_passant.zobrist_hash
  end

  test "make_move variants stay equivalent on shared state" do
    game = Game.new("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")

    game
    |> MoveGen.legal_moves_int()
    |> Enum.take(12)
    |> Enum.each(fn packed_move ->
      struct_move = Move.to_struct(packed_move)
      move_game = Game.make_move(game, struct_move)
      int_game = Game.make_move_int(game, packed_move)
      perft_game = Game.make_move_perft(game, packed_move)

      assert_same_game_fields(move_game, int_game)
      assert_same_game_fields(move_game, perft_game)

      assert int_game.zobrist_hash ==
               Zobrist.hash(int_game.board, int_game.turn, int_game.castling, int_game.en_passant)
    end)
  end

  test "optimized perft matches recursive reference" do
    positions = [
      {Game.new(), 4},
      {Game.new("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"), 3},
      {Game.new("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"), 3}
    ]

    Enum.each(positions, fn {game, depth} ->
      assert Perft.perft(game, depth) == recursive_perft(game, depth)
    end)
  end

  test "transition invariants hold on deterministic legal prefixes" do
    games = [
      Game.new(),
      Game.new("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
    ]

    Enum.each(games, &assert_prefix_invariants(&1, 2, 4))
  end

  defp assert_prefix_invariants(_game, 0, _branch_limit), do: :ok

  defp assert_prefix_invariants(game, depth, branch_limit) do
    game
    |> MoveGen.legal_moves_int()
    |> Enum.take(branch_limit)
    |> Enum.each(fn packed_move ->
      struct_move = Move.to_struct(packed_move)
      next_game = Game.make_move_int(game, packed_move)
      next_struct_game = Game.make_move(game, struct_move)

      assert_same_game_fields(next_game, next_struct_game)

      assert next_game.zobrist_hash ==
               Zobrist.hash(
                 next_game.board,
                 next_game.turn,
                 next_game.castling,
                 next_game.en_passant
               )

      assert_prefix_invariants(next_game, depth - 1, branch_limit)
    end)
  end

  defp assert_same_game_fields(left, right) do
    assert left.board == right.board
    assert left.turn == right.turn
    assert left.castling == right.castling
    assert left.en_passant == right.en_passant
    assert left.halfmove == right.halfmove
    assert left.fullmove == right.fullmove
    assert left.king_pos == right.king_pos
    assert left.zobrist_hash == right.zobrist_hash
  end

  defp recursive_perft(_game, 0), do: 1

  defp recursive_perft(game, depth) do
    game
    |> MoveGen.legal_moves()
    |> Enum.reduce(0, fn move, count ->
      count + recursive_perft(Game.make_move(game, move), depth - 1)
    end)
  end
end
