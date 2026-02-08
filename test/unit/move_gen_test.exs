defmodule Echecs.MoveGenTest do
  use ExUnit.Case
  alias Echecs.{Board, Game, MoveGen}

  test "filters moves that leave king in check" do
    fen = "4r3/8/8/8/8/8/8/4K3 w - - 0 1"
    game = Game.new(fen)

    moves = MoveGen.legal_moves(game)

    destinations = Enum.map(moves, & &1.to)

    assert Board.to_index("d1") in destinations
    assert Board.to_index("f1") in destinations
    refute Board.to_index("e2") in destinations
  end

  test "pinned piece cannot move" do
    fen = "4r3/8/8/8/8/4R3/8/4K3 w - - 0 1"
    game = Game.new(fen)

    moves = MoveGen.legal_moves(game)

    rook_moves = Enum.filter(moves, fn m -> m.from == Board.to_index("e3") end)
    rook_destinations = Enum.map(rook_moves, & &1.to)

    refute Board.to_index("d3") in rook_destinations
    refute Board.to_index("f3") in rook_destinations
    assert Board.to_index("e4") in rook_destinations
    assert Board.to_index("e8") in rook_destinations
  end
end
