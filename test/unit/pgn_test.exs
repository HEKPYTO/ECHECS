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
end
