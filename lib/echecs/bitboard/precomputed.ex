defmodule Echecs.Bitboard.Precomputed do
  @moduledoc """
  Precomputed tables for Knight, King, Pawn attacks, and geometric masks (between/line).
  All tables are computed at compile time for zero runtime cost.
  """
  import Bitwise
  alias Echecs.Bitboard.MagicGenerator

  @compile {:inline,
            get_knight_attacks: 1,
            get_king_attacks: 1,
            get_pawn_attacks: 2,
            get_between: 2,
            get_line: 2}

  # ── Knight attacks ──

  @knight_attacks (for sq <- 0..63 do
                     rank = div(sq, 8)
                     file = rem(sq, 8)

                     offsets = [
                       {-2, -1},
                       {-2, 1},
                       {-1, -2},
                       {-1, 2},
                       {1, -2},
                       {1, 2},
                       {2, -1},
                       {2, 1}
                     ]

                     Enum.reduce(offsets, 0, fn {dr, df}, acc ->
                       r = rank + dr
                       f = file + df
                       if r in 0..7 and f in 0..7, do: acc ||| 1 <<< (r * 8 + f), else: acc
                     end)
                   end)
                  |> List.to_tuple()

  # ── King attacks ──

  @king_attacks (for sq <- 0..63 do
                   rank = div(sq, 8)
                   file = rem(sq, 8)

                   offsets = for dr <- -1..1, df <- -1..1, {dr, df} != {0, 0}, do: {dr, df}

                   Enum.reduce(offsets, 0, fn {dr, df}, acc ->
                     r = rank + dr
                     f = file + df
                     if r in 0..7 and f in 0..7, do: acc ||| 1 <<< (r * 8 + f), else: acc
                   end)
                 end)
                |> List.to_tuple()

  # ── Pawn attacks ──

  @white_pawn_attacks (for sq <- 0..63 do
                         rank = div(sq, 8)
                         file = rem(sq, 8)

                         Enum.reduce([{-1, -1}, {-1, 1}], 0, fn {dr, df}, acc ->
                           r = rank + dr
                           f = file + df
                           if r in 0..7 and f in 0..7, do: acc ||| 1 <<< (r * 8 + f), else: acc
                         end)
                       end)
                      |> List.to_tuple()

  @black_pawn_attacks (for sq <- 0..63 do
                         rank = div(sq, 8)
                         file = rem(sq, 8)

                         Enum.reduce([{1, -1}, {1, 1}], 0, fn {dr, df}, acc ->
                           r = rank + dr
                           f = file + df
                           if r in 0..7 and f in 0..7, do: acc ||| 1 <<< (r * 8 + f), else: acc
                         end)
                       end)
                      |> List.to_tuple()

  # ── Between masks (64x64) ──
  # between(sq1, sq2) = squares strictly between sq1 and sq2 on same line, 0 otherwise

  @between_masks (for sq1 <- 0..63 do
                    for sq2 <- 0..63 do
                      if sq1 == sq2 do
                        0
                      else
                        r1 = div(sq1, 8)
                        f1 = rem(sq1, 8)
                        r2 = div(sq2, 8)
                        f2 = rem(sq2, 8)

                        cond do
                          r1 == r2 or f1 == f2 ->
                            a1 = MagicGenerator.attack_rook(sq1, 1 <<< sq2)
                            a2 = MagicGenerator.attack_rook(sq2, 1 <<< sq1)
                            a1 &&& a2

                          abs(r1 - r2) == abs(f1 - f2) ->
                            a1 = MagicGenerator.attack_bishop(sq1, 1 <<< sq2)
                            a2 = MagicGenerator.attack_bishop(sq2, 1 <<< sq1)
                            a1 &&& a2

                          true ->
                            0
                        end
                      end
                    end
                    |> List.to_tuple()
                  end)
                 |> List.to_tuple()

  # ── Line masks (64x64) ──
  # line(sq1, sq2) = full line through both squares (rank, file, or diagonal), 0 if not aligned

  @line_masks (for sq1 <- 0..63 do
                 for sq2 <- 0..63 do
                   if sq1 == sq2 do
                     0
                   else
                     r1 = div(sq1, 8)
                     f1 = rem(sq1, 8)
                     r2 = div(sq2, 8)
                     f2 = rem(sq2, 8)

                     cond do
                       r1 == r2 or f1 == f2 ->
                         a1 = MagicGenerator.attack_rook(sq1, 0)
                         a2 = MagicGenerator.attack_rook(sq2, 0)
                         (a1 &&& a2) ||| 1 <<< sq1 ||| 1 <<< sq2

                       abs(r1 - r2) == abs(f1 - f2) ->
                         a1 = MagicGenerator.attack_bishop(sq1, 0)
                         a2 = MagicGenerator.attack_bishop(sq2, 0)
                         (a1 &&& a2) ||| 1 <<< sq1 ||| 1 <<< sq2

                       true ->
                         0
                     end
                   end
                 end
                 |> List.to_tuple()
               end)
              |> List.to_tuple()

  def init, do: :ok

  def get_knight_attacks(sq), do: elem(@knight_attacks, sq)
  def get_king_attacks(sq), do: elem(@king_attacks, sq)
  def get_pawn_attacks(sq, :white), do: elem(@white_pawn_attacks, sq)
  def get_pawn_attacks(sq, :black), do: elem(@black_pawn_attacks, sq)
  def get_between(sq1, sq2), do: elem(elem(@between_masks, sq1), sq2)
  def get_line(sq1, sq2), do: elem(elem(@line_masks, sq1), sq2)
end
