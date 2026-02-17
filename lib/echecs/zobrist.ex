defmodule Echecs.Zobrist do
  @moduledoc """
  Zobrist Hashing implementation for fast state repetition detection.
  Optimized using Tuple-based lookups for O(1) access.
  """
  import Bitwise

  @key :zobrist_keys
  @castling_hashes_key :zobrist_castling_hashes

  def init do
    :rand.seed(:exsss, {1, 2, 3})

    piece_keys =
      for _color <- [:white, :black],
          _type <- [:pawn, :knight, :bishop, :rook, :queen, :king],
          _sq <- 0..63 do
        rand64()
      end

    castling_keys = [rand64(), rand64(), rand64(), rand64()]

    ep_keys = for _f <- 0..7, do: rand64()

    side_key = [rand64()]

    all_keys = piece_keys ++ castling_keys ++ ep_keys ++ side_key
    tuple_keys = List.to_tuple(all_keys)

    :persistent_term.put(@key, tuple_keys)

    # Precompute combined castling hashes for all 16 states
    castling_hashes =
      for state <- 0..15 do
        compute_castling_hash(state, castling_keys)
      end
      |> List.to_tuple()

    :persistent_term.put(@castling_hashes_key, castling_hashes)

    :ok
  end

  defp compute_castling_hash(state, castling_keys) do
    Enum.reduce(0..3, 0, fn bit, acc ->
      if (state &&& 1 <<< bit) != 0 do
        bxor(acc, Enum.at(castling_keys, bit))
      else
        acc
      end
    end)
  end

  defp rand64 do
    :rand.uniform(0xFFFFFFFFFFFFFFFF)
  end

  @compile {:inline, piece_index: 3, ep_index: 1, side_index: 0, color_to_int: 1, type_to_int: 1}

  defp color_to_int(:white), do: 0
  defp color_to_int(:black), do: 1

  defp type_to_int(:pawn), do: 0
  defp type_to_int(:knight), do: 1
  defp type_to_int(:bishop), do: 2
  defp type_to_int(:rook), do: 3
  defp type_to_int(:queen), do: 4
  defp type_to_int(:king), do: 5

  defp piece_index(color, type, sq) do
    color_to_int(color) * 384 + type_to_int(type) * 64 + sq
  end

  defp ep_index(file), do: 772 + file

  defp side_index, do: 780

  def hash(board, turn, castling, en_passant) do
    keys = :persistent_term.get(@key)

    h =
      0..63
      |> Enum.reduce(0, fn sq, acc ->
        case Echecs.Board.at(board, sq) do
          nil ->
            acc

          {c, t} ->
            idx = piece_index(c, t, sq)
            bxor(acc, elem(keys, idx))
        end
      end)

    # XOR castling hash using precomputed table
    castling_hashes = :persistent_term.get(@castling_hashes_key)
    h = bxor(h, elem(castling_hashes, castling))

    h =
      if en_passant do
        file = rem(en_passant, 8)
        bxor(h, elem(keys, ep_index(file)))
      else
        h
      end

    if turn == :black do
      bxor(h, elem(keys, side_index()))
    else
      h
    end
  end

  require Echecs.Move

  def update_hash(
        current_hash,
        move,
        piece,
        target_piece,
        {old_castling, new_castling},
        {old_ep, new_ep},
        turn
      ) do
    keys = :persistent_term.get(@key)

    current_hash
    |> bxor(elem(keys, side_index()))
    |> update_ep(old_ep, new_ep, keys)
    |> update_castling_hash(old_castling, new_castling)
    |> update_pieces(move, piece, target_piece, keys)
    |> update_special_moves(move, piece, turn, keys)
  end

  @doc """
  Incremental Zobrist hash update using unpacked move fields (no struct needed).
  """
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  def update_hash_int(
        current_hash,
        from,
        to,
        promotion,
        special,
        piece,
        target_piece,
        {old_castling, new_castling},
        {old_ep, new_ep},
        turn
      ) do
    keys = :persistent_term.get(@key)

    current_hash
    |> bxor(elem(keys, side_index()))
    |> update_ep(old_ep, new_ep, keys)
    |> update_castling_hash(old_castling, new_castling)
    |> update_pieces_int(from, to, promotion, piece, target_piece, keys)
    |> update_special_moves_int(special, to, piece, turn, keys)
  end

  defp update_ep(h, old_ep, new_ep, keys) do
    h = if old_ep, do: bxor(h, elem(keys, ep_index(rem(old_ep, 8)))), else: h
    if new_ep, do: bxor(h, elem(keys, ep_index(rem(new_ep, 8)))), else: h
  end

  defp update_castling_hash(h, old_castling, new_castling) do
    changed = bxor(old_castling, new_castling)

    if changed != 0 do
      castling_hashes = :persistent_term.get(@castling_hashes_key)
      bxor(h, elem(castling_hashes, changed))
    else
      h
    end
  end

  defp update_pieces(h, move, {c, t}, target_piece, keys) do
    from = move.from
    to = move.to
    promotion = move.promotion

    idx_from = piece_index(c, t, from)
    h = bxor(h, elem(keys, idx_from))

    final_type = promotion || t
    idx_to = piece_index(c, final_type, to)
    h = bxor(h, elem(keys, idx_to))

    if target_piece do
      {tc, tt} = target_piece
      idx_target = piece_index(tc, tt, to)
      bxor(h, elem(keys, idx_target))
    else
      h
    end
  end

  defp update_pieces_int(h, from, to, promotion, {c, t}, target_piece, keys) do
    idx_from = piece_index(c, t, from)
    h = bxor(h, elem(keys, idx_from))

    final_type = promotion || t
    idx_to = piece_index(c, final_type, to)
    h = bxor(h, elem(keys, idx_to))

    if target_piece do
      {tc, tt} = target_piece
      idx_target = piece_index(tc, tt, to)
      bxor(h, elem(keys, idx_target))
    else
      h
    end
  end

  defp update_special_moves(h, move, {c, _}, turn, keys) do
    cond do
      move.special == :en_passant ->
        cap_sq = if turn == :white, do: move.to + 8, else: move.to - 8
        op_c = if c == :white, do: :black, else: :white
        idx = piece_index(op_c, :pawn, cap_sq)
        bxor(h, elem(keys, idx))

      move.special == :kingside_castle ->
        update_castle_rooks(h, c, :kingside, keys)

      move.special == :queenside_castle ->
        update_castle_rooks(h, c, :queenside, keys)

      true ->
        h
    end
  end

  defp update_special_moves_int(h, :en_passant, to, {c, _}, turn, keys) do
    cap_sq = if turn == :white, do: to + 8, else: to - 8
    op_c = if c == :white, do: :black, else: :white
    idx = piece_index(op_c, :pawn, cap_sq)
    bxor(h, elem(keys, idx))
  end

  defp update_special_moves_int(h, :kingside_castle, _to, {c, _}, _turn, keys) do
    update_castle_rooks(h, c, :kingside, keys)
  end

  defp update_special_moves_int(h, :queenside_castle, _to, {c, _}, _turn, keys) do
    update_castle_rooks(h, c, :queenside, keys)
  end

  defp update_special_moves_int(h, _, _to, _piece, _turn, _keys), do: h

  defp update_castle_rooks(h, c, side, keys) do
    {r_from, r_to} =
      case {c, side} do
        {:white, :kingside} -> {63, 61}
        {:white, :queenside} -> {56, 59}
        {:black, :kingside} -> {7, 5}
        {:black, :queenside} -> {0, 3}
      end

    idx_from = piece_index(c, :rook, r_from)
    idx_to = piece_index(c, :rook, r_to)

    h
    |> bxor(elem(keys, idx_from))
    |> bxor(elem(keys, idx_to))
  end
end
