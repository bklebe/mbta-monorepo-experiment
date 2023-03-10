defmodule Trike.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    listen_port = Application.get_env(:trike, :listen_port)
    kinesis_client = Application.get_env(:trike, :kinesis_client)
    kinesis_stream = Application.get_env(:trike, :kinesis_stream)

    Logger.info(
      "Starting Trike on port #{inspect(listen_port)} proxying to #{kinesis_stream} (#{inspect(kinesis_client)})"
    )

    listener_ref = make_ref()

    children = [
      :ranch.child_spec(
        listener_ref,
        :ranch_tcp,
        [port: listen_port],
        Trike.Proxy,
        stream: kinesis_stream,
        kinesis_client: kinesis_client,
        clock: Application.get_env(:trike, :clock)
      ),
      {Trike.HealthChecker, [ranch_ref: listener_ref]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
