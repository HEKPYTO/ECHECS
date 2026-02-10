defmodule Echecs.Bitboard.MagicGenerator do
  @moduledoc """
  Generates Magic Numbers and Attack Tables for Sliding Pieces (Rook, Bishop).
  """
  import Bitwise
  alias Echecs.Bitboard.{Helper, Magic}

  @doc """
  Pre-computes magic bitboards and saves them to cache.
  Called from Mix task or startup.
  """
  def init do
    Magic.init()
  end

  @doc """
  Finds magic numbers for all squares for rooks and bishops.
  Returns a structure suitable for saving.
  """
  def find_all_magics do
    rooks =
      0..63
      |> Task.async_stream(fn sq -> find_magic(sq, :rook) end, timeout: :infinity)
      |> Enum.map(fn {:ok, res} -> res end)

    bishops =
      0..63
      |> Task.async_stream(fn sq -> find_magic(sq, :bishop) end, timeout: :infinity)
      |> Enum.map(fn {:ok, res} -> res end)

    %{rook: rooks, bishop: bishops}
  end

  def find_magic(sq, piece_type) do
    mask = if piece_type == :rook, do: mask_rook(sq), else: mask_bishop(sq)
    bits = Helper.pop_count(mask)
    occupancies = generate_occupancies(mask, bits)

    attacks =
      Enum.map(occupancies, fn occ ->
        if piece_type == :rook, do: attack_rook(sq, occ), else: attack_bishop(sq, occ)
      end)

    find_magic_loop(sq, mask, bits, occupancies, attacks)
  end

  defp find_magic_loop(sq, mask, bits, occupancies, attacks) do
    magic =
      :rand.uniform(0xFFFFFFFFFFFFFFFF) &&& :rand.uniform(0xFFFFFFFFFFFFFFFF) &&&
        :rand.uniform(0xFFFFFFFFFFFFFFFF)

    shift = 64 - bits

    table_size = 1 <<< bits
    table = :erlang.make_tuple(table_size, nil)

    case test_magic(magic, shift, mask, occupancies, attacks, table) do
      {:ok, final_table} ->
        build_magic_result(sq, magic, shift, mask, final_table)

      :fail ->
        find_magic_loop(sq, mask, bits, occupancies, attacks)
    end
  end

  defp build_magic_result(sq, magic, shift, mask, final_table) do
    bin_table =
      final_table
      |> Tuple.to_list()
      |> Enum.reduce(<<>>, fn attack, acc ->
        val = if attack == nil, do: 0, else: attack
        acc <> <<val::64-little>>
      end)

    %{sq: sq, magic: magic, shift: shift, mask: mask, table: bin_table}
  end

  defp test_magic(magic, shift, mask, [occ | rest_occ], [att | rest_att], table) do
    masked = occ &&& mask
    prod = masked * magic &&& 0xFFFFFFFFFFFFFFFF
    idx = prod >>> shift

    current = elem(table, idx)

    cond do
      current == nil ->
        new_table = put_elem(table, idx, att)
        test_magic(magic, shift, mask, rest_occ, rest_att, new_table)

      current == att ->
        test_magic(magic, shift, mask, rest_occ, rest_att, table)

      true ->
        :fail
    end
  end

  defp test_magic(_, _, _, [], [], table), do: {:ok, table}

  defp generate_occupancies(mask, bits) do
    count = 1 <<< bits
    Enum.map(0..(count - 1), fn i -> map_bits_to_mask(i, mask) end)
  end

  defp map_bits_to_mask(index, mask) do
    map_recursive(index, mask, 0)
  end

  defp map_recursive(_, 0, result), do: result

  defp map_recursive(index, mask, result) do
    lsb_mask = mask &&& -mask
    lsb_bit = if (index &&& 1) != 0, do: lsb_mask, else: 0
    map_recursive(index >>> 1, mask &&& bnot(lsb_mask), result ||| lsb_bit)
  end

  def mask_rook(sq) do
    r = div(sq, 8)
    f = rem(sq, 8)

    (for(rank <- (r + 1)..6//1, do: {rank, f}) ++
       for(rank <- (r - 1)..1//-1, do: {rank, f}) ++
       for(file <- (f + 1)..6//1, do: {r, file}) ++
       for(file <- (f - 1)..1//-1, do: {r, file}))
    |> coords_to_bb()
  end

  def mask_bishop(sq) do
    r = div(sq, 8)
    f = rem(sq, 8)

    (for(i <- 1..6//1, r + i < 7, f + i < 7, do: {r + i, f + i}) ++
       for(i <- 1..6//1, r + i < 7, f - i > 0, do: {r + i, f - i}) ++
       for(i <- 1..6//1, r - i > 0, f + i < 7, do: {r - i, f + i}) ++
       for(i <- 1..6//1, r - i > 0, f - i > 0, do: {r - i, f - i}))
    |> coords_to_bb()
  end

  def attack_rook(sq, block) do
    r = div(sq, 8)
    f = rem(sq, 8)

    (ray(r, f, 1, 0, block) ++
       ray(r, f, -1, 0, block) ++
       ray(r, f, 0, 1, block) ++
       ray(r, f, 0, -1, block))
    |> coords_to_bb()
  end

  def attack_bishop(sq, block) do
    r = div(sq, 8)
    f = rem(sq, 8)

    (ray(r, f, 1, 1, block) ++
       ray(r, f, 1, -1, block) ++
       ray(r, f, -1, 1, block) ++
       ray(r, f, -1, -1, block))
    |> coords_to_bb()
  end

  defp ray(r, f, dr, df, block) do
    Stream.iterate({r + dr, f + df}, fn {curr_r, curr_f} -> {curr_r + dr, curr_f + df} end)
    |> Enum.reduce_while([], fn {rank, file}, acc ->
      check_ray_step(rank, file, block, acc)
    end)
  end

  defp check_ray_step(rank, file, block, acc) when rank in 0..7 and file in 0..7 do
    sq_bb = 1 <<< (rank * 8 + file)
    hit = (block &&& sq_bb) != 0

    if hit do
      {:halt, [{rank, file} | acc]}
    else
      {:cont, [{rank, file} | acc]}
    end
  end

  defp check_ray_step(_, _, _, acc), do: {:halt, acc}

  defp coords_to_bb(coords) do
    Enum.reduce(coords, 0, fn {r, f}, acc -> acc ||| 1 <<< (r * 8 + f) end)
  end
end
