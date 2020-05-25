defmodule Extreme.FanoutListener do
  @moduledoc ~S"""
  A macro for writing listeners which subscribe only to new events

  Modules that use this listener will connect to a stream and wait for new
  events only. This is in contrast to `Extreme.Listener` which will read
  existing events (starting from an arbitrary position) and then keep listening
  to new events once caught-up.

  This is similar in behavior to RabbitMQ's fanout exchange, hence the name.

  It's not uncommon situation to listen live events and propagate them (for
  example on web sockets). For that situation, use the `Extreme.FanoutListener`
  macro:

      defmodule MyApp.MyFanoutListener do
        use Extreme.FanoutListener
        import MyApp.MyPusher

        defp process_push(push) do
          Logger.info "Forward to web socket event #{inspect push.event.event_type}"
          :ok = push.event.data
                 |> :erlang.binary_to_term
                 |> process_event(push.event.event_type)
        end
      end

      defmodule MyApp.MyPusher do
        def process_event(data, "Elixir.MyApp.Events.PersonCreated") do
          Logger.debug "Transform and push event with data: #{inspect data}"
          :ok
        end
        def process_event(_, _), do: :ok # Just acknowledge events we are not interested in
      end

  Listener can be started manually but it is most common to place it in a
  supervision tree _after_ specifying an Extreme client module:

      defmodule MyApp.Supervisor do
        use Supervisor

        def start_link, do: Supervisor.start_link __MODULE__, :ok

        @event_store MyApp.EventStore

        def init(:ok) do
          event_store_settings = Application.get_env :my_app, :event_store
      
          children = [
            {MyExtreme, [event_store_settings]},
            {MyApp.MyFanoutListener, [MyExtreme, "my_indexed_stream", [name: MyFanoutListener]]},
            # ... other workers / supervisors
          ]

          Supervisor.init children, strategy: :one_for_one
        end
      end

  The listener can temporary unsubscribe from the stream:

      :ok = MyApp.MyFanoutListener.unsubscribe(MyFanoutListener)

  ... and resubscribe again:

      :ok = MyApp.MyFanoutListener.resubscribe(MyFanoutListener)
  """
  defmacro __using__(_) do
    quote do
      use GenServer
      require Logger

      def child_spec(args) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, args}
        }
      end

      def start_link(extreme, stream_name, opts \\ []),
        do: GenServer.start_link(__MODULE__, {extreme, stream_name}, opts)

      def resubscribe(server), do: GenServer.call(server, :resubscribe)

      def unsubscribe(server), do: GenServer.call(server, :unsubscribe)

      @impl true
      def init({extreme, stream_name}) do
        state = %{
          extreme: extreme,
          subscription: nil,
          subscription_ref: nil,
          stream_name: stream_name
        }

        GenServer.cast(self(), :subscribe)
        {:ok, state}
      end

      @impl true
      def handle_call(:resubscribe, from, state) do
        {:ok, subscription, ref} = _subscribe(state)
        {:reply, :ok, %{state | subscription: subscription, subscription_ref: ref}}
      end

      def handle_call(:unsubscribe, from, state) do
        true = Process.demonitor(state.subscription_ref)
        :unsubscribed = state.extreme.unsubscribe(state.subscription)
        {:reply, :ok, %{state | subscription: nil, subscription_ref: nil}}
      end

      @impl true
      def handle_cast(:subscribe, state) do
        {:ok, subscription, ref} = _subscribe(state)
        Logger.debug("Subscription created: #{inspect({subscription, ref})}")
        {:noreply, %{state | subscription: subscription, subscription_ref: ref}}
      end

      @impl true
      def handle_info({:DOWN, ref, :process, _pid, _reason}, %{subscription_ref: ref} = state) do
        reconnect_delay = 1_000
        Logger.warn("Subscription to EventStore is down. Will retry in #{reconnect_delay} ms.")
        :timer.sleep(reconnect_delay)
        GenServer.cast(self(), :subscribe)
        {:noreply, state}
      end

      def handle_call({:on_event, push}, _from, state) do
        :ok = process_push(push)
        {:reply, :ok, state}
      end

      def handle_info(_msg, state), do: {:noreply, state}

      defp _subscribe(%{subscription: nil, subscription_ref: nil} = state) do
        Logger.debug("There's no active subscription")
        {:ok, subscription} = state.extreme.subscribe_to(state.stream_name, self())
        ref = Process.monitor(subscription)
        {:ok, subscription, ref}
      end

      defp _subscribe(state), do: {:ok, state.subscription, state.ref}
    end
  end
end
