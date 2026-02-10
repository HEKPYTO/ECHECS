defmodule Echecs.DBScenarioTest do
  use ExUnit.Case
  alias Echecs.{Game, PGN}

  test "regression: Rd1d2 parsing issue" do
    pgn =
      "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 11. c4 c6 12. cxb5 axb5 13. Nc3 Bb7 14. Bg5 h6 15. Bh4 b4 16. Na4 c5 17. dxc5 dxc5 18. Bxf6 Bxf6 19. Rc1 Be7 20. Qc2 Qc7 21. Red1 Rfd8 22. Qc4 Rf8 23. Qxb4 Bc6 24. Qc4 Qb7 25. Nc3 Nb6 26. Qe2 Bf6 27. Rd6 Rfd8 28. Rcd1 Rxd6 29. Rxd6 Rd8 30. Rxd8+ Bxd8 31. Nxe5 Be8 32. Qd3 Bf6 33. Nc4 Nxc4 34. Qxc4 Bd4 35. Qd5 Qe7 36. Qa8 Kh7 37. Nd5 Qxe4 38. Nf6+ Bxf6 39. Qxe4+ g6 40. Qxe8"

    moves = PGN.parse_moves(pgn)
    game = Game.new()
    result = PGN.replay(game, moves)

    assert match?(%Game{}, result)
  end
end
