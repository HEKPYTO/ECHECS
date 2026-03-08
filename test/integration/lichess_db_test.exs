defmodule Echecs.Integration.LichessDBTest do
  use ExUnit.Case

  alias Echecs.{Game, PGN}

  @moduledoc """
  Integration test that replays a local Lichess PGN dataset.
  """

  @tag :integration
  @tag timeout: 7_200_000
  test "processes local 2015-01 PGN file" do
    sample_size =
      case System.get_env("SAMPLE_SIZE") do
        nil -> 1_000_000
        value -> String.to_integer(value)
      end

    file_path =
      System.get_env("LICHESS_DB_PATH")
      |> case do
        nil -> Path.expand("lichess_db_standard_rated_2015-01.pgn.zst", File.cwd!())
        path -> Path.expand(path)
      end

    if File.exists?(file_path) do
      results =
        stream_pgn_from_file(file_path)
        |> Stream.take(sample_size)
        |> Task.async_stream(&test_game/1,
          max_concurrency: System.schedulers_online(),
          timeout: 30_000,
          ordered: false
        )
        |> Enum.reduce(%{total: 0, failed: 0, errors: []}, &reduce_result/2)

      assert results.failed == 0
    else
      IO.puts("Local file #{file_path} not found. Skipping test.")
      :ok
    end
  end

  @spec stream_pgn_from_file(String.t()) :: Enumerable.t()
  defp stream_pgn_from_file(path) do
    Stream.resource(
      fn ->
        cmd = "zstd -d -c -q \"#{path}\""
        port = Port.open({:spawn, "sh -c '#{cmd}'"}, [:binary, :exit_status])
        {port, ""}
      end,
      &next_chunk/1,
      &close_stream/1
    )
  end

  @spec test_game(String.t()) :: :ok | {:error, String.t(), term()}
  defp test_game(pgn) do
    case String.split(pgn, "\n\n", parts: 2) do
      [headers, moves_block] ->
        moves_list = PGN.parse_moves(moves_block)
        expected_result = extract_result(headers)

        try do
          case PGN.replay(Game.new(), moves_list) do
            %Game{} = game ->
              validate_final_state(game, moves_list, expected_result)

            {:error, reason, move, _state} ->
              {:error, "Replay failed: #{inspect(reason)} on move #{move}", pgn}

            _ ->
              {:error, "Unknown replay result", pgn}
          end
        rescue
          error ->
            {:error, "Crash: #{inspect(error)}", pgn}
        end

      _ ->
        :ok
    end
  end

  defp next_chunk({port, buffer}) do
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
        finalize_stream(buffer)
    end
  end

  defp finalize_stream(buffer) do
    if String.trim(buffer) != "" and String.contains?(buffer, "[Event ") do
      final =
        buffer
        |> String.split("[Event ")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&("[Event " <> &1))

      {final, {:closed, ""}}
    else
      {:halt, {:closed, ""}}
    end
  end

  defp close_stream({port, _}) when is_port(port) do
    if Port.info(port) do
      Port.close(port)
    end
  end

  defp close_stream(_), do: :ok

  defp extract_result(headers) do
    case Regex.run(~r/\[Result "(.*?)"\]/, headers) do
      [_, result] -> result
      _ -> nil
    end
  end

  defp validate_final_state(game, moves_list, _expected_result) do
    case List.last(moves_list) do
      nil ->
        :ok

      last_move_san ->
        if String.ends_with?(last_move_san, "#") and not Game.checkmate?(game) do
          {:error, "Expected checkmate (move #{last_move_san}) but game is not in checkmate",
           last_move_san}
        else
          :ok
        end
    end
  end

  defp reduce_result({:ok, :ok}, acc) do
    %{acc | total: acc.total + 1}
  end

  defp reduce_result({:ok, {:error, reason, context}}, acc) do
    %{
      acc
      | total: acc.total + 1,
        failed: acc.failed + 1,
        errors: [{reason, context} | acc.errors]
    }
  end
end
