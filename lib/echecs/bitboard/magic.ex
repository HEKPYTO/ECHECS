defmodule Echecs.Bitboard.Magic do
  @moduledoc """
  Magic Bitboard implementation for fast sliding piece attacks.
  Uses pre-computed attack tables stored in :persistent_term for speed.
  """
  import Bitwise

  alias Echecs.Bitboard.MagicGenerator

  @table_key :magic_tables
  @cache_file_path "priv/magic_cache.bin"

  @doc """
  Initialize magic tables. Should be called at app startup.
  """
  def init do
    data = load_or_generate_magics()

    rooks =
      data.rook
      |> Enum.sort_by(fn %{sq: sq} -> sq end)
      |> Enum.map(fn %{mask: mask, magic: magic, shift: shift, table: table} ->
        {mask, magic, shift, table}
      end)
      |> List.to_tuple()

    bishops =
      data.bishop
      |> Enum.sort_by(fn %{sq: sq} -> sq end)
      |> Enum.map(fn %{mask: mask, magic: magic, shift: shift, table: table} ->
        {mask, magic, shift, table}
      end)
      |> List.to_tuple()

    :persistent_term.put(@table_key, {rooks, bishops})
    :ok
  end

  defp load_or_generate_magics do
    path = Path.expand(@cache_file_path, File.cwd!())

    if File.exists?(path) do
      IO.puts("Loading magic numbers from cache: #{path}")
      path |> File.read!() |> :erlang.binary_to_term()
    else
      IO.puts("Generating magic numbers (this may take a while)...")
      data = MagicGenerator.find_all_magics()

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, :erlang.term_to_binary(data))
      IO.puts("Magic numbers cached to #{path}")

      data
    end
  end

  @doc """
  Get rook attacks for a square given occupancy.
  """
  def get_rook_attacks(sq, occupancy) do
    {rooks, _} = :persistent_term.get(@table_key)

    {mask, magic, shift, table} = elem(rooks, sq)

    idx = ((occupancy &&& mask) * magic &&& 0xFFFFFFFFFFFFFFFF) >>> shift

    offset = idx * 8
    <<attacks::64-little-integer>> = :binary.part(table, offset, 8)

    attacks
  end

  @doc """
  Get bishop attacks for a square given occupancy.
  """
  def get_bishop_attacks(sq, occupancy) do
    {_, bishops} = :persistent_term.get(@table_key)

    {mask, magic, shift, table} = elem(bishops, sq)

    idx = ((occupancy &&& mask) * magic &&& 0xFFFFFFFFFFFFFFFF) >>> shift

    offset = idx * 8
    <<attacks::64-little-integer>> = :binary.part(table, offset, 8)

    attacks
  end
end
