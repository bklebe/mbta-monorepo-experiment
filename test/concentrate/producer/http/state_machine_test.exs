defmodule Concentrate.Producer.HTTP.StateMachineTest do
  @moduledoc false
  use ExUnit.Case, async: true
  import Concentrate.Producer.HTTP.StateMachine
  import ExUnit.CaptureLog

  describe "message/2" do
    test "does not log an error on :closed errors" do
      machine = init("url", [])

      for reason <- [:closed, {:closed, :timeout}] do
        error = %HTTPoison.Error{reason: reason}

        log =
          capture_log([level: :error], fn ->
            _ = message(machine, error)
          end)

        assert log == ""
      end
    end

    test "does log other errors" do
      machine = init("url", [])
      error = %HTTPoison.Error{reason: :unknown_error}

      log =
        capture_log([level: :error], fn ->
          _ = message(machine, error)
        end)

      assert log =~ ":unknown_error"
    end

    test "logs a error if we have't gotten content since a timeout" do
      opts = [content_warning_timeout: 0]

      messages = [
        %HTTPoison.AsyncStatus{code: 200},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncChunk{chunk: "body"},
        %HTTPoison.AsyncEnd{},
        fn -> :timer.sleep(5) end,
        %HTTPoison.AsyncStatus{code: 304},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncEnd{}
      ]

      log =
        capture_log([level: :error], fn ->
          _ = run_machine("url", opts, messages)
        end)

      assert log =~ ~s("url")
      assert log =~ "has not been updated in"
    end

    test "does not log multiple warnings after the first timeout" do
      opts = [content_warning_timeout: 5]

      messages = [
        %HTTPoison.AsyncStatus{code: 200},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncChunk{chunk: "body"},
        %HTTPoison.AsyncEnd{},
        fn -> :timer.sleep(10) end,
        %HTTPoison.AsyncStatus{code: 304},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncEnd{},
        %HTTPoison.AsyncStatus{code: 304},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncEnd{}
      ]

      log =
        capture_log([level: :error], fn ->
          _ = run_machine("url", opts, messages)
        end)

      # only one message (some content before, some content after)
      assert [_, _] = String.split(log, "[error]")
    end

    test "receiving the same body twice does not send a second message" do
      messages = [
        %HTTPoison.AsyncStatus{code: 200},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncChunk{chunk: "body"},
        %HTTPoison.AsyncEnd{},
        %HTTPoison.AsyncStatus{code: 200},
        %HTTPoison.AsyncHeaders{headers: []},
        %HTTPoison.AsyncChunk{chunk: "body"},
        %HTTPoison.AsyncEnd{}
      ]

      {_machine, bodies, _messages} = run_machine("url", [], messages)

      assert bodies == []
    end
  end

  defp run_machine(url, opts, messages) do
    machine = init(url, opts)
    initial = {machine, [], []}

    Enum.reduce(messages, initial, fn message, {machine, _, _} ->
      case message do
        fun when is_function(fun, 0) ->
          fun.()
          {machine, [], []}

        message ->
          message(machine, message)
      end
    end)
  end
end
