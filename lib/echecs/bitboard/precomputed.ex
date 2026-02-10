defmodule Echecs.Bitboard.Precomputed do
  @moduledoc """
  Precomputed tables for Knight, King, and Pawn attacks.
  """
  import Bitwise

  @doc """
  Compile-time generation of attack tables.
  """

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

  def init, do: :ok

  def get_knight_attacks(sq), do: elem(@knight_attacks, sq)
  def get_king_attacks(sq), do: elem(@king_attacks, sq)
  def get_pawn_attacks(sq, :white), do: elem(@white_pawn_attacks, sq)
  def get_pawn_attacks(sq, :black), do: elem(@black_pawn_attacks, sq)
end
