defmodule SeatReservation do

    def start(name, paxos_proc) do
        pid = spawn(SeatReservation, :init, [name, paxos_proc])
        pid = case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> nil
        end
        IO.puts(if pid, do: "registered #{name}", else: "failed to register #{name}")
        pid
    end

    def init(name, paxos_proc) do
        state = %{
            name: name,
            pax_pid: get_paxos_pid(paxos_proc),
            last_instance: 0,
            pending: {0, nil},
            free_seats: MapSet.new(),
            my_reserved_seats: MapSet.new(),
            all_seats: %{A1: "Available", A2: "Available", A3: "Available"}

        }
        # Ensures shared destiny (if one of the processes dies, the other one does too)
        # Process.link(state.pax_pid)
        run(state)
    end

    # Get pid of a Paxos instance to connect to
    defp get_paxos_pid(paxos_proc) do
        case :global.whereis_name(paxos_proc) do
                pid when is_pid(pid) -> pid
                :undefined -> raise(Atom.to_string(paxos_proc))
        end
    end

    defp wait_for_reply(_, 0), do: nil
    defp wait_for_reply(r, attempt) do
        msg = receive do
            msg -> msg
            after 1000 ->
                send(r, {:poll_for_decisions})
                nil
        end
        if msg, do: msg, else: wait_for_reply(r, attempt-1)
    end

    def reserve(r, seat_number) do        
        send(r, {:reserve, self(), seat_number})
        case wait_for_reply(r, 5) do
            {:reserve_ok} -> :ok
            {:reserve_failed} -> :fail
            {:abort} -> :fail
            _ -> :timeout
    end

    def cancel(r, seat_number) do
        send(r, {:cancel, self(), seat_number})
        case wait_for_reply(r, 5) do
            {:cancel_ok} -> :ok
            {:cancel_failed} -> :fail
            {:abort} -> :fail
            _ -> :timeout
        end
    end

    def get_seats(r) do
        send(r, {:get_seats, self()})
        receive do
            {:seats, all_seats} -> 
                all_seats
            after 10000 -> :timeout
        end
    end


  def deposit(r, amount) do
      if amount < 0, do: raise("deposit failed: amount must be positive")
      send(r, {:deposit, self(), amount})
      case wait_for_reply(r, 5) do
          {:deposit_ok} -> :ok
          {:deposit_failed} -> :fail
          {:abort} -> :fail
          _ -> :timeout
      end
  end

  def withdraw(r, amount) do
      if amount < 0, do: raise("withdraw failed: amount must be positive")
      send(r, {:withdraw, self(), amount})
      case wait_for_reply(r, 5) do
          {:insufficient_funds} -> :insufficient_funds
          {:withdraw_ok} -> :ok
          {:withdraw_failed} -> :fail
          {:abort} -> :fail
          _ -> :timeout
      end
  end

  def balance(r) do
      send(r, {:get_balance, self()})
      receive do
          {:balance, bal} -> bal
          after 10000 -> :timeout
      end
  end


    def run(state) do
        state = receive do
            {trans, client, _}=t when trans == :reserve or trans == :cancel ->
                state = poll_for_decisions(state)
                if Paxos.propose(state.pax_pid, state.last_instance+1, t, 1000) == {:abort} do
                    send(client, {:abort})
                else
                    %{state | pending: {state.last_instance+1, client}}
                end

            {:get_seats, client} ->
                state = poll_for_decisions(state)
                send(client, {:seats, state.all_seats})
                state

            {:abort, inst} ->
                {pinst, client} = state.pending
                if inst == pinst do
                    send(client, {:abort})
                    %{state | pending: {0, nil}}
                else
                    state
                end

            {:poll_for_decisions} ->
                poll_for_decisions(state)

            _ -> state
        end
        # IO.puts("REPLICA STATE: #{inspect state}")
        run(state)
    end


    defp poll_for_decisions(state) do
        case  Paxos.get_decision(state.pax_pid, i=state.last_instance+1, 1000) do
            {:reserve, client, seat_number} ->
                state = case state.pending do
                    {^i, ^client} ->
                        send(elem(state.pending, 1), {:reserve_ok})
                        %{state | pending: {0, nil}, all_seats: Map.put(state.all_seats, seat_number, "Booked"), my_reserved_seats: MapSet.put(state.my_reserved_seats, seat_number)}
                    {^i, _} ->
                        send(elem(state.pending, 1), {:reserve_failed})
                        %{state | pending: {0, nil}, all_seats: Map.put(state.all_seats, seat_number, "Booked"), my_reserved_seats: MapSet.put(state.my_reserved_seats, seat_number)}
                    _ ->
                        %{state | all_seats: Map.put(state.all_seats, seat_number, "Booked"), my_reserved_seats: MapSet.put(state.my_reserved_seats, seat_number)}
                end
                poll_for_decisions(%{state | last_instance: i})

            {:cancel, client, seat_number} ->
                state = case state.pending do 
                    {^i, ^client} ->
                        send(elem(state.pending, 1), {:cancel_ok})
                        %{state | pending: {0, nil}}
                    {^i, _} ->
                        send(elem(state.pending, 1), {:cancel_failed})
                        %{state | pending: {0, nil}}
                    _ -> state
                end
                if MapSet.member?(state.my_reserved_seats, seat_number) do
                    state = %{state | all_seats: Map.put(state.all_seats, seat_number, "Available")}
                    state = %{state | my_reserved_seats: MapSet.delete(state.my_reserved_seats, seat_number)}
                    state = %{state | free_seats: MapSet.put(state.free_seats, seat_number)}
                end
                
                # IO.puts("\tNEW BALANCE: #{bal}")
                poll_for_decisions(%{state | last_instance: i})

            nil -> state
        end
    end

end
