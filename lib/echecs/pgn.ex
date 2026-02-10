defmodule Echecs.PGN do
  @moduledoc """
  Simple PGN parser and replayer for testing against Lichess DB.
  """

  alias Echecs.{Board, Game, MoveGen}

  @doc """
  Parses a PGN move text (e.g., "1. e4 c5 2. Nf3") into a list of algebraic moves.
  """
  def parse_moves(pgn_body) do
    pgn_body
    |> String.replace(~r/\{.*?\}/, "")
    |> String.replace(~r/\(.*\)/, "")
    |> String.replace(~r/\d+\.+/, "")
    |> String.replace(~r/(1-0|0-1|1\/2-1\/2|\*)/, "")
    |> String.replace(~r/[\?!]+/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split(" ")
    |> Enum.filter(fn s -> s != "" end)
  end

  @doc """
  Replays a game from a list of algebraic moves starting from the given game state.
  """
  def replay(game, moves) do
    Enum.reduce_while(moves, game, fn san, current_game ->
      case move_from_san(current_game, san) do
        {:ok, move} ->
          new_game = Game.make_move(current_game, move)
          {:cont, new_game}

        {:error, reason} ->
          {:halt, {:error, reason, san, current_game}}
      end
    end)
  end

  def move_from_san(game, san) do
    san = String.replace(san, "+", "") |> String.replace("#", "")

    cond do
      san == "O-O" ->
        find_castling_move(game, :kingside_castle)

      san == "O-O-O" ->
        find_castling_move(game, :queenside_castle)

      true ->
        parse_standard_san(game, san)
    end
  end

  defp find_castling_move(game, type) do
    moves = MoveGen.pseudo_legal_moves(game)
    move = Enum.find(moves, fn m -> m.special == type end)

    if move, do: {:ok, move}, else: {:error, :illegal_castling}
  end

  defp parse_standard_san(game, san) do
    regex = ~r/^([NBRQK])?([a-h1-8]{0,2})?(x)?([a-h][1-8])(=[NBRQ])?$/

    case Regex.run(regex, san) do
      [_, piece_char, disambig, _capture, target_str | rest] ->
        promo_str = List.first(rest) || ""

        piece_type =
          if piece_char == "",
            do: :pawn,
            else: Echecs.Piece.type_from_char(String.to_charlist(piece_char) |> hd())

        target_idx = Board.to_index(target_str)

        promotion =
          if promo_str != "",
            do:
              Echecs.Piece.type_from_char(
                String.to_charlist(String.replace(promo_str, "=", ""))
                |> hd()
              ),
            else: nil

        find_move(game, piece_type, target_idx, disambig, promotion)

      nil ->
        {:error, :invalid_san_format}
    end
  end

  defp find_move(game, piece_type, target_idx, disambig, promotion) do
    moves = MoveGen.pseudo_legal_moves(game)

    candidates =
      Enum.filter(moves, fn m ->
        m.to == target_idx and
          m.promotion == promotion and
          match_piece_type?(game.board, m.from, piece_type, game.turn) and
          match_disambiguation?(m.from, disambig)
      end)

    valid_candidates =
      Enum.filter(candidates, fn m -> Echecs.Game.verify_move(game, m) end)

    case valid_candidates do
      [move] -> {:ok, move}
      [] -> {:error, :no_move_found}
      _ -> {:error, :ambiguous_move}
    end
  end

  defp match_piece_type?(board, idx, type, color) do
    case Board.at(board, idx) do
      {^color, ^type} -> true
      _ -> false
    end
  end

  defp match_disambiguation?(_, ""), do: true

  defp match_disambiguation?(from_idx, disambig) do
    file_char = ?a + rem(from_idx, 8)
    rank_char = ?8 - div(from_idx, 8)

    if String.length(disambig) == 1 do
      char = String.to_charlist(disambig) |> hd()
      char == file_char or char == rank_char
    else
      to_str = Board.to_algebraic(from_idx)
      String.contains?(to_str, disambig)
    end
  end
end
