defmodule Extreme.SubscriptionsSupervisor do
  use DynamicSupervisor
  alias Extreme.{Subscription, ReadingSubscription, PersistentSubscription}

  @moduledoc false

  def _name(base_name),
    do: Module.concat(base_name, SubscriptionsSupervisor)

  def start_link(base_name),
    do: DynamicSupervisor.start_link(__MODULE__, :ok, name: _name(base_name))

  def init(:ok),
    do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_subscription(
        base_name,
        correlation_id,
        subscriber,
        stream,
        resolve_link_tos,
        ack_timeout \\ 5_000
      ) do
    base_name
    |> _name()
    |> DynamicSupervisor.start_child(%{
      id: Subscription,
      start:
        {Subscription, :start_link,
         [base_name, correlation_id, subscriber, stream, resolve_link_tos, ack_timeout]},
      restart: :temporary
    })
  end

  def start_subscription(base_name, correlation_id, subscriber, read_params) do
    base_name
    |> _name()
    |> DynamicSupervisor.start_child(%{
      id: ReadingSubscription,
      start:
        {ReadingSubscription, :start_link, [base_name, correlation_id, subscriber, read_params]},
      restart: :temporary
    })
  end

  def start_persistent_subscription(
        base_name,
        correlation_id,
        subscriber,
        stream,
        group,
        allowed_in_flight_messages
      )
      when is_binary(stream) and is_binary(group) and is_integer(allowed_in_flight_messages) do
    base_name
    |> _name()
    |> DynamicSupervisor.start_child(%{
      id: PersistentSubscription,
      start:
        {PersistentSubscription, :start_link,
         [base_name, correlation_id, subscriber, stream, group, allowed_in_flight_messages]},
      restart: :temporary
    })
  end
end
