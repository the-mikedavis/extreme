defmodule Extreme.Messages do
  @moduledoc """
  Messages that may be sent to or received from the EventStore

  Communication with the EventStore is accomplished via Protocol Buffers.

  Messages are based on the [official proto
  file](https://github.com/EventStore/EventStore/blob/master/src/Protos/ClientAPI/ClientMessageDtos.proto)
  along with the `ReadStreamEventsBackward` message (which works but is missing
  from their proto file).
  """

  # turns off the documentation for `defs/0`
  @doc false

  use Protobuf,
    from: Path.expand("../../include/event_store.proto", __DIR__),
    use_package_names: true
end
