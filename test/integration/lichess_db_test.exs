defmodule Echecs.Integration.LichessDBTest do
  use ExUnit.Case
  alias Echecs.{Game, PGN}

  @moduledoc """
  Integration test that processes a specific local Lichess database file.
  This ensures the engine can handle real-world games from a large dataset
  without crashing or flagging valid moves as illegal.
  """

  @tag :integration
  # 2 hours
  @tag timeout: 7_200_000
  test "processes local 2015-01 PGN file" do
    # Allow configuring file path via env var for CI
    default_file = "lichess_db_standard_rated_2015-01.pgn.zst"
    env_file = System.get_env("LICHESS_DB_PATH")

    file_path =
      if env_file, do: Path.expand(env_file), else: Path.expand(default_file, File.cwd!())

    if File.exists?(file_path) do
      IO.puts("Found local file: #{file_path}")
      IO.puts("Starting processing... (This may take a while)")

      env_sample = System.get_env("SAMPLE_SIZE")
      sample_size = if env_sample, do: String.to_integer(env_sample), else: 1_000_000

      IO.puts("Processing sample of #{sample_size} games...")

      results =
        stream_pgn_from_file(file_path)
        |> Stream.take(sample_size)
        |> Task.async_stream(&test_game/1,
          max_concurrency: System.schedulers_online(),
          timeout: 30_000,
          ordered: false
        )
        |> Enum.reduce(%{total: 0, failed: 0, errors: []}, fn {:ok, result}, acc ->
          case result do
            :ok ->
              if rem(acc.total + 1, 10_000) == 0, do: IO.write(".")

              if rem(acc.total + 1, 100_000) == 0,
                do: IO.puts(" #{acc.total + 1} games processed")

              %{acc | total: acc.total + 1}

            {:error, reason, context} ->
              IO.puts("\nFailed: #{reason}")
              IO.puts("Context: #{String.slice(inspect(context), 0, 100)}...")

              %{
                acc
                | total: acc.total + 1,
                  failed: acc.failed + 1,
                  errors: [{reason, context} | acc.errors]
              }
          end
        end)

      IO.puts("\nFinished processing #{file_path}")
      IO.puts("Total: #{results.total}, Failed: #{results.failed}")
      assert results.failed == 0
    else
      IO.puts("Local file #{file_path} not found. Skipping test.")
      :ok
    end
  end

  # Streams games from a zstd compressed file
  defp stream_pgn_from_file(path) do
    Stream.resource(
      fn ->
        # Decompress using zstd to stdout
        cmd = "zstd -d -c -q \"#{path}\""
        port = Port.open({:spawn, "sh -c '#{cmd}'"}, [:binary, :exit_status])
        {port, ""}
      end,
      fn {port, buffer} ->
        receive do
          {^port, {:data, data}} ->
            new_buffer = buffer <> data
            games = String.split(new_buffer, "[Event ")

            if length(games) > 1 do
              {complete_games, [incomplete]} = Enum.split(games, -1)

              formatted =
                complete_games
                |> Enum.reject(&(&1 == ""))
                |> Enum.map(&("[Event " <> &1))

              {formatted, {port, "[Event " <> incomplete}}
            else
              {[], {port, new_buffer}}
            end

          {^port, {:exit_status, _}} ->
            if String.trim(buffer) != "" and String.contains?(buffer, "[Event ") do
              parts = String.split(buffer, "[Event ")

              final =
                parts
                |> Enum.reject(&(&1 == ""))
                |> Enum.map(&("[Event " <> &1))

              {final, {:closed, ""}}
            else
              {:halt, {:closed, ""}}
            end
        end
      end,
      fn {port, _} ->
        if is_port(port) do
          try do
            Port.close(port)
          rescue
            ArgumentError -> :ok
          end
        end
      end
    )
  end

  defp test_game(pgn) do
    parts = String.split(pgn, "\n\n", parts: 2)

    case parts do
      [headers, moves_block] ->
        moves_list = PGN.parse_moves(moves_block)

        expected_result =
          case Regex.run(~r/\[Result "(.*?)"\]/, headers) do
            [_, res] -> res
            _ -> nil
          end

        try do
          # Replay the game move by move
          result_game = PGN.replay(Game.new(), moves_list)

          case result_game do
            %Game{} = game ->
              validate_final_state(game, moves_list, expected_result)

            {:error, reason, move, _state} ->
              {:error, "Replay failed: #{inspect(reason)} on move #{move}", pgn}

            _ ->
              {:error, "Unknown replay result", pgn}
          end
        rescue
          e -> {:error, "Crash: #{inspect(e)}", pgn}
        end

      _ ->
        :ok
    end
  end

  defp validate_final_state(game, moves_list, _expected_result) do
    last_move_san = List.last(moves_list)

    if last_move_san && String.ends_with?(last_move_san, "#") do
      if Game.checkmate?(game) do
        :ok
      else
        {:error, "Expected checkmate (move #{last_move_san}) but game is not in checkmate",
         last_move_san}
      end
    else
      :ok
    end
  end
end
