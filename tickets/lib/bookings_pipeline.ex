defmodule BookingsPipeline do
  use Broadway

  @producer BroadwayRabbitMQ.Producer
  @producer_config [
    queue: "bookings_queue",
    declare: [durable: true],
    on_failure: :reject_and_requeue
  ]

  def start_link(_args) do
    options = [
      name: __MODULE__,
      producer: [
        module: {@producer, @producer_config}
      ],
      processors: [
        default: []
      ],
      batchers: [
        cinema: [],
        musical: [],
        default: [],
      ],
    ]
    Broadway.start_link(__MODULE__, options)
  end

  def handle_batch(_batcher, messages, batch_info, _context) do
    IO.puts("#{inspect(self())} Batch #{batch_info.batcher} #{batch_info.batch_key}")

    messages
    |> Tickets.insert_all_tickets()
    # |> Enum.each(fn %{data: %{user: user}} ->
    #   Tickets.send_email(user)
    # end)
    |> Enum.each(fn message ->
      channel = message.metadata.amqp_channel
      payload = "email,#{message.data.user.email}"
      AMQP.Basic.publish(channel, "", "notifications_queue", payload)
    end)

    messages
  end

  def handle_message(_processor, message, _context) do
    %{data: %{event: event, user: _user}} = message

    if Tickets.tickets_available?(event) do
      # Tickets.create_ticket(user, event)
      # Tickets.send_email(user)
      # message # IO.inspect(message, label: "Message")
      case message do
        %{data: %{event: "cinema"}} = message ->
          Broadway.Message.put_batcher(message, :cinema)
        %{data: %{event: "musical"}} = message ->
          Broadway.Message.put_batcher(message, :musical)
        message ->
          message
      end
    else
      Broadway.Message.failed(message, "bookings-closed")
    end
  end

  def handle_failed(messages, _context) do
    IO.inspect(messages, label: "Failed messages")
    Enum.map(messages, fn
      %{status: {:failed, "bookings-closed"}} = message ->
        Broadway.Message.configure_ack(message, on_failure: :reject)
      message ->
        message
    end)
  end

  def prepare_messages(messages, _context) do
    # Parse data and convert to maps
    messages = Enum.map(messages, fn message ->
      Broadway.Message.update_data(message, fn data ->
        [event, user_id] = String.split(data, ",")
        %{event: event, user_id: user_id}
      end)
    end)

    # Put users in messages
    users = Tickets.users_by_ids(Enum.map(messages, & &1.data.user_id))
    Enum.map(messages, fn message ->
      Broadway.Message.update_data(message, fn data ->
        user = Enum.find(users, & &1.id == data.user_id)
        Map.put(data, :user, user)
      end)
    end)
  end
end
