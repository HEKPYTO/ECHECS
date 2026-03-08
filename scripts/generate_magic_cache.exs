Code.require_file(Path.expand("../lib/echecs/bitboard/constants.ex", __DIR__))
Code.require_file(Path.expand("../lib/echecs/bitboard/helper.ex", __DIR__))
Code.require_file(Path.expand("../lib/echecs/bitboard/magic_generator.ex", __DIR__))

path = Path.expand("../priv/magic_cache.bin", __DIR__)
data = Echecs.Bitboard.MagicGenerator.find_all_magics()

File.mkdir_p!(Path.dirname(path))
File.write!(path, :erlang.term_to_binary(data))

IO.puts("Wrote #{path}")
