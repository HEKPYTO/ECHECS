defmodule Echecs.Bitboard.Magic do
  @moduledoc """
  Magic bitboard lookups for sliding piece attacks.
  """

  import Bitwise

  @cache_file_path Path.expand("../../../priv/magic_cache.bin", __DIR__)
  @external_resource @cache_file_path

  magic_data =
    if File.exists?(@cache_file_path) do
      @cache_file_path
      |> File.read!()
      |> :erlang.binary_to_term()
    else
      raise """
      Missing magic cache at #{@cache_file_path}.

      Generate it explicitly with:

          elixir scripts/generate_magic_cache.exs
      """
    end

  rooks =
    magic_data.rook
    |> Enum.sort_by(fn %{sq: sq} -> sq end)

  bishops =
    magic_data.bishop
    |> Enum.sort_by(fn %{sq: sq} -> sq end)

  @doc """
  Initializes the module for compatibility with older startup code.
  """
  @spec init() :: :ok
  def init, do: :ok

  @compile {:inline, get_rook_attacks: 2, get_bishop_attacks: 2}

  for %{sq: sq, mask: mask, magic: magic, shift: shift, table: table} <- rooks do
    table_tuple = for <<a::64-little <- table>>, do: a
    table_tuple = List.to_tuple(table_tuple)

    if tuple_size(table_tuple) != 1 <<< (64 - shift) do
      raise "magic table size mismatch (rook sq #{sq}): got #{tuple_size(table_tuple)}, expected #{1 <<< (64 - shift)}"
    end

    table_esc = Macro.escape(table_tuple)

    def get_rook_attacks(unquote(sq), occupancy) do
      idx =
        ((occupancy &&& unquote(mask)) * unquote(magic) &&& 0xFFFFFFFFFFFFFFFF) >>> unquote(shift)

      elem(unquote(table_esc), idx)
    end
  end

  for %{sq: sq, mask: mask, magic: magic, shift: shift, table: table} <- bishops do
    table_tuple = for <<a::64-little <- table>>, do: a
    table_tuple = List.to_tuple(table_tuple)

    if tuple_size(table_tuple) != 1 <<< (64 - shift) do
      raise "magic table size mismatch (bishop sq #{sq}): got #{tuple_size(table_tuple)}, expected #{1 <<< (64 - shift)}"
    end

    table_esc = Macro.escape(table_tuple)

    def get_bishop_attacks(unquote(sq), occupancy) do
      idx =
        ((occupancy &&& unquote(mask)) * unquote(magic) &&& 0xFFFFFFFFFFFFFFFF) >>> unquote(shift)

      elem(unquote(table_esc), idx)
    end
  end
end
