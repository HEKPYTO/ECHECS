defmodule Echecs.MoveGen do
  @moduledoc """
  Legal-only move generation using the check-mask + pin-mask technique.

  Instead of generating pseudo-legal moves and filtering them, `legal_moves_int/4`
  computes the checking pieces (`check_mask`) and the pinned rays (`pin_rays`)
  once per position, then emits only legal moves: king moves avoid the danger
  set, and all other moves are masked by `check_mask` and their pin ray. Double
  check exits early with king moves only.

  Moves are emitted as packed integers (see `Echecs.Move`) and converted to
  structs only at the API boundary by `legal_moves/1`. The `captures/1` and
  `quiets/1` variants share the same pipeline for search use.
  """

  import Bitwise
  alias Echecs.Bitboard.{Constants, Magic, Precomputed}
  alias Echecs.{Board, Game, Move}

  require Echecs.Move
  require Echecs.Bitboard.Constants

  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  @mask64 Constants.mask64()

  # Local bit-scan (De Bruijn), bit-identical to Helper.lsb/1.
  # Lives here so the compiler can inline it into the hot loops below;
  # cross-module calls to Helper.lsb/1 cannot be inlined and dominated the
  # fresh :eprof profile (~18.5% in Helper.lsb/1 over perft 4).
  @debruijn64 0x03F79D71B4CB0A89
  @lsb_index {
    0,
    1,
    48,
    2,
    57,
    49,
    28,
    3,
    61,
    58,
    50,
    42,
    38,
    29,
    17,
    4,
    62,
    55,
    59,
    36,
    53,
    51,
    43,
    22,
    45,
    39,
    33,
    30,
    24,
    18,
    12,
    5,
    63,
    47,
    56,
    27,
    60,
    41,
    37,
    16,
    54,
    35,
    52,
    21,
    44,
    32,
    23,
    11,
    46,
    26,
    40,
    15,
    34,
    20,
    31,
    10,
    25,
    14,
    19,
    9,
    13,
    8,
    7,
    6
  }

  @compile {:inline,
            lsb: 1,
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
            ensure_tuple: 1,
            bitboard_to_moves_from: 3,
            add_pawn_move: 5,
            add_promotions: 3,
            do_gen_sliders_fast: 5,
            do_gen_knights_fast: 3,
            opp: 1,
            popc: 1,
            right?: 3}

  defp lsb(0), do: nil

  defp lsb(bb) do
    isolated = bb &&& -bb
    prod = isolated * @debruijn64 &&& 0xFFFFFFFFFFFFFFFF
    idx = prod >>> 58
    elem(@lsb_index, idx)
  end

  # Local trivial getters, bit-identical to the cross-module originals.
  # Remote calls cannot be inlined by the compiler; resolving them here as
  # inline tuple loads removes ~40 cross-module calls per node (profile:
  # Board/Piece/Game trivial getters ~10% of perft time).
  # Board tuple layout (see Echecs.Board wp..bk, white/black/all_occ):
  # white pieces 0..5, black pieces 6..11, occupancies 12/13/14.
  defp opp(:white), do: :black
  defp opp(:black), do: :white

  # Bit-identical to Helper.pop_count/1 (Hamming-weight reduction).
  defp popc(bb) do
    bb = bb - (bb >>> 1 &&& 0x5555555555555555)
    bb = (bb &&& 0x3333333333333333) + (bb >>> 2 &&& 0x3333333333333333)
    bb = bb + (bb >>> 4) &&& 0x0F0F0F0F0F0F0F0F
    (bb * 0x0101010101010101 &&& 0xFFFFFFFFFFFFFFFF) >>> 56
  end

  # Bit-identical to Game.has_right?/3 (castling bits wk=1, wq=2, bk=4, bq=8).
  defp right?(castling, :white, :kingside), do: (castling &&& 1) != 0
  defp right?(castling, :white, :queenside), do: (castling &&& 2) != 0
  defp right?(castling, :black, :kingside), do: (castling &&& 4) != 0
  defp right?(castling, :black, :queenside), do: (castling &&& 8) != 0

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
    legal_moves_int(ensure_tuple(game.board), game.turn, game.castling, game.en_passant)
  end

  def legal_moves_int(board, turn, castling, en_passant) do
    opponent = opp(turn)

    {us_bb, them_bb, all_bb} = get_occupancies(board, turn)
    king_bb = get_king_bb(board, turn)
    king_sq = lsb(king_bb)

    # Compute danger squares for the king first (with king removed from
    # occupancy). Removing the king only extends enemy rays, so a clear danger
    # bit on our king square proves we are not in check. Checks are rare:
    # testing that bit first skips compute_checkers' two slider magic calls
    # on nearly every node (profile: compute_checkers ~2.4% + magic share).
    occ_no_king = bxor(all_bb, king_bb)
    danger = compute_danger(board, opponent, occ_no_king)

    checkers =
      if (danger &&& king_bb) == 0 do
        0
      else
        compute_checkers(board, king_sq, opponent, all_bb)
      end

    num_checkers = if checkers == 0, do: 0, else: popc(checkers)

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
      # not_us hoisted: one bnot/node instead of one per slider piece (~8/node).
      not_us = bnot(us_bb) &&& @mask64

      moves
      |> gen_pawn_moves(
        board,
        turn,
        us_bb,
        them_bb,
        all_bb,
        en_passant,
        check_mask,
        pinned,
        pin_rays,
        king_sq
      )
      |> gen_knight_moves(board, turn, us_bb, check_mask, pinned)
      |> gen_slider_moves(:bishop, board, turn, not_us, all_bb, check_mask, pinned, pin_rays)
      |> gen_slider_moves(:rook, board, turn, not_us, all_bb, check_mask, pinned, pin_rays)
      |> gen_slider_moves(:queen, board, turn, not_us, all_bb, check_mask, pinned, pin_rays)
      |> gen_castling(king_sq, turn, castling, all_bb, danger, num_checkers)
    end
  end

  @doc """
  Returns true if there is at least one legal move. Short-circuits on first found.
  """
  def has_legal_move?(%Game{} = game) do
    has_legal_move?(ensure_tuple(game.board), game.turn, game.castling, game.en_passant)
  end

  def has_legal_move?(board, turn, castling, en_passant) do
    opponent = opp(turn)

    {us_bb, them_bb, all_bb} = get_occupancies(board, turn)
    king_bb = get_king_bb(board, turn)
    king_sq = lsb(king_bb)

    checkers = compute_checkers(board, king_sq, opponent, all_bb)
    num_checkers = popc(checkers)

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
          castling,
          us_bb,
          them_bb,
          all_bb,
          en_passant,
          check_mask,
          pinned,
          pin_rays,
          king_sq,
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
    defender_color = opp(attacker_color)

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
    # Single-checker precondition: both call sites return early on
    # num_checkers >= 2, so reaching here with 2+ checkers means a future
    # caller broke the contract — fail loud instead of masking one checker.
    if popc(checkers) > 1,
      do: raise(ArgumentError, "compute_check_mask: #{popc(checkers)} checkers, expected 0 or 1")

    checker_sq = lsb(checkers)
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
    enemy_king_sq = lsb(get_king_bb(board, attacker_color))
    if enemy_king_sq, do: danger ||| Precomputed.get_king_attacks(enemy_king_sq), else: danger
  end

  defp or_knight_attacks(danger, 0), do: danger

  defp or_knight_attacks(danger, bb) do
    sq = lsb(bb)
    or_knight_attacks(danger ||| Precomputed.get_knight_attacks(sq), bb &&& bb - 1)
  end

  defp or_bishop_attacks(danger, 0, _occ), do: danger

  defp or_bishop_attacks(danger, bb, occ) do
    sq = lsb(bb)
    or_bishop_attacks(danger ||| Magic.get_bishop_attacks(sq, occ), bb &&& bb - 1, occ)
  end

  defp or_rook_attacks(danger, 0, _occ), do: danger

  defp or_rook_attacks(danger, bb, occ) do
    sq = lsb(bb)
    or_rook_attacks(danger ||| Magic.get_rook_attacks(sq, occ), bb &&& bb - 1, occ)
  end

  # Precomputed all-ones pin mask for the common case of no pins
  @no_pin_mask :erlang.make_tuple(64, Constants.mask64())

  # Returns {pinned_bb, pin_mask_tuple} where pin_mask_tuple is a 64-element tuple.
  # Unpinned squares have @mask64 (all-ones), pinned squares have their ray mask.
  # This enables branchless pin checking: targets &&& elem(pin_mask, from)
  defp compute_pins(board, king_sq, turn, us_bb, them_bb) do
    opponent = opp(turn)

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
    pinner_sq = lsb(pinners)
    between = Precomputed.get_between(king_sq, pinner_sq)
    our_between = between &&& us_bb

    {pinned, pin_mask} =
      if popc(our_between) == 1 do
        pinned_sq = lsb(our_between)
        ray = between ||| 1 <<< pinner_sq
        {pinned ||| our_between, put_elem(pin_mask, pinned_sq, ray)}
      else
        {pinned, pin_mask}
      end

    process_pinners(pinners &&& pinners - 1, king_sq, us_bb, pinned, pin_mask)
  end

  # ── Non-king move generation (with check_mask + pin restrictions) ──

  # Knights: pinned knights can NEVER move. Fast path (mirrors the slider
  # fast path): with no check every unpinned knight move is legal, so hoist
  # not_us once and skip the per-knight check_mask AND (profile:
  # do_gen_knights ~4.7% of perft time, checks present in <10% of nodes).
  defp gen_knight_moves(acc, board, turn, us_bb, check_mask, pinned) do
    knights = get_knights(board, turn)
    knights = if pinned == 0, do: knights, else: knights &&& bnot(pinned) &&& @mask64

    if check_mask == @mask64 do
      do_gen_knights_fast(knights, acc, bnot(us_bb) &&& @mask64)
    else
      do_gen_knights(knights, acc, us_bb, check_mask)
    end
  end

  defp do_gen_knights_fast(0, acc, _not_us), do: acc

  defp do_gen_knights_fast(knights, acc, not_us) do
    from = lsb(knights)
    targets = Precomputed.get_knight_attacks(from) &&& not_us
    acc = bitboard_to_moves_from(targets, from, acc)
    do_gen_knights_fast(knights &&& knights - 1, acc, not_us)
  end

  defp do_gen_knights(0, acc, _us_bb, _check_mask), do: acc

  defp do_gen_knights(knights, acc, us_bb, check_mask) do
    from = lsb(knights)
    targets = Precomputed.get_knight_attacks(from) &&& bnot(us_bb) &&& check_mask &&& @mask64
    acc = bitboard_to_moves_from(targets, from, acc)
    do_gen_knights(knights &&& knights - 1, acc, us_bb, check_mask)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp gen_slider_moves(acc, type, board, turn, not_us, all_bb, check_mask, pinned, pin_mask) do
    bb = get_slider_bb(board, turn, type)

    # Fast path: no check and no pins (the common case) — skip the per-piece
    # check_mask AND and pin_mask tuple lookup (profile: do_gen_sliders ~7.9%).
    if pinned == 0 and check_mask == @mask64 do
      do_gen_sliders_fast(bb, acc, type, not_us, all_bb)
    else
      do_gen_sliders(bb, acc, type, not_us, all_bb, check_mask, pin_mask)
    end
  end

  defp do_gen_sliders_fast(0, acc, _type, _not_us, _all_bb), do: acc

  defp do_gen_sliders_fast(bb, acc, type, not_us, all_bb) do
    from = lsb(bb)
    targets = get_slider_attacks(type, from, all_bb) &&& not_us
    acc = bitboard_to_moves_from(targets, from, acc)
    do_gen_sliders_fast(bb &&& bb - 1, acc, type, not_us, all_bb)
  end

  defp do_gen_sliders(0, acc, _type, _not_us, _all_bb, _check_mask, _pin_mask), do: acc

  defp do_gen_sliders(bb, acc, type, not_us, all_bb, check_mask, pin_mask) do
    from = lsb(bb)
    attacks = get_slider_attacks(type, from, all_bb)
    # Branchless pin mask: unpinned squares have @mask64 (no-op AND), pinned have ray.
    # not_us is already @mask64-masked, so the trailing mask is a no-op here.
    targets = attacks &&& not_us &&& check_mask &&& elem(pin_mask, from)

    acc = bitboard_to_moves_from(targets, from, acc)
    do_gen_sliders(bb &&& bb - 1, acc, type, not_us, all_bb, check_mask, pin_mask)
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

    # Fast path: with no check (full check_mask) and no pins, every push is
    # legal — skip the per-square check_mask/pin_mask test (profile: push
    # extractors ~9.3% of perft time, test almost always passes).
    unrestricted = pinned == 0 and check_mask == @mask64

    # The promo test in add_pawn_move is loop-invariant per node: a white
    # single push promotes iff it starts from squares 8..15 (mask 0xFF00), a
    # black one iff from squares 48..55. Promos are vanishingly rare, so when
    # no pawn sits on a pre-promo square every push is a plain move — skip
    # the per-push promo_rank test entirely (profile:
    # extract_pawn_pushes_fast ~6.3% of perft time).
    promo_possible =
      if promo_rank == 0,
        do: (pawns &&& 0xFF00) != 0,
        else: (pawns &&& 0x00FF000000000000) != 0

    # ── Single pushes ──
    single_pushes = shift_pawn(pawns, push_dir) &&& bnot(all_bb) &&& @mask64

    acc =
      cond do
        unrestricted and not promo_possible ->
          extract_pawn_pushes_plain(single_pushes, -push_dir, acc)

        unrestricted ->
          extract_pawn_pushes_fast(single_pushes, -push_dir, turn, promo_rank, acc)

        true ->
          extract_legal_pawn_pushes(
            single_pushes,
            -push_dir,
            turn,
            promo_rank,
            check_mask,
            pin_mask,
            acc
          )
      end

    # ── Double pushes ──
    double_pushes =
      shift_pawn(single_pushes &&& double_rank_mask, push_dir) &&& bnot(all_bb) &&& @mask64

    acc =
      if unrestricted do
        extract_pawn_double_pushes_fast(double_pushes, -push_dir * 2, acc)
      else
        extract_legal_pawn_double_pushes(double_pushes, -push_dir * 2, check_mask, pin_mask, acc)
      end

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
    to = lsb(pushes)
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
    to = lsb(pushes)
    from = to + offset
    to_bit = 1 <<< to

    acc =
      if (to_bit &&& check_mask &&& elem(pin_mask, from)) != 0 do
        [Move.pack_plain(from, to) | acc]
      else
        acc
      end

    extract_legal_pawn_double_pushes(pushes &&& pushes - 1, offset, check_mask, pin_mask, acc)
  end

  # Promo-free single pushes: valid only when no pawn sits on a pre-promo
  # square (see gen_pawn_moves), so every push is a plain move.
  defp extract_pawn_pushes_plain(0, _offset, acc), do: acc

  defp extract_pawn_pushes_plain(pushes, offset, acc) do
    to = lsb(pushes)
    from = to + offset

    extract_pawn_pushes_plain(pushes &&& pushes - 1, offset, [
      Move.pack_plain(from, to) | acc
    ])
  end

  # Fast paths for extract_legal_pawn_pushes/7 and
  # extract_legal_pawn_double_pushes/5 when every push is known legal
  # (no check, no pins): no check_mask/pin_mask tests per square.
  defp extract_pawn_pushes_fast(0, _offset, _turn, _promo_rank, acc), do: acc

  defp extract_pawn_pushes_fast(pushes, offset, turn, promo_rank, acc) do
    to = lsb(pushes)
    from = to + offset
    acc = add_pawn_move(acc, from, to, turn, promo_rank)
    extract_pawn_pushes_fast(pushes &&& pushes - 1, offset, turn, promo_rank, acc)
  end

  defp extract_pawn_double_pushes_fast(0, _offset, acc), do: acc

  defp extract_pawn_double_pushes_fast(pushes, offset, acc) do
    to = lsb(pushes)
    from = to + offset

    extract_pawn_double_pushes_fast(pushes &&& pushes - 1, offset, [
      Move.pack_plain(from, to) | acc
    ])
  end

  defp gen_pawn_captures(0, _turn, _them_bb, _promo_rank, _cm, _pin_mask, acc), do: acc

  # Bulk capture targets via shifts (same masks as compute_danger pawn attacks).
  # Captures are rare (profile: <1% of pawn iterations find one), so iterating
  # actual capture squares beats one get_pawn_attacks table lookup per pawn.
  defp gen_pawn_captures(pawns, :white, them_bb, promo_rank, check_mask, pin_mask, acc) do
    left = (pawns &&& bnot(Constants.file_a()) &&& @mask64) >>> 9
    right = (pawns &&& bnot(Constants.file_h()) &&& @mask64) >>> 7
    targets = (left ||| right) &&& them_bb &&& check_mask &&& @mask64
    do_bulk_pawn_captures(targets, left, right, 9, 7, :white, promo_rank, pin_mask, acc)
  end

  defp gen_pawn_captures(pawns, :black, them_bb, promo_rank, check_mask, pin_mask, acc) do
    left = (pawns &&& bnot(Constants.file_a()) &&& @mask64) <<< 7
    right = (pawns &&& bnot(Constants.file_h()) &&& @mask64) <<< 9
    targets = (left ||| right) &&& them_bb &&& check_mask &&& @mask64
    do_bulk_pawn_captures(targets, left, right, -7, -9, :black, promo_rank, pin_mask, acc)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp do_bulk_pawn_captures(0, _left, _right, _ol, _or, _turn, _promo, _pm, acc), do: acc

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  defp do_bulk_pawn_captures(
         targets,
         left,
         right,
         off_left,
         off_right,
         turn,
         promo_rank,
         pin_mask,
         acc
       ) do
    to = lsb(targets)
    to_bit = 1 <<< to
    # A square can be captured by two pawns; each (from, to) pair is pin-tested.
    acc =
      if (to_bit &&& left) != 0,
        do: maybe_add_pawn_capture(acc, to + off_left, to, to_bit, turn, promo_rank, pin_mask),
        else: acc

    acc =
      if (to_bit &&& right) != 0,
        do: maybe_add_pawn_capture(acc, to + off_right, to, to_bit, turn, promo_rank, pin_mask),
        else: acc

    do_bulk_pawn_captures(
      targets &&& targets - 1,
      left,
      right,
      off_left,
      off_right,
      turn,
      promo_rank,
      pin_mask,
      acc
    )
  end

  defp maybe_add_pawn_capture(acc, from, to, to_bit, turn, promo_rank, pin_mask) do
    if (to_bit &&& elem(pin_mask, from)) != 0 do
      add_pawn_move(acc, from, to, turn, promo_rank)
    else
      acc
    end
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
    ep_attackers = Precomputed.get_pawn_attacks(ep_sq, opp(turn)) &&& pawns

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
    from = lsb(attackers)
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
          # EP discovered-check re-test: only orthogonal (rook/queen) rays.
          # Soundness rests on a reachability precondition. The capture vacates
          # two squares (captor `from`, victim `cap_sq`) and re-blocks on
          # `ep_sq`, tested via `occ_after` below. Diagonal uncoverings by the
          # captor leaving `from` are already excluded by the pin check above.
          # The victim cannot be the sole diagonal shield of a new ray: it is
          # an enemy pawn that just double pushed, so its square was empty in
          # the pre-push position and that diagonal would already have been
          # open then — impossible from a legal pre-push position. Hence, from
          # legal double pushes only, no diagonal re-test is needed here.
          occ_after = bxor(all_bb, 1 <<< from ||| 1 <<< cap_sq) ||| 1 <<< ep_sq
          opponent = opp(turn)
          enemy_rq = get_rooks(board, opponent) ||| get_queens(board, opponent)
          rook_attacks = Magic.get_rook_attacks(king_sq, occ_after)

          if (rook_attacks &&& enemy_rq) == 0 do
            [Move.pack_fast(from, ep_sq, 0, 1) | acc]
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
    # to in 0..7 <=> rank 0 (white promo), to in 56..63 <=> rank 7 (black promo):
    # comparison instead of div(to, 8) on every pawn move.
    if (promo_rank == 0 and to < 8) or (promo_rank == 7 and to >= 56) do
      add_promotions(acc, from, to)
    else
      [Move.pack_plain(from, to) | acc]
    end
  end

  defp add_promotions(acc, from, to) do
    # Promo bit fields are loop-invariant literals: queen = 4, rook = 3,
    # bishop = 2, knight = 1. No encode_promo call per move.
    [
      Move.pack_fast(from, to, 4, 0),
      Move.pack_fast(from, to, 3, 0),
      Move.pack_fast(from, to, 2, 0),
      Move.pack_fast(from, to, 1, 0) | acc
    ]
  end

  # ── Castling ──

  defp gen_castling(acc, _king_sq, _turn, _castling, _all_bb, _danger, num_checkers)
       when num_checkers > 0,
       do: acc

  defp gen_castling(acc, king_sq, turn, castling, all_bb, danger, 0) do
    acc
    |> try_castle(:kingside, castling, king_sq, turn, all_bb, danger)
    |> try_castle(:queenside, castling, king_sq, turn, all_bb, danger)
  end

  defp try_castle(acc, side, castling, king_sq, turn, all_bb, danger) do
    if right?(castling, turn, side) do
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
         castling,
         us_bb,
         them_bb,
         all_bb,
         ep_sq,
         check_mask,
         pinned,
         pin_mask,
         king_sq,
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
        any_castle_int?(castling, lsb(get_king_bb(board, turn)), turn, all_bb, danger)

      true ->
        false
    end
  end

  defp any_knight_move?(0, _us_bb, _check_mask), do: false

  defp any_knight_move?(knights, us_bb, check_mask) do
    from = lsb(knights)
    targets = Precomputed.get_knight_attacks(from) &&& bnot(us_bb) &&& check_mask &&& @mask64
    if targets != 0, do: true, else: any_knight_move?(knights &&& knights - 1, us_bb, check_mask)
  end

  defp any_slider_move?(type, board, turn, us_bb, all_bb, check_mask, pin_mask) do
    bb = get_slider_bb(board, turn, type)
    any_slider_move_loop?(bb, type, us_bb, all_bb, check_mask, pin_mask)
  end

  defp any_slider_move_loop?(0, _type, _us_bb, _all_bb, _cm, _pm), do: false

  defp any_slider_move_loop?(bb, type, us_bb, all_bb, check_mask, pin_mask) do
    from = lsb(bb)
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
        ep_attackers = Precomputed.get_pawn_attacks(ep_sq, opp(turn)) &&& pawns

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
    to = lsb(bb)
    from = to + offset
    to_bit = 1 <<< to

    ok = (to_bit &&& check_mask &&& elem(pin_mask, from)) != 0

    if ok, do: true, else: any_in_mask?(bb &&& bb - 1, check_mask, pin_mask, offset)
  end

  defp any_pawn_capture?(0, _turn, _them, _cm, _pm), do: false

  defp any_pawn_capture?(pawns, turn, them_bb, check_mask, pin_mask) do
    from = lsb(pawns)
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
    from = lsb(attackers)
    cap_sq = ep_sq + ep_cap_offset

    ep_valid = (1 <<< ep_sq &&& check_mask) != 0 or (1 <<< cap_sq &&& check_mask) != 0

    ok =
      if ep_valid do
        pin_ok = (1 <<< ep_sq &&& elem(pin_mask, from)) != 0

        if pin_ok do
          occ_after = bxor(all_bb, 1 <<< from ||| 1 <<< cap_sq) ||| 1 <<< ep_sq
          opponent = opp(turn)
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
    if right?(castling, turn, side) do
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
    to = lsb(targets)
    from = to + offset

    acc =
      if (color == :white and to < 8) or (color == :black and to >= 56) do
        add_promotions(acc, from, to)
      else
        [Move.pack_plain(from, to) | acc]
      end

    extract_pawn_moves(targets &&& targets - 1, offset, color, acc)
  end

  defp extract_pawn_double_moves(0, _, acc), do: acc

  defp extract_pawn_double_moves(targets, offset, acc) do
    to = lsb(targets)

    extract_pawn_double_moves(targets &&& targets - 1, offset, [
      Move.pack_plain(to + offset, to) | acc
    ])
  end

  defp generate_pawn_captures(acc, pawns, color, them_bb, ep_sq) do
    ep_bb = if ep_sq, do: 1 <<< ep_sq, else: 0
    valid_targets = them_bb ||| ep_bb

    do_generate_pawn_captures(pawns, acc, color, valid_targets, ep_sq)
  end

  defp do_generate_pawn_captures(0, acc, _, _, _), do: acc

  defp do_generate_pawn_captures(pawns, acc, color, valid_targets, ep_sq) do
    from = lsb(pawns)
    attacks = Precomputed.get_pawn_attacks(from, color)
    captures = attacks &&& valid_targets

    acc = do_add_pawn_capture_moves(captures, acc, from, color, ep_sq)
    do_generate_pawn_captures(pawns &&& pawns - 1, acc, color, valid_targets, ep_sq)
  end

  defp do_add_pawn_capture_moves(0, acc, _, _, _), do: acc

  defp do_add_pawn_capture_moves(captures, acc, from, color, ep_sq) do
    to = lsb(captures)
    acc = add_pawn_capture_move(from, to, acc, color, ep_sq)
    do_add_pawn_capture_moves(captures &&& captures - 1, acc, from, color, ep_sq)
  end

  defp add_pawn_capture_move(from, to, m, color, ep_sq) do
    if (color == :white and to < 8) or (color == :black and to >= 56) do
      add_promotions(m, from, to)
    else
      sbits = if to == ep_sq, do: 1, else: 0
      [Move.pack_fast(from, to, 0, sbits) | m]
    end
  end

  defp generate_knight_moves_pseudo(acc, board, turn, target_mask) do
    knights = if turn == :white, do: Board.wn(board), else: Board.bn(board)
    do_gen_knights_pseudo(knights, acc, target_mask)
  end

  defp do_gen_knights_pseudo(0, acc, _), do: acc

  defp do_gen_knights_pseudo(knights, acc, target_mask) do
    from = lsb(knights)
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
    from = lsb(bb)
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
      king_sq = lsb(king_bb)
      valid_moves = Precomputed.get_king_attacks(king_sq) &&& target_mask
      bitboard_to_moves_from(valid_moves, king_sq, acc)
    end
  end

  defp generate_castling_moves_pseudo(acc, king_bb, turn, game) do
    if king_bb == 0 do
      acc
    else
      board = ensure_tuple(game.board)
      king_sq = lsb(king_bb)
      castling = game.castling
      opponent = opp(turn)

      if Board.attacked?(board, king_sq, opponent) do
        acc
      else
        acc
        |> check_castling_pseudo(:kingside, castling, king_sq, turn, board, opponent)
        |> check_castling_pseudo(:queenside, castling, king_sq, turn, board, opponent)
      end
    end
  end

  defp check_castling_pseudo(acc, side, castling, king_sq, turn, board, opponent) do
    if right?(castling, turn, side) and can_castle_pseudo?(side, turn, board, opponent) do
      target = if side == :kingside, do: king_sq + 2, else: king_sq - 2
      special = if side == :kingside, do: :kingside_castle, else: :queenside_castle
      [Move.pack(king_sq, target, nil, special) | acc]
    else
      acc
    end
  end

  defp can_castle_pseudo?(:kingside, :white, board, opponent) do
    (Board.all_occ(board) &&& Constants.white_ks_path()) == 0 and
      not Board.attacked?(board, 61, opponent) and not Board.attacked?(board, 62, opponent)
  end

  defp can_castle_pseudo?(:queenside, :white, board, opponent) do
    (Board.all_occ(board) &&& Constants.white_qs_path()) == 0 and
      not Board.attacked?(board, 59, opponent) and not Board.attacked?(board, 58, opponent)
  end

  defp can_castle_pseudo?(:kingside, :black, board, opponent) do
    (Board.all_occ(board) &&& Constants.black_ks_path()) == 0 and
      not Board.attacked?(board, 5, opponent) and not Board.attacked?(board, 6, opponent)
  end

  defp can_castle_pseudo?(:queenside, :black, board, opponent) do
    (Board.all_occ(board) &&& Constants.black_qs_path()) == 0 and
      not Board.attacked?(board, 3, opponent) and not Board.attacked?(board, 2, opponent)
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
    from = lsb(bb)
    bitboard_to_moves_to(bb &&& bb - 1, to, [Move.pack_plain(from, to) | acc])
  end

  defp bitboard_to_moves_from(0, _, acc), do: acc

  defp bitboard_to_moves_from(bb, from, acc) do
    to = lsb(bb)
    # from is loop-invariant here; plain pack skips both encode calls per target.
    bitboard_to_moves_from(bb &&& bb - 1, from, [Move.pack_plain(from, to) | acc])
  end

  # ── Piece accessor helpers ──

  defp ensure_tuple(board) when is_tuple(board), do: board
  defp ensure_tuple(board), do: Board.from_struct(board)

  defp get_occupancies(board, :white) do
    {elem(board, 12), elem(board, 13), elem(board, 14)}
  end

  defp get_occupancies(board, :black) do
    {elem(board, 13), elem(board, 12), elem(board, 14)}
  end

  defp get_king_bb(board, :white), do: elem(board, 5)
  defp get_king_bb(board, :black), do: elem(board, 11)

  defp get_pawns(board, :white), do: elem(board, 0)
  defp get_pawns(board, :black), do: elem(board, 6)

  defp get_knights(board, :white), do: elem(board, 1)
  defp get_knights(board, :black), do: elem(board, 7)

  defp get_bishops(board, :white), do: elem(board, 2)
  defp get_bishops(board, :black), do: elem(board, 8)

  defp get_rooks(board, :white), do: elem(board, 3)
  defp get_rooks(board, :black), do: elem(board, 9)

  defp get_queens(board, :white), do: elem(board, 4)
  defp get_queens(board, :black), do: elem(board, 10)

  defp get_slider_bb(board, :white, :bishop), do: elem(board, 2)
  defp get_slider_bb(board, :white, :rook), do: elem(board, 3)
  defp get_slider_bb(board, :white, :queen), do: elem(board, 4)
  defp get_slider_bb(board, :black, :bishop), do: elem(board, 8)
  defp get_slider_bb(board, :black, :rook), do: elem(board, 9)
  defp get_slider_bb(board, :black, :queen), do: elem(board, 10)

  defp get_slider_attacks(:bishop, from, all_bb), do: Magic.get_bishop_attacks(from, all_bb)
  defp get_slider_attacks(:rook, from, all_bb), do: Magic.get_rook_attacks(from, all_bb)

  defp get_slider_attacks(:queen, from, all_bb),
    do: Magic.get_bishop_attacks(from, all_bb) ||| Magic.get_rook_attacks(from, all_bb)

  defp get_piece_bb(board, :white, :pawn), do: elem(board, 0)
  defp get_piece_bb(board, :white, :knight), do: elem(board, 1)
  defp get_piece_bb(board, :white, :bishop), do: elem(board, 2)
  defp get_piece_bb(board, :white, :rook), do: elem(board, 3)
  defp get_piece_bb(board, :white, :queen), do: elem(board, 4)
  defp get_piece_bb(board, :white, :king), do: elem(board, 5)
  defp get_piece_bb(board, :black, :pawn), do: elem(board, 6)
  defp get_piece_bb(board, :black, :knight), do: elem(board, 7)
  defp get_piece_bb(board, :black, :bishop), do: elem(board, 8)
  defp get_piece_bb(board, :black, :rook), do: elem(board, 9)
  defp get_piece_bb(board, :black, :queen), do: elem(board, 10)
  defp get_piece_bb(board, :black, :king), do: elem(board, 11)
end
