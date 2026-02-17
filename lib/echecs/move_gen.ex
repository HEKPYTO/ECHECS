defmodule Echecs.MoveGen do
  @moduledoc """
  Legal-only move generation using check_mask + pin_mask technique.
  Generates only legal moves directly without pseudo-legal filtering.
  """

  import Bitwise
  alias Echecs.Bitboard.{Constants, Helper, Magic, Precomputed}
  alias Echecs.{Board, Game, Move, Piece}

  require Echecs.Move
  require Echecs.Bitboard.Constants

  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  @mask64 Constants.mask64()

  @compile {:inline,
            get_occupancies: 2,
            get_king_bb: 2,
            get_pawns: 2,
            get_knights: 2,
            get_bishops: 2,
            get_rooks: 2,
            get_queens: 2,
            get_slider_bb: 3,
            get_slider_attacks: 3,
            shift_pawn: 2,
            ensure_tuple: 1}

  # ── Public API ──

  @doc """
  Returns a list of all legal moves for the current player.
  """
  def legal_moves(%Game{} = game) do
    legal_moves_int(game)
    |> Enum.map(&Move.to_struct/1)
  end

  @doc """
  Returns all legal moves as packed integers (no struct allocation).
  """
  def legal_moves_int(%Game{} = game) do
    board = ensure_tuple(game.board)
    turn = game.turn
    opponent = Piece.opponent(turn)

    {us_bb, them_bb, all_bb} = get_occupancies(board, turn)
    king_bb = get_king_bb(board, turn)
    king_sq = Helper.lsb(king_bb)

    # Compute checkers
    checkers = compute_checkers(board, king_sq, opponent, all_bb)
    num_checkers = Helper.pop_count(checkers)

    # Compute danger squares for king (with king removed from occupancy)
    occ_no_king = bxor(all_bb, king_bb)
    danger = compute_danger(board, opponent, occ_no_king)

    # King moves (always generated)
    king_targets =
      Precomputed.get_king_attacks(king_sq) &&& bnot(us_bb) &&& bnot(danger) &&& @mask64

    moves = bitboard_to_moves_from(king_targets, king_sq, [])

    if num_checkers >= 2 do
      # Double check: only king can move
      moves
    else
      # Compute check_mask
      check_mask = compute_check_mask(checkers, king_sq)

      # Compute pins
      {pinned, pin_rays} = compute_pins(board, king_sq, turn, us_bb, them_bb)

      # Generate non-king moves restricted by check_mask and pins
      moves
      |> gen_pawn_moves(
        board,
        turn,
        us_bb,
        them_bb,
        all_bb,
        game.en_passant,
        check_mask,
        pinned,
        pin_rays,
        king_sq
      )
      |> gen_knight_moves(board, turn, us_bb, check_mask, pinned)
      |> gen_slider_moves(:bishop, board, turn, us_bb, all_bb, check_mask, pinned, pin_rays)
      |> gen_slider_moves(:rook, board, turn, us_bb, all_bb, check_mask, pinned, pin_rays)
      |> gen_slider_moves(:queen, board, turn, us_bb, all_bb, check_mask, pinned, pin_rays)
      |> gen_castling(king_sq, turn, game, all_bb, danger, num_checkers)
    end
  end

  @doc """
  Returns true if there is at least one legal move. Short-circuits on first found.
  """
  def has_legal_move?(%Game{} = game) do
    board = ensure_tuple(game.board)
    turn = game.turn
    opponent = Piece.opponent(turn)

    {us_bb, them_bb, all_bb} = get_occupancies(board, turn)
    king_bb = get_king_bb(board, turn)
    king_sq = Helper.lsb(king_bb)

    checkers = compute_checkers(board, king_sq, opponent, all_bb)
    num_checkers = Helper.pop_count(checkers)

    occ_no_king = bxor(all_bb, king_bb)
    danger = compute_danger(board, opponent, occ_no_king)

    king_targets =
      Precomputed.get_king_attacks(king_sq) &&& bnot(us_bb) &&& bnot(danger) &&& @mask64

    if king_targets != 0 do
      true
    else
      if num_checkers >= 2 do
        false
      else
        check_mask = compute_check_mask(checkers, king_sq)
        {pinned, pin_rays} = compute_pins(board, king_sq, turn, us_bb, them_bb)

        has_non_king_move?(
          board,
          turn,
          us_bb,
          them_bb,
          all_bb,
          game.en_passant,
          check_mask,
          pinned,
          pin_rays,
          king_sq,
          game,
          danger,
          num_checkers
        )
      end
    end
  end

  @doc """
  Returns a list of pseudo-legal moves (ignoring check).
  """
  def pseudo_legal_moves(game) do
    generate_pseudo_moves_int(game)
    |> Enum.map(&Move.to_struct/1)
  end

  @doc """
  Generates only capturing moves (for Quiescence Search).
  """
  def captures(game) do
    generate_captures_int(game)
    |> Enum.map(&Move.to_struct/1)
  end

  @doc """
  Generates only non-capturing (quiet) moves.
  """
  def quiets(game) do
    generate_quiets_int(game)
    |> Enum.map(&Move.to_struct/1)
  end

  def generate_moves_targeting(game, target_sq, piece_type) do
    board = ensure_tuple(game.board)
    turn = game.turn
    all_bb = Board.all_occ(board)

    piece_bb = get_piece_bb(board, turn, piece_type)

    candidates_bb =
      case piece_type do
        :knight ->
          Precomputed.get_knight_attacks(target_sq) &&& piece_bb

        :bishop ->
          Magic.get_bishop_attacks(target_sq, all_bb) &&& piece_bb

        :rook ->
          Magic.get_rook_attacks(target_sq, all_bb) &&& piece_bb

        :queen ->
          (Magic.get_bishop_attacks(target_sq, all_bb) |||
             Magic.get_rook_attacks(target_sq, all_bb)) &&& piece_bb

        :king ->
          Precomputed.get_king_attacks(target_sq) &&& piece_bb

        :pawn ->
          reverse_pawn_moves(game, target_sq, turn)
      end

    if is_integer(candidates_bb) do
      bitboard_to_moves_to(candidates_bb, target_sq, [])
      |> Enum.map(&Move.to_struct/1)
    else
      candidates_bb |> Enum.map(&Move.to_struct/1)
    end
  end

  # ── Check/Pin/Danger computation ──

  defp compute_checkers(board, king_sq, attacker_color, all_bb) do
    # Which enemy pieces attack the king square?
    defender_color = Piece.opponent(attacker_color)

    pawn_attackers =
      Precomputed.get_pawn_attacks(king_sq, defender_color) &&& get_pawns(board, attacker_color)

    knight_attackers =
      Precomputed.get_knight_attacks(king_sq) &&& get_knights(board, attacker_color)

    bishop_attacks = Magic.get_bishop_attacks(king_sq, all_bb)
    rook_attacks = Magic.get_rook_attacks(king_sq, all_bb)
    bq = get_bishops(board, attacker_color) ||| get_queens(board, attacker_color)
    rq = get_rooks(board, attacker_color) ||| get_queens(board, attacker_color)

    pawn_attackers ||| knight_attackers ||| (bishop_attacks &&& bq) ||| (rook_attacks &&& rq)
  end

  defp compute_check_mask(0, _king_sq), do: @mask64

  defp compute_check_mask(checkers, king_sq) do
    checker_sq = Helper.lsb(checkers)
    Precomputed.get_between(king_sq, checker_sq) ||| 1 <<< checker_sq
  end

  defp compute_danger(board, attacker_color, occ_no_king) do
    # All squares attacked by attacker_color, with our king removed from occupancy
    danger = 0

    # Pawn attacks (bulk)
    enemy_pawns = get_pawns(board, attacker_color)

    danger =
      if attacker_color == :white do
        # White pawns attack "upward" (lower indices) = shift >>> 7 and >>> 9
        ne = (enemy_pawns &&& bnot(Constants.file_h()) &&& @mask64) >>> 7
        nw = (enemy_pawns &&& bnot(Constants.file_a()) &&& @mask64) >>> 9
        danger ||| ne ||| nw
      else
        # Black pawns attack "downward" (higher indices) = shift <<< 7 and <<< 9
        se = (enemy_pawns &&& bnot(Constants.file_a()) &&& @mask64) <<< 7
        sw = (enemy_pawns &&& bnot(Constants.file_h()) &&& @mask64) <<< 9
        danger ||| se ||| sw
      end

    # Knight attacks
    danger = or_knight_attacks(danger, get_knights(board, attacker_color))

    # Bishop + Queen diagonal attacks (using occ_no_king)
    enemy_bq = get_bishops(board, attacker_color) ||| get_queens(board, attacker_color)
    danger = or_bishop_attacks(danger, enemy_bq, occ_no_king)

    # Rook + Queen HV attacks (using occ_no_king)
    enemy_rq = get_rooks(board, attacker_color) ||| get_queens(board, attacker_color)
    danger = or_rook_attacks(danger, enemy_rq, occ_no_king)

    # Enemy king attacks
    enemy_king_sq = Helper.lsb(get_king_bb(board, attacker_color))
    if enemy_king_sq, do: danger ||| Precomputed.get_king_attacks(enemy_king_sq), else: danger
  end

  defp or_knight_attacks(danger, 0), do: danger

  defp or_knight_attacks(danger, bb) do
    sq = Helper.lsb(bb)
    or_knight_attacks(danger ||| Precomputed.get_knight_attacks(sq), bb &&& bb - 1)
  end

  defp or_bishop_attacks(danger, 0, _occ), do: danger

  defp or_bishop_attacks(danger, bb, occ) do
    sq = Helper.lsb(bb)
    or_bishop_attacks(danger ||| Magic.get_bishop_attacks(sq, occ), bb &&& bb - 1, occ)
  end

  defp or_rook_attacks(danger, 0, _occ), do: danger

  defp or_rook_attacks(danger, bb, occ) do
    sq = Helper.lsb(bb)
    or_rook_attacks(danger ||| Magic.get_rook_attacks(sq, occ), bb &&& bb - 1, occ)
  end

  # Precomputed all-ones pin mask for the common case of no pins
  @no_pin_mask :erlang.make_tuple(64, Constants.mask64())

  # Returns {pinned_bb, pin_mask_tuple} where pin_mask_tuple is a 64-element tuple.
  # Unpinned squares have @mask64 (all-ones), pinned squares have their ray mask.
  # This enables branchless pin checking: targets &&& elem(pin_mask, from)
  defp compute_pins(board, king_sq, turn, us_bb, them_bb) do
    opponent = Piece.opponent(turn)

    # Potential HV pinners: enemy R/Q that can see king through our pieces
    enemy_rq = get_rooks(board, opponent) ||| get_queens(board, opponent)
    rook_xray = Magic.get_rook_attacks(king_sq, them_bb)
    hv_pinners = rook_xray &&& enemy_rq

    # Potential diagonal pinners: enemy B/Q
    enemy_bq = get_bishops(board, opponent) ||| get_queens(board, opponent)
    bishop_xray = Magic.get_bishop_attacks(king_sq, them_bb)
    diag_pinners = bishop_xray &&& enemy_bq

    # Short-circuit: if no potential pinners, skip tuple allocation
    if (hv_pinners ||| diag_pinners) == 0 do
      {0, @no_pin_mask}
    else
      {pinned, pin_mask} =
        process_pinners(hv_pinners, king_sq, us_bb, 0, @no_pin_mask)

      process_pinners(diag_pinners, king_sq, us_bb, pinned, pin_mask)
    end
  end

  defp process_pinners(0, _king_sq, _us_bb, pinned, pin_mask), do: {pinned, pin_mask}

  defp process_pinners(pinners, king_sq, us_bb, pinned, pin_mask) do
    pinner_sq = Helper.lsb(pinners)
    between = Precomputed.get_between(king_sq, pinner_sq)
    our_between = between &&& us_bb

    {pinned, pin_mask} =
      if Helper.pop_count(our_between) == 1 do
        pinned_sq = Helper.lsb(our_between)
        ray = between ||| 1 <<< pinner_sq
        {pinned ||| our_between, put_elem(pin_mask, pinned_sq, ray)}
      else
        {pinned, pin_mask}
      end

    process_pinners(pinners &&& pinners - 1, king_sq, us_bb, pinned, pin_mask)
  end

  # ── Non-king move generation (with check_mask + pin restrictions) ──

  # Knights: pinned knights can NEVER move
  defp gen_knight_moves(acc, board, turn, us_bb, check_mask, pinned) do
    knights = get_knights(board, turn) &&& bnot(pinned) &&& @mask64
    do_gen_knights(knights, acc, us_bb, check_mask)
  end

  defp do_gen_knights(0, acc, _us_bb, _check_mask), do: acc

  defp do_gen_knights(knights, acc, us_bb, check_mask) do
    from = Helper.lsb(knights)
    targets = Precomputed.get_knight_attacks(from) &&& bnot(us_bb) &&& check_mask &&& @mask64
    acc = bitboard_to_moves_from(targets, from, acc)
    do_gen_knights(knights &&& knights - 1, acc, us_bb, check_mask)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp gen_slider_moves(acc, type, board, turn, us_bb, all_bb, check_mask, _pinned, pin_mask) do
    bb = get_slider_bb(board, turn, type)
    do_gen_sliders(bb, acc, type, us_bb, all_bb, check_mask, pin_mask)
  end

  defp do_gen_sliders(0, acc, _type, _us_bb, _all_bb, _check_mask, _pin_mask), do: acc

  defp do_gen_sliders(bb, acc, type, us_bb, all_bb, check_mask, pin_mask) do
    from = Helper.lsb(bb)
    attacks = get_slider_attacks(type, from, all_bb)
    # Branchless pin mask: unpinned squares have @mask64 (no-op AND), pinned have ray
    targets = attacks &&& bnot(us_bb) &&& check_mask &&& elem(pin_mask, from) &&& @mask64

    acc = bitboard_to_moves_from(targets, from, acc)
    do_gen_sliders(bb &&& bb - 1, acc, type, us_bb, all_bb, check_mask, pin_mask)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp gen_pawn_moves(
         acc,
         board,
         turn,
         us_bb,
         them_bb,
         all_bb,
         ep_sq,
         check_mask,
         pinned,
         pin_mask,
         king_sq
       ) do
    pawns = get_pawns(board, turn)
    {push_dir, promo_rank, double_rank_mask, ep_cap_offset} = pawn_params(turn)

    # ── Single pushes ──
    single_pushes = shift_pawn(pawns, push_dir) &&& bnot(all_bb) &&& @mask64

    acc =
      extract_legal_pawn_pushes(
        single_pushes,
        -push_dir,
        turn,
        promo_rank,
        check_mask,
        pin_mask,
        acc
      )

    # ── Double pushes ──
    double_pushes =
      shift_pawn(single_pushes &&& double_rank_mask, push_dir) &&& bnot(all_bb) &&& @mask64

    acc =
      extract_legal_pawn_double_pushes(double_pushes, -push_dir * 2, check_mask, pin_mask, acc)

    # ── Captures ──
    acc = gen_pawn_captures(pawns, turn, them_bb, promo_rank, check_mask, pin_mask, acc)

    # ── En passant ──
    if ep_sq do
      gen_en_passant(
        pawns,
        turn,
        ep_sq,
        ep_cap_offset,
        king_sq,
        board,
        us_bb,
        them_bb,
        all_bb,
        check_mask,
        pinned,
        pin_mask,
        acc
      )
    else
      acc
    end
  end

  defp pawn_params(:white) do
    # push_dir: negative = towards lower indices = "north"
    {-8, 0, 0x0000FF0000000000, 8}
  end

  defp pawn_params(:black) do
    {8, 7, 0x0000000000FF0000, -8}
  end

  defp shift_pawn(bb, -8), do: bb >>> 8
  defp shift_pawn(bb, 8), do: bb <<< 8

  defp extract_legal_pawn_pushes(0, _offset, _turn, _promo_rank, _cm, _pin_mask, acc), do: acc

  defp extract_legal_pawn_pushes(pushes, offset, turn, promo_rank, check_mask, pin_mask, acc) do
    to = Helper.lsb(pushes)
    from = to + offset
    to_bit = 1 <<< to

    acc =
      if (to_bit &&& check_mask &&& elem(pin_mask, from)) != 0 do
        add_pawn_move(acc, from, to, turn, promo_rank)
      else
        acc
      end

    extract_legal_pawn_pushes(
      pushes &&& pushes - 1,
      offset,
      turn,
      promo_rank,
      check_mask,
      pin_mask,
      acc
    )
  end

  defp extract_legal_pawn_double_pushes(0, _offset, _cm, _pin_mask, acc), do: acc

  defp extract_legal_pawn_double_pushes(pushes, offset, check_mask, pin_mask, acc) do
    to = Helper.lsb(pushes)
    from = to + offset
    to_bit = 1 <<< to

    acc =
      if (to_bit &&& check_mask &&& elem(pin_mask, from)) != 0 do
        [Move.pack(from, to, nil, nil) | acc]
      else
        acc
      end

    extract_legal_pawn_double_pushes(pushes &&& pushes - 1, offset, check_mask, pin_mask, acc)
  end

  defp gen_pawn_captures(0, _turn, _them_bb, _promo_rank, _cm, _pin_mask, acc), do: acc

  defp gen_pawn_captures(pawns, turn, them_bb, promo_rank, check_mask, pin_mask, acc) do
    from = Helper.lsb(pawns)
    attacks = Precomputed.get_pawn_attacks(from, turn)
    # Apply pin mask to captures: only allow captures along pin ray
    captures = attacks &&& them_bb &&& check_mask &&& elem(pin_mask, from)

    acc = do_pawn_captures(captures, from, turn, promo_rank, acc)

    gen_pawn_captures(pawns &&& pawns - 1, turn, them_bb, promo_rank, check_mask, pin_mask, acc)
  end

  defp do_pawn_captures(0, _from, _turn, _promo_rank, acc), do: acc

  defp do_pawn_captures(captures, from, turn, promo_rank, acc) do
    to = Helper.lsb(captures)
    acc = add_pawn_move(acc, from, to, turn, promo_rank)
    do_pawn_captures(captures &&& captures - 1, from, turn, promo_rank, acc)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp gen_en_passant(
         pawns,
         turn,
         ep_sq,
         ep_cap_offset,
         king_sq,
         board,
         _us_bb,
         _them_bb,
         all_bb,
         check_mask,
         _pinned,
         pin_mask,
         acc
       ) do
    # Find our pawns that can capture en passant
    ep_attackers = Precomputed.get_pawn_attacks(ep_sq, Piece.opponent(turn)) &&& pawns

    do_gen_ep(
      ep_attackers,
      ep_sq,
      ep_cap_offset,
      king_sq,
      turn,
      board,
      all_bb,
      check_mask,
      pin_mask,
      acc
    )
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp do_gen_ep(0, _ep_sq, _offset, _king_sq, _turn, _board, _all, _cm, _pm, acc), do: acc

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp do_gen_ep(
         attackers,
         ep_sq,
         ep_cap_offset,
         king_sq,
         turn,
         board,
         all_bb,
         check_mask,
         pin_mask,
         acc
       ) do
    from = Helper.lsb(attackers)
    cap_sq = ep_sq + ep_cap_offset

    # The captured pawn must be on check_mask OR the ep_sq itself must be on check_mask
    ep_valid =
      (1 <<< ep_sq &&& check_mask) != 0 or
        (1 <<< cap_sq &&& check_mask) != 0

    acc =
      if ep_valid do
        # Check pin restriction using pin_mask tuple
        pin_ok = (1 <<< ep_sq &&& elem(pin_mask, from)) != 0

        if pin_ok do
          # Check for horizontal discovered check (the rare EP edge case)
          occ_after = bxor(all_bb, 1 <<< from ||| 1 <<< cap_sq) ||| 1 <<< ep_sq
          opponent = Piece.opponent(turn)
          enemy_rq = get_rooks(board, opponent) ||| get_queens(board, opponent)
          rook_attacks = Magic.get_rook_attacks(king_sq, occ_after)

          if (rook_attacks &&& enemy_rq) == 0 do
            [Move.pack(from, ep_sq, nil, :en_passant) | acc]
          else
            acc
          end
        else
          acc
        end
      else
        acc
      end

    do_gen_ep(
      attackers &&& attackers - 1,
      ep_sq,
      ep_cap_offset,
      king_sq,
      turn,
      board,
      all_bb,
      check_mask,
      pin_mask,
      acc
    )
  end

  defp add_pawn_move(acc, from, to, _turn, promo_rank) do
    rank = div(to, 8)

    if rank == promo_rank do
      add_promotions(acc, from, to)
    else
      [Move.pack(from, to, nil, nil) | acc]
    end
  end

  defp add_promotions(acc, from, to) do
    [
      Move.pack(from, to, :queen, nil),
      Move.pack(from, to, :rook, nil),
      Move.pack(from, to, :bishop, nil),
      Move.pack(from, to, :knight, nil) | acc
    ]
  end

  # ── Castling ──

  defp gen_castling(acc, _king_sq, _turn, _game, _all_bb, _danger, num_checkers)
       when num_checkers > 0,
       do: acc

  defp gen_castling(acc, king_sq, turn, game, all_bb, danger, 0) do
    castling = game.castling

    acc
    |> try_castle(:kingside, castling, king_sq, turn, all_bb, danger)
    |> try_castle(:queenside, castling, king_sq, turn, all_bb, danger)
  end

  defp try_castle(acc, side, castling, king_sq, turn, all_bb, danger) do
    if Game.has_right?(castling, turn, side) do
      {path_mask, check_mask, target, special} = castle_params(side, turn)

      # Path must be clear and traversal squares not attacked (single bitwise op each)
      if (all_bb &&& path_mask) == 0 and (danger &&& check_mask) == 0 do
        [Move.pack(king_sq, target, nil, special) | acc]
      else
        acc
      end
    else
      acc
    end
  end

  # {path_mask, check_mask, target_sq, special}
  # check_mask = bitboard of squares king traverses (must not be attacked)
  defp castle_params(:kingside, :white),
    do: {Constants.white_ks_path(), 0x6000000000000000, 62, :kingside_castle}

  defp castle_params(:queenside, :white),
    do: {Constants.white_qs_path(), 0x0C00000000000000, 58, :queenside_castle}

  defp castle_params(:kingside, :black),
    do: {Constants.black_ks_path(), 0x0000000000000060, 6, :kingside_castle}

  defp castle_params(:queenside, :black),
    do: {Constants.black_qs_path(), 0x000000000000000C, 2, :queenside_castle}

  # ── has_legal_move? short-circuit helpers ──

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp has_non_king_move?(
         board,
         turn,
         us_bb,
         them_bb,
         all_bb,
         ep_sq,
         check_mask,
         pinned,
         pin_mask,
         king_sq,
         game,
         danger,
         num_checkers
       ) do
    knights = get_knights(board, turn) &&& bnot(pinned) &&& @mask64

    cond do
      any_knight_move?(knights, us_bb, check_mask) ->
        true

      any_slider_move?(:bishop, board, turn, us_bb, all_bb, check_mask, pin_mask) ->
        true

      any_slider_move?(:rook, board, turn, us_bb, all_bb, check_mask, pin_mask) ->
        true

      any_slider_move?(:queen, board, turn, us_bb, all_bb, check_mask, pin_mask) ->
        true

      any_pawn_move?(
        board,
        turn,
        us_bb,
        them_bb,
        all_bb,
        ep_sq,
        check_mask,
        pinned,
        pin_mask,
        king_sq
      ) ->
        true

      num_checkers == 0 ->
        any_castle_int?(game.castling, Helper.lsb(get_king_bb(board, turn)), turn, all_bb, danger)

      true ->
        false
    end
  end

  defp any_knight_move?(0, _us_bb, _check_mask), do: false

  defp any_knight_move?(knights, us_bb, check_mask) do
    from = Helper.lsb(knights)
    targets = Precomputed.get_knight_attacks(from) &&& bnot(us_bb) &&& check_mask &&& @mask64
    if targets != 0, do: true, else: any_knight_move?(knights &&& knights - 1, us_bb, check_mask)
  end

  defp any_slider_move?(type, board, turn, us_bb, all_bb, check_mask, pin_mask) do
    bb = get_slider_bb(board, turn, type)
    any_slider_move_loop?(bb, type, us_bb, all_bb, check_mask, pin_mask)
  end

  defp any_slider_move_loop?(0, _type, _us_bb, _all_bb, _cm, _pm), do: false

  defp any_slider_move_loop?(bb, type, us_bb, all_bb, check_mask, pin_mask) do
    from = Helper.lsb(bb)
    attacks = get_slider_attacks(type, from, all_bb)
    targets = attacks &&& bnot(us_bb) &&& check_mask &&& elem(pin_mask, from) &&& @mask64

    if targets != 0,
      do: true,
      else: any_slider_move_loop?(bb &&& bb - 1, type, us_bb, all_bb, check_mask, pin_mask)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp any_pawn_move?(
         board,
         turn,
         _us_bb,
         them_bb,
         all_bb,
         ep_sq,
         check_mask,
         pinned,
         pin_mask,
         king_sq
       ) do
    pawns = get_pawns(board, turn)
    {push_dir, _promo_rank, double_rank_mask, ep_cap_offset} = pawn_params(turn)

    single_pushes = shift_pawn(pawns, push_dir) &&& bnot(all_bb) &&& @mask64

    double_pushes =
      shift_pawn(single_pushes &&& double_rank_mask, push_dir) &&& bnot(all_bb) &&& @mask64

    cond do
      any_in_mask?(single_pushes, check_mask, pin_mask, -push_dir) ->
        true

      any_in_mask?(double_pushes, check_mask, pin_mask, -push_dir * 2) ->
        true

      any_pawn_capture?(pawns, turn, them_bb, check_mask, pin_mask) ->
        true

      ep_sq != nil ->
        ep_attackers = Precomputed.get_pawn_attacks(ep_sq, Piece.opponent(turn)) &&& pawns

        ep_attackers != 0 and
          ep_is_legal_any?(
            ep_attackers,
            ep_sq,
            ep_cap_offset,
            king_sq,
            turn,
            board,
            all_bb,
            pinned,
            pin_mask,
            check_mask
          )

      true ->
        false
    end
  end

  defp any_in_mask?(0, _cm, _pm, _offset), do: false

  defp any_in_mask?(bb, check_mask, pin_mask, offset) do
    to = Helper.lsb(bb)
    from = to + offset
    to_bit = 1 <<< to

    ok = (to_bit &&& check_mask &&& elem(pin_mask, from)) != 0

    if ok, do: true, else: any_in_mask?(bb &&& bb - 1, check_mask, pin_mask, offset)
  end

  defp any_pawn_capture?(0, _turn, _them, _cm, _pm), do: false

  defp any_pawn_capture?(pawns, turn, them_bb, check_mask, pin_mask) do
    from = Helper.lsb(pawns)
    attacks = Precomputed.get_pawn_attacks(from, turn)
    captures = attacks &&& them_bb &&& check_mask &&& elem(pin_mask, from)

    if captures != 0,
      do: true,
      else: any_pawn_capture?(pawns &&& pawns - 1, turn, them_bb, check_mask, pin_mask)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp ep_is_legal_any?(0, _ep_sq, _offset, _king_sq, _turn, _board, _all, _pinned, _pm, _cm),
    do: false

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp ep_is_legal_any?(
         attackers,
         ep_sq,
         ep_cap_offset,
         king_sq,
         turn,
         board,
         all_bb,
         pinned,
         pin_mask,
         check_mask
       ) do
    from = Helper.lsb(attackers)
    cap_sq = ep_sq + ep_cap_offset

    ep_valid = (1 <<< ep_sq &&& check_mask) != 0 or (1 <<< cap_sq &&& check_mask) != 0

    ok =
      if ep_valid do
        pin_ok = (1 <<< ep_sq &&& elem(pin_mask, from)) != 0

        if pin_ok do
          occ_after = bxor(all_bb, 1 <<< from ||| 1 <<< cap_sq) ||| 1 <<< ep_sq
          opponent = Piece.opponent(turn)
          enemy_rq = get_rooks(board, opponent) ||| get_queens(board, opponent)
          rook_attacks = Magic.get_rook_attacks(king_sq, occ_after)
          (rook_attacks &&& enemy_rq) == 0
        else
          false
        end
      else
        false
      end

    if ok,
      do: true,
      else:
        ep_is_legal_any?(
          attackers &&& attackers - 1,
          ep_sq,
          ep_cap_offset,
          king_sq,
          turn,
          board,
          all_bb,
          pinned,
          pin_mask,
          check_mask
        )
  end

  defp any_castle_int?(castling, king_sq, turn, all_bb, danger) do
    any_castle_side?(:kingside, castling, king_sq, turn, all_bb, danger) or
      any_castle_side?(:queenside, castling, king_sq, turn, all_bb, danger)
  end

  defp any_castle_side?(side, castling, _king_sq, turn, all_bb, danger) do
    if Game.has_right?(castling, turn, side) do
      {path_mask, check_mask, _target, _special} = castle_params(side, turn)
      (all_bb &&& path_mask) == 0 and (danger &&& check_mask) == 0
    else
      false
    end
  end

  # ── Pseudo-legal generation (kept for API compatibility) ──

  defp generate_pseudo_moves_int(%Game{board: board, turn: turn} = game) do
    board_tuple = ensure_tuple(board)

    us_bb =
      if turn == :white, do: Board.white_occ(board_tuple), else: Board.black_occ(board_tuple)

    them_bb =
      if turn == :white, do: Board.black_occ(board_tuple), else: Board.white_occ(board_tuple)

    all_bb = Board.all_occ(board_tuple)
    target_mask = bnot(us_bb) &&& @mask64

    []
    |> generate_pawn_moves(board_tuple, turn, them_bb, all_bb, game.en_passant)
    |> generate_knight_moves_pseudo(board_tuple, turn, target_mask)
    |> generate_sliding_moves_pseudo(:bishop, board_tuple, turn, all_bb, target_mask)
    |> generate_sliding_moves_pseudo(:rook, board_tuple, turn, all_bb, target_mask)
    |> generate_sliding_moves_pseudo(:queen, board_tuple, turn, all_bb, target_mask)
    |> generate_king_moves_pseudo(board_tuple, turn, target_mask)
    |> generate_castling_moves_pseudo(
      get_king_bb(board_tuple, turn),
      turn,
      game
    )
  end

  defp generate_captures_int(%Game{board: board, turn: turn} = game) do
    board_tuple = ensure_tuple(board)

    _us_bb =
      if turn == :white, do: Board.white_occ(board_tuple), else: Board.black_occ(board_tuple)

    them_bb =
      if turn == :white, do: Board.black_occ(board_tuple), else: Board.white_occ(board_tuple)

    generate_pawn_captures([], Board.wp(board_tuple), turn, them_bb, game.en_passant)
    |> generate_pawn_captures_only(board_tuple, turn, them_bb, game.en_passant)
    |> generate_knight_moves_pseudo(board_tuple, turn, them_bb)
    |> generate_sliding_moves_pseudo(
      :bishop,
      board_tuple,
      turn,
      Board.all_occ(board_tuple),
      them_bb
    )
    |> generate_sliding_moves_pseudo(
      :rook,
      board_tuple,
      turn,
      Board.all_occ(board_tuple),
      them_bb
    )
    |> generate_sliding_moves_pseudo(
      :queen,
      board_tuple,
      turn,
      Board.all_occ(board_tuple),
      them_bb
    )
    |> generate_king_moves_pseudo(board_tuple, turn, them_bb)
  end

  defp generate_quiets_int(%Game{board: board, turn: turn} = game) do
    board_tuple = ensure_tuple(board)

    all_bb = Board.all_occ(board_tuple)
    empty_bb = bnot(all_bb) &&& @mask64

    []
    |> generate_pawn_quiets(board_tuple, turn, all_bb)
    |> generate_knight_moves_pseudo(board_tuple, turn, empty_bb)
    |> generate_sliding_moves_pseudo(:bishop, board_tuple, turn, all_bb, empty_bb)
    |> generate_sliding_moves_pseudo(:rook, board_tuple, turn, all_bb, empty_bb)
    |> generate_sliding_moves_pseudo(:queen, board_tuple, turn, all_bb, empty_bb)
    |> generate_king_moves_pseudo(board_tuple, turn, empty_bb)
    |> generate_castling_moves_pseudo(get_king_bb(board_tuple, turn), turn, game)
  end

  # ── Pseudo-legal internal generators ──

  defp generate_pawn_captures_only(acc, board, :white, them_bb, ep_sq) do
    generate_pawn_captures(acc, Board.wp(board), :white, them_bb, ep_sq)
  end

  defp generate_pawn_captures_only(acc, board, :black, them_bb, ep_sq) do
    generate_pawn_captures(acc, Board.bp(board), :black, them_bb, ep_sq)
  end

  defp generate_pawn_quiets(acc, board, :white, all_bb) do
    pawns = Board.wp(board)
    single_pushes = pawns >>> 8 &&& bnot(all_bb) &&& @mask64
    acc = extract_pawn_moves(single_pushes, 8, :white, acc)

    rank_3_mask = 0x0000FF0000000000
    double_pushes = (single_pushes &&& rank_3_mask) >>> 8 &&& bnot(all_bb) &&& @mask64
    extract_pawn_double_moves(double_pushes, 16, acc)
  end

  defp generate_pawn_quiets(acc, board, :black, all_bb) do
    pawns = Board.bp(board)
    single_pushes = pawns <<< 8 &&& bnot(all_bb) &&& @mask64
    acc = extract_pawn_moves(single_pushes, -8, :black, acc)

    rank_6_mask = 0x0000000000FF0000
    double_pushes = (single_pushes &&& rank_6_mask) <<< 8 &&& bnot(all_bb) &&& @mask64
    extract_pawn_double_moves(double_pushes, -16, acc)
  end

  defp generate_pawn_moves(acc, board, :white, them_bb, all_bb, ep_sq) do
    pawns = Board.wp(board)
    single_pushes = pawns >>> 8 &&& bnot(all_bb) &&& @mask64
    acc = extract_pawn_moves(single_pushes, 8, :white, acc)

    rank_3_mask = 0x0000FF0000000000
    double_pushes = (single_pushes &&& rank_3_mask) >>> 8 &&& bnot(all_bb) &&& @mask64
    acc = extract_pawn_double_moves(double_pushes, 16, acc)

    generate_pawn_captures(acc, pawns, :white, them_bb, ep_sq)
  end

  defp generate_pawn_moves(acc, board, :black, them_bb, all_bb, ep_sq) do
    pawns = Board.bp(board)
    single_pushes = pawns <<< 8 &&& bnot(all_bb) &&& @mask64
    acc = extract_pawn_moves(single_pushes, -8, :black, acc)

    rank_6_mask = 0x0000000000FF0000
    double_pushes = (single_pushes &&& rank_6_mask) <<< 8 &&& bnot(all_bb) &&& @mask64
    acc = extract_pawn_double_moves(double_pushes, -16, acc)

    generate_pawn_captures(acc, pawns, :black, them_bb, ep_sq)
  end

  defp extract_pawn_moves(0, _, _, acc), do: acc

  defp extract_pawn_moves(targets, offset, color, acc) do
    to = Helper.lsb(targets)
    from = to + offset
    rank = div(to, 8)

    acc =
      if (color == :white and rank == 0) or (color == :black and rank == 7) do
        add_promotions(acc, from, to)
      else
        [Move.pack(from, to, nil, nil) | acc]
      end

    extract_pawn_moves(targets &&& targets - 1, offset, color, acc)
  end

  defp extract_pawn_double_moves(0, _, acc), do: acc

  defp extract_pawn_double_moves(targets, offset, acc) do
    to = Helper.lsb(targets)

    extract_pawn_double_moves(targets &&& targets - 1, offset, [
      Move.pack(to + offset, to, nil, nil) | acc
    ])
  end

  defp generate_pawn_captures(acc, pawns, color, them_bb, ep_sq) do
    ep_bb = if ep_sq, do: 1 <<< ep_sq, else: 0
    valid_targets = them_bb ||| ep_bb

    do_generate_pawn_captures(pawns, acc, color, valid_targets, ep_sq)
  end

  defp do_generate_pawn_captures(0, acc, _, _, _), do: acc

  defp do_generate_pawn_captures(pawns, acc, color, valid_targets, ep_sq) do
    from = Helper.lsb(pawns)
    attacks = Precomputed.get_pawn_attacks(from, color)
    captures = attacks &&& valid_targets

    acc = do_add_pawn_capture_moves(captures, acc, from, color, ep_sq)
    do_generate_pawn_captures(pawns &&& pawns - 1, acc, color, valid_targets, ep_sq)
  end

  defp do_add_pawn_capture_moves(0, acc, _, _, _), do: acc

  defp do_add_pawn_capture_moves(captures, acc, from, color, ep_sq) do
    to = Helper.lsb(captures)
    acc = add_pawn_capture_move(from, to, acc, color, ep_sq)
    do_add_pawn_capture_moves(captures &&& captures - 1, acc, from, color, ep_sq)
  end

  defp add_pawn_capture_move(from, to, m, color, ep_sq) do
    special = if to == ep_sq, do: :en_passant, else: nil
    rank = div(to, 8)

    if (color == :white and rank == 0) or (color == :black and rank == 7) do
      add_promotions(m, from, to)
    else
      [Move.pack(from, to, nil, special) | m]
    end
  end

  defp generate_knight_moves_pseudo(acc, board, turn, target_mask) do
    knights = if turn == :white, do: Board.wn(board), else: Board.bn(board)
    do_gen_knights_pseudo(knights, acc, target_mask)
  end

  defp do_gen_knights_pseudo(0, acc, _), do: acc

  defp do_gen_knights_pseudo(knights, acc, target_mask) do
    from = Helper.lsb(knights)
    valid_moves = Precomputed.get_knight_attacks(from) &&& target_mask
    acc = bitboard_to_moves_from(valid_moves, from, acc)
    do_gen_knights_pseudo(knights &&& knights - 1, acc, target_mask)
  end

  defp generate_sliding_moves_pseudo(acc, type, board, turn, all_bb, target_mask) do
    bb = get_slider_bb(board, turn, type)
    do_gen_sliders_pseudo(bb, acc, type, all_bb, target_mask)
  end

  defp do_gen_sliders_pseudo(0, acc, _, _, _), do: acc

  defp do_gen_sliders_pseudo(bb, acc, type, all_bb, target_mask) do
    from = Helper.lsb(bb)
    attacks = get_slider_attacks(type, from, all_bb)
    valid_moves = attacks &&& target_mask
    acc = bitboard_to_moves_from(valid_moves, from, acc)
    do_gen_sliders_pseudo(bb &&& bb - 1, acc, type, all_bb, target_mask)
  end

  defp generate_king_moves_pseudo(acc, board, turn, target_mask) do
    king_bb = get_king_bb(board, turn)

    if king_bb == 0 do
      acc
    else
      king_sq = Helper.lsb(king_bb)
      valid_moves = Precomputed.get_king_attacks(king_sq) &&& target_mask
      bitboard_to_moves_from(valid_moves, king_sq, acc)
    end
  end

  defp generate_castling_moves_pseudo(acc, king_bb, turn, game) do
    if king_bb == 0 do
      acc
    else
      king_sq = Helper.lsb(king_bb)
      castling = game.castling
      opponent = Piece.opponent(turn)

      if Game.in_check?(game) do
        acc
      else
        acc
        |> check_castling_pseudo(:kingside, castling, king_sq, turn, game, opponent)
        |> check_castling_pseudo(:queenside, castling, king_sq, turn, game, opponent)
      end
    end
  end

  defp check_castling_pseudo(acc, side, castling, king_sq, turn, game, opponent) do
    if Game.has_right?(castling, turn, side) and can_castle_pseudo?(side, turn, game, opponent) do
      target = if side == :kingside, do: king_sq + 2, else: king_sq - 2
      special = if side == :kingside, do: :kingside_castle, else: :queenside_castle
      [Move.pack(king_sq, target, nil, special) | acc]
    else
      acc
    end
  end

  defp can_castle_pseudo?(:kingside, :white, game, opponent) do
    board_tuple = ensure_tuple(game.board)

    (Board.all_occ(board_tuple) &&& Constants.white_ks_path()) == 0 and
      not Game.attacked?(game, 61, opponent) and not Game.attacked?(game, 62, opponent)
  end

  defp can_castle_pseudo?(:queenside, :white, game, opponent) do
    board_tuple = ensure_tuple(game.board)

    (Board.all_occ(board_tuple) &&& Constants.white_qs_path()) == 0 and
      not Game.attacked?(game, 59, opponent) and not Game.attacked?(game, 58, opponent)
  end

  defp can_castle_pseudo?(:kingside, :black, game, opponent) do
    board_tuple = ensure_tuple(game.board)

    (Board.all_occ(board_tuple) &&& Constants.black_ks_path()) == 0 and
      not Game.attacked?(game, 5, opponent) and not Game.attacked?(game, 6, opponent)
  end

  defp can_castle_pseudo?(:queenside, :black, game, opponent) do
    board_tuple = ensure_tuple(game.board)

    (Board.all_occ(board_tuple) &&& Constants.black_qs_path()) == 0 and
      not Game.attacked?(game, 3, opponent) and not Game.attacked?(game, 2, opponent)
  end

  # ── Reverse pawn moves (for generate_moves_targeting) ──

  defp reverse_pawn_moves(game, to, :white) do
    board = ensure_tuple(game.board)
    white_pawns = Board.wp(board)
    moves = []

    moves = add_reverse_single_push(moves, to, white_pawns, board, 8)
    moves = add_reverse_double_push(moves, to, white_pawns, board, 16, 32..39)

    is_ep = game.en_passant == to
    target_occupied = Board.at(board, to) != nil and match?({:black, _}, Board.at(board, to))

    if is_ep or target_occupied do
      moves
      |> add_reverse_captures(to, white_pawns, is_ep, [9, 7])
      |> add_promo_if_needed(to)
    else
      add_promo_if_needed(moves, to)
    end
  end

  defp reverse_pawn_moves(game, to, :black) do
    board = ensure_tuple(game.board)
    black_pawns = Board.bp(board)
    moves = []

    moves = add_reverse_single_push_black(moves, to, black_pawns, board, -8)
    moves = add_reverse_double_push_black(moves, to, black_pawns, board, -16, 24..31)

    is_ep = game.en_passant == to
    target_occupied = Board.at(board, to) != nil and match?({:white, _}, Board.at(board, to))

    if is_ep or target_occupied do
      moves
      |> add_reverse_captures_black(to, black_pawns, is_ep, [-7, -9])
      |> add_promo_if_needed(to)
    else
      add_promo_if_needed(moves, to)
    end
  end

  defp add_reverse_single_push(moves, to, pawns, board, offset) do
    from = to + offset

    if from <= 63 and (pawns &&& 1 <<< from) != 0 and Board.at(board, to) == nil do
      [Move.pack(from, to, nil, nil) | moves]
    else
      moves
    end
  end

  defp add_reverse_double_push(moves, to, pawns, board, offset, range) do
    if to in range and Board.at(board, to) == nil and Board.at(board, to + div(offset, 2)) == nil do
      from = to + offset
      if (pawns &&& 1 <<< from) != 0, do: [Move.pack(from, to, nil, nil) | moves], else: moves
    else
      moves
    end
  end

  defp add_reverse_captures(moves, to, pawns, is_ep, offsets) do
    Enum.reduce(offsets, moves, fn offset, acc ->
      from = to + offset

      if from <= 63 and (pawns &&& 1 <<< from) != 0 and abs(rem(from, 8) - rem(to, 8)) == 1 do
        [create_pawn_move(from, to, is_ep) | acc]
      else
        acc
      end
    end)
  end

  defp add_reverse_single_push_black(moves, to, pawns, board, offset) do
    from = to + offset

    if from >= 0 and (pawns &&& 1 <<< from) != 0 and Board.at(board, to) == nil do
      [Move.pack(from, to, nil, nil) | moves]
    else
      moves
    end
  end

  defp add_reverse_double_push_black(moves, to, pawns, board, offset, range) do
    if to in range and Board.at(board, to) == nil and Board.at(board, to + div(offset, 2)) == nil do
      from = to + offset
      if (pawns &&& 1 <<< from) != 0, do: [Move.pack(from, to, nil, nil) | moves], else: moves
    else
      moves
    end
  end

  defp add_reverse_captures_black(moves, to, pawns, is_ep, offsets) do
    Enum.reduce(offsets, moves, fn offset, acc ->
      from = to + offset

      if from >= 0 and (pawns &&& 1 <<< from) != 0 and abs(rem(from, 8) - rem(to, 8)) == 1 do
        [create_pawn_move(from, to, is_ep) | acc]
      else
        acc
      end
    end)
  end

  defp add_promo_if_needed(moves, to) do
    rank = div(to, 8)
    if rank == 0 or rank == 7, do: expand_promotions(moves), else: moves
  end

  defp expand_promotions(moves) do
    Enum.flat_map(moves, fn m ->
      [:queen, :rook, :bishop, :knight]
      |> Enum.map(fn p ->
        from = Move.unpack_from(m)
        to = Move.unpack_to(m)
        special = Move.unpack_special(m)
        Move.pack(from, to, p, special)
      end)
    end)
  end

  defp create_pawn_move(from, to, true), do: Move.pack(from, to, nil, :en_passant)
  defp create_pawn_move(from, to, false), do: Move.pack(from, to, nil, nil)

  # ── Serialization helpers ──

  defp bitboard_to_moves_to(0, _, acc), do: acc

  defp bitboard_to_moves_to(bb, to, acc) do
    from = Helper.lsb(bb)
    bitboard_to_moves_to(bb &&& bb - 1, to, [Move.pack(from, to, nil, nil) | acc])
  end

  defp bitboard_to_moves_from(0, _, acc), do: acc

  defp bitboard_to_moves_from(bb, from, acc) do
    to = Helper.lsb(bb)
    bitboard_to_moves_from(bb &&& bb - 1, from, [Move.pack(from, to, nil, nil) | acc])
  end

  # ── Piece accessor helpers ──

  defp ensure_tuple(board) when is_tuple(board), do: board
  defp ensure_tuple(board), do: Board.from_struct(board)

  defp get_occupancies(board, :white) do
    {Board.white_occ(board), Board.black_occ(board), Board.all_occ(board)}
  end

  defp get_occupancies(board, :black) do
    {Board.black_occ(board), Board.white_occ(board), Board.all_occ(board)}
  end

  defp get_king_bb(board, :white), do: Board.wk(board)
  defp get_king_bb(board, :black), do: Board.bk(board)

  defp get_pawns(board, :white), do: Board.wp(board)
  defp get_pawns(board, :black), do: Board.bp(board)

  defp get_knights(board, :white), do: Board.wn(board)
  defp get_knights(board, :black), do: Board.bn(board)

  defp get_bishops(board, :white), do: Board.wb(board)
  defp get_bishops(board, :black), do: Board.bb(board)

  defp get_rooks(board, :white), do: Board.wr(board)
  defp get_rooks(board, :black), do: Board.br(board)

  defp get_queens(board, :white), do: Board.wq(board)
  defp get_queens(board, :black), do: Board.bq(board)

  defp get_slider_bb(board, :white, :bishop), do: Board.wb(board)
  defp get_slider_bb(board, :white, :rook), do: Board.wr(board)
  defp get_slider_bb(board, :white, :queen), do: Board.wq(board)
  defp get_slider_bb(board, :black, :bishop), do: Board.bb(board)
  defp get_slider_bb(board, :black, :rook), do: Board.br(board)
  defp get_slider_bb(board, :black, :queen), do: Board.bq(board)

  defp get_slider_attacks(:bishop, from, all_bb), do: Magic.get_bishop_attacks(from, all_bb)
  defp get_slider_attacks(:rook, from, all_bb), do: Magic.get_rook_attacks(from, all_bb)

  defp get_slider_attacks(:queen, from, all_bb),
    do: Magic.get_bishop_attacks(from, all_bb) ||| Magic.get_rook_attacks(from, all_bb)

  defp get_piece_bb(board, :white, :pawn), do: Board.wp(board)
  defp get_piece_bb(board, :white, :knight), do: Board.wn(board)
  defp get_piece_bb(board, :white, :bishop), do: Board.wb(board)
  defp get_piece_bb(board, :white, :rook), do: Board.wr(board)
  defp get_piece_bb(board, :white, :queen), do: Board.wq(board)
  defp get_piece_bb(board, :white, :king), do: Board.wk(board)
  defp get_piece_bb(board, :black, :pawn), do: Board.bp(board)
  defp get_piece_bb(board, :black, :knight), do: Board.bn(board)
  defp get_piece_bb(board, :black, :bishop), do: Board.bb(board)
  defp get_piece_bb(board, :black, :rook), do: Board.br(board)
  defp get_piece_bb(board, :black, :queen), do: Board.bq(board)
  defp get_piece_bb(board, :black, :king), do: Board.bk(board)
end
