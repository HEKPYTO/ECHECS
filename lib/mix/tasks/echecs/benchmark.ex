defmodule Mix.Tasks.Echecs.Benchmark do
  @shortdoc "Runs deterministic engine benchmarks"
  @moduledoc """
  Runs deterministic benchmarks for move generation, perft, PGN replay, and hashing.
  """

  use Mix.Task

  alias Echecs.{Board, Game, MoveGen, Perft, PGN, Zobrist}

  require Echecs.Move

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          samples: :integer,
          start_depth: :integer,
          kiwipete_depth: :integer
        ]
      )

    samples = Keyword.get(opts, :samples, 5)
    start_depth = Keyword.get(opts, :start_depth, 5)
    kiwipete_depth = Keyword.get(opts, :kiwipete_depth, 4)

    Mix.Task.run("app.start")

    datasets = benchmark_datasets(start_depth, kiwipete_depth)

    IO.puts("benchmark=suite samples=#{samples}")

    run_benchmark("movegen_start", samples, fn -> MoveGen.legal_moves_int(datasets.start_game) end)

    run_benchmark("movegen_kiwipete", samples, fn ->
      MoveGen.legal_moves_int(datasets.kiwipete_game)
    end)

    run_benchmark("perft_start", samples, fn -> Perft.perft(datasets.start_game, start_depth) end)

    run_benchmark("perft_kiwipete", samples, fn ->
      Perft.perft(datasets.kiwipete_game, kiwipete_depth)
    end)

    run_benchmark("pgn_replay", samples, fn ->
      PGN.replay(Game.new(), datasets.pgn_moves)
    end)

    run_benchmark("hash_incremental", samples, fn ->
      Enum.each(datasets.hash_transitions, &apply_incremental_hash/1)
      :ok
    end)

    run_benchmark("hash_full", samples, fn ->
      Enum.each(datasets.hash_states, fn state ->
        Zobrist.hash(state.board, state.turn, state.castling, state.en_passant)
      end)

      :ok
    end)
  end

  defp benchmark_datasets(start_depth, kiwipete_depth) do
    start_game = Game.new()

    kiwipete_game =
      Game.new("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")

    pgn_moves =
      PGN.parse_moves(
        "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O"
      )

    {hash_transitions, hash_states} = hash_benchmark_data(pgn_moves)

    %{
      start_game: start_game,
      kiwipete_game: kiwipete_game,
      pgn_moves: pgn_moves,
      hash_transitions: hash_transitions,
      hash_states: hash_states,
      start_depth: start_depth,
      kiwipete_depth: kiwipete_depth
    }
  end

  defp hash_benchmark_data(moves) do
    {transitions, states, _game} =
      Enum.reduce(moves, {[], [], Game.new()}, fn san, {acc_transitions, acc_states, game} ->
        {:ok, move} = PGN.move_from_san(game, san)
        packed = Echecs.Move.pack(move.from, move.to, move.promotion, move.special)
        next_game = Game.make_move_int(game, packed)
        piece = Board.at(game.board, move.from)
        target_piece = Board.at(game.board, move.to)

        transition = %{
          current_hash: game.zobrist_hash,
          from: move.from,
          to: move.to,
          promotion: move.promotion,
          special: move.special,
          piece: piece,
          target_piece: target_piece,
          castling: {game.castling, next_game.castling},
          en_passant: {game.en_passant, next_game.en_passant},
          turn: game.turn
        }

        {[transition | acc_transitions], [next_game | acc_states], next_game}
      end)

    {Enum.reverse(transitions), Enum.reverse(states)}
  end

  defp apply_incremental_hash(%{
         current_hash: current_hash,
         from: from,
         to: to,
         promotion: promotion,
         special: special,
         piece: piece,
         target_piece: target_piece,
         castling: castling,
         en_passant: en_passant,
         turn: turn
       }) do
    Zobrist.update_hash_int(
      current_hash,
      from,
      to,
      promotion,
      special,
      piece,
      target_piece,
      castling,
      en_passant,
      turn
    )
  end

  defp run_benchmark(label, samples, fun) do
    results =
      for _ <- 1..samples do
        {time_us, result} = :timer.tc(fun)
        %{time_us: time_us, result: result}
      end

    best = Enum.min_by(results, & &1.time_us)
    avg_us = div(Enum.reduce(results, 0, fn sample, acc -> acc + sample.time_us end), samples)

    output =
      case benchmark_value(label, best.result, best.time_us) do
        nil -> ""
        value -> " #{value}"
      end

    IO.puts(
      "benchmark=#{label} samples=#{samples} best_us=#{best.time_us} avg_us=#{avg_us} result=#{format_result(label, best.result)}#{output}"
    )
  end

  defp benchmark_value("perft_start", nodes, time_us), do: throughput_fragment(nodes, time_us)
  defp benchmark_value("perft_kiwipete", nodes, time_us), do: throughput_fragment(nodes, time_us)
  defp benchmark_value(_, _result, _time_us), do: nil

  defp format_result(label, result) when label in ["movegen_start", "movegen_kiwipete"] do
    Integer.to_string(length(result))
  end

  defp format_result("pgn_replay", %Game{fullmove: fullmove}), do: Integer.to_string(fullmove)
  defp format_result(_label, result), do: inspect(result)

  defp throughput_fragment(nodes, time_us) do
    nps = trunc(nodes * 1_000_000 / max(time_us, 1))
    "nps=#{nps}"
  end
end
