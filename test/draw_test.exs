defmodule Echecs.DrawTest do
  use ExUnit.Case
  alias Echecs.Game

  test "insufficient material: K vs K" do
    game = Game.new("8/8/8/4k3/8/4K3/8/8 w - - 0 1")
    assert Game.draw?(game)
  end

  test "insufficient material: K+N vs K" do
    game = Game.new("8/8/8/4k3/8/4K1N1/8/8 w - - 0 1")
    assert Game.draw?(game)
  end

  test "insufficient material: K vs K+B" do
    game = Game.new("8/8/8/4k3/8/4K1b1/8/8 w - - 0 1")
    assert Game.draw?(game)
  end

  test "insufficient material: K+B vs K+B (same color squares) -> Draw" do
    # White Bishop on e3 (light square: 2+4=6 even).
    # Black Bishop on d6 (dark square: 5+3=8 even? Wait. d6 index 43?
    # Rank 6 (index 2), file d (3). 2+3=5 odd.
    # Let's verify square color logic.

    # Square color(i): rank = div(i,8), file = rem(i,8). rem(r+f, 2).
    # e3: rank 2 (from 0? No, FEN ranks: 8=0..7, 1=56..63).
    # My Board module: rank 8 is row 0.
    # Logic in `square_color` uses 0-63 index.
    # 0 (a8) -> 0,0 -> 0 (light). (Real chess: a8 is light? Yes).
    # 1 (b8) -> 0,1 -> 1 (dark).

    # White B on c1 (58). 7, 2 -> 9 (dark).
    # Black B on f8 (5). 0, 5 -> 5 (dark).
    # Same color squares! Draw.

    game = Game.new("5b2/8/8/3k4/8/3K4/8/2B5 w - - 0 1")
    assert Game.draw?(game)
  end

  test "sufficient material: K+B vs K+B (diff color squares) -> NOT Draw" do
    # White B on c1 (58, dark).
    # Black B on e8 (4, 0,4 -> 4, light).

    game = Game.new("4b3/8/8/3k4/8/3K4/8/2B5 w - - 0 1")
    refute Game.draw?(game)
  end
end
