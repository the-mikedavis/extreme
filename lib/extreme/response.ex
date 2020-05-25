defmodule Extreme.Response do
  require Logger

  @moduledoc false

  def get_correlation_id(<<_message_type, _auth, correlation_id::16-binary, _data::binary>>),
    do: correlation_id

  def parse(<<message_type, auth, correlation_id::16-binary, data::binary>>) do
    case Extreme.MessageResolver.decode_cmd(message_type) do
      :not_authenticated ->
        {:error, :not_authenticated, correlation_id}

      :heartbeat_request_command ->
        {:heartbeat_request, correlation_id}

      :pong ->
        {:pong, correlation_id}

      :client_identified ->
        {:client_identified, correlation_id}

      :bad_request ->
        {:error, :bad_request, correlation_id}

      response_struct ->
        data = response_struct.decode(data)
        {auth, correlation_id, data}
    end
  end

  def reply(%{result: error} = msg, _correlation_id) when error != :success,
    do: {:error, error, msg}

  def reply(response, _correlation_id), do: {:ok, response}
end
