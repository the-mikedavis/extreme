defmodule Extreme do
  @moduledoc """
  An EventStore client library

  TODO
  """

  @typedoc false
  @type t :: module

  @doc false
  defmacro __using__(opts \\ []) do
    quote do
      @otp_app Keyword.get(unquote(opts), :otp_app, :extreme)

      defp _default_config,
        do: Application.get_env(@otp_app, __MODULE__)

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(config \\ [])
      def start_link([]), do: Extreme.Supervisor.start_link(__MODULE__, _default_config())
      def start_link(config), do: Extreme.Supervisor.start_link(__MODULE__, config)

      def ping,
        do: Extreme.RequestManager.ping(__MODULE__, Extreme.Tools.generate_uuid())

      def execute(message, correlation_id \\ nil, timeout \\ 5_000) do
        Extreme.RequestManager.execute(
          __MODULE__,
          message,
          correlation_id || Extreme.Tools.generate_uuid(),
          timeout
        )
      end

      def subscribe_to(stream, subscriber, resolve_link_tos \\ true, ack_timeout \\ 5_000)
          when is_binary(stream) and is_pid(subscriber) and is_boolean(resolve_link_tos) do
        Extreme.RequestManager.subscribe_to(
          __MODULE__,
          stream,
          subscriber,
          resolve_link_tos,
          ack_timeout
        )
      end

      def read_and_stay_subscribed(
            stream,
            subscriber,
            from_event_number \\ 0,
            per_page \\ 1_000,
            resolve_link_tos \\ true,
            require_master \\ false,
            ack_timeout \\ 5_000
          )
          when is_binary(stream) and is_pid(subscriber) and is_boolean(resolve_link_tos) and
                 is_boolean(require_master) and from_event_number > -2 and per_page >= 0 and
                 per_page <= 4096 do
        Extreme.RequestManager.read_and_stay_subscribed(
          __MODULE__,
          subscriber,
          {stream, from_event_number, per_page, resolve_link_tos, require_master, ack_timeout}
        )
      end

      def unsubscribe(subscription) when is_pid(subscription),
        do: Extreme.Subscription.unsubscribe(subscription)

      def connect_to_persistent_subscription(
            subscriber,
            stream,
            group,
            allowed_in_flight_messages
          ) do
        Extreme.RequestManager.connect_to_persistent_subscription(
          __MODULE__,
          subscriber,
          stream,
          group,
          allowed_in_flight_messages
        )
      end
    end
  end

  @doc """
  Starts an extreme connection

  Typically, extreme connections are started as part of a supervision tree

      def start(_type, _args) do
        config = Application.fetch_env!(:my_app, MyExtremeClientModule)

        children = [
          {MyExtremeClientModule, config}
        ]

        Supervisor.start_link(children, strategy: :one_for_one)
      end

  But if this is undesirable, connections may be started like so

      iex> config = Application.fetch_env!(:my_app, MyExtremeClientModule)
      iex> MyExtremeClientModule.start_link(config)
  """
  @callback start_link(config :: Keyword.t(), opts :: Keyword.t()) ::
              {:ok, pid}
              | {:error, {:already_started, pid}}
              | {:error, term}

  @doc """
  Sends a message to the EventStore and synchronously awaits a response

  Communication between the client and the server is done with Protocol
  Buffers. See `Extreme.Messages` for more information.

  If unspecified, the `correlation_id` defaults to a new UUID and the `timeout`
  defaults to `5_000` ms (5 seconds).

  ## Examples

      iex> Extreme.Messages.CreatePersistentSubscription.new(
      ...>   buffer_size: 500,
      ...>   subscriber_max_count: 1,
      ...>   prefer_round_robin: true,
      ...>   event_stream_id: "my_stream_name",
      ...>   live_buffer_size: 500,
      ...>   max_retry_count: 10,
      ...>   message_timeout_milliseconds: 10_000,
      ...>   read_batch_size: 20,
      ...>   resolve_link_tos: true,
      ...>   start_from: 0,
      ...>   subscription_group_name: "my_subscription_group",
      ...>   record_statistics: false,
      ...>   checkpoint_after_time: 1_000,
      ...>   checkpoint_max_count: 500,
      ...>   checkpoint_min_count: 1
      ...> ) |> MyExtremeClient.execute()
      {:ok, %Extreme.Messages.CreatePersistentSubscriptionCompleted{result: :success, reason: ""}}
  """
  @callback execute(message :: struct(), correlation_id :: binary(), timeout :: integer()) ::
              term()

  @doc """
  Spawns a generic subscription

  See `Extreme.Subscription` for more information.

  ## Examples

      iex> MyExtremeClientModule.subscribe_to("my_stream_of_events", self(), true, 5_000)
      {:ok, #PID<1.2.3>}
  """
  @callback subscribe_to(
              stream :: String.t(),
              subscriber :: pid(),
              resolve_link_tos :: boolean(),
              ack_timeout :: integer()
            ) :: {:ok, pid}

  @doc """
  Unsubscribes and terminates a subscription process

  ## Examples

      iex> {:ok, subscription_pid} =
      ...>   MyExtremeClientModule.connect_to_persistent_subscription(
      ...>     self(),
      ...>     "my_stream_of_events",
      ...>     "my_subscription_group",
      ...>     1
      ...>   )
      {:ok, #PID<1.2.3>}
      iex> MyExtremeClientModule.unsubscribe(subscription_pid)
      :unsubscribed

  """
  @callback unsubscribe(subscription :: pid()) :: :unsubscribed

  @doc """
  Spawns a reading-style subscription

  See `Extreme.ReadingSubscription` for full details.

  ## Examples

      iex> MyExtremeClientModule.read_and_stay_subscribed(
      ...>   "my_stream_of_events",
      ...>   self(),
      ...>   0,
      ...>   100,
      ...>   true,
      ...>   false
      ...> )
      {:ok, #PID<1.2.3>}
  """
  @callback read_and_stay_subscribed(
              stream :: String.t(),
              subscriber :: pid(),
              from_event_number :: integer(),
              per_page :: integer(),
              resolve_link_tos :: boolean(),
              require_master :: boolean()
            ) :: {:ok, pid()}

  @doc """
  Pings the connected EventStore and should return `:pong` back

  This function provides a simple sanity-check to determine if a client
  module is currently connected to an EventStore.

  ## Examples

      iex> MyExtremeClientModule.ping
      :pong
  """
  @callback ping() :: :pong

  @doc """
  Spawns a persistent subscription

  The persistent subscription will send events to the `subscriber` process in
  the form of `GenServer.cast/2`s in the shape of `{:on_event, event,
  correlation_id}`.

  See `Extreme.PersistentSubscription` for full details.

  ## Examples

      iex> MyExtremeClientModule.connect_to_persistent_subscription(
      ...>   self(),
      ...>   "my_stream_of_events",
      ...>   "my_subscription_group",
      ...>   1
      ...> )
      {:ok, #PID<1.2.3>}
  """
  @callback connect_to_persistent_subscription(
              subscriber :: pid(),
              stream :: String.t(),
              group :: String.t(),
              allowed_in_flight_messages :: integer()
            ) :: {:ok, pid()}
end
