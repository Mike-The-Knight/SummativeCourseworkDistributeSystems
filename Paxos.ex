defmodule Paxos do
    def start(name, participants) do
        pid = spawn(Paxos, :init, [name, participants])
        case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> :error
        end
        IO.puts "registered #{name}"
        pid
    end

    defp init() do
        state = %{
            name: name,
            participants: participants,
            bal: 0,
            a_bal: 0,
            a_val: 0,
            v: 0,
            prepared_acks: [],
            accepted_acks: [],
            decided: false
        }
        run(state)
    end

    defp run(state) do
        state = receive do
            {:prepare, b, p} ->
                if b > state.bal do
                    state = %{state | bal: b}
                    send(p, {:prepared, b, state.a_bal, state.a_val})
                else
                    send(p, {:nack, b})
                end
                state

            {:prepared, b, a_bal, a_val} ->
                state = %{state | prepared_acks: state.prepared_acks
                 ++ [%{:b => b, :a_bal => a_bal, :a_val => a_val}]}
                if length(state.prepared_acks) > round(length(state.participants)/2) do
                    decided_value = decide_value(state)
                    for p <- state.participants do
                        send(p, {:accept, b, decided_value})
                    end
                else
                    state = receive do
                        {:nack, b} ->
                            {:abort}
                    end
                end
                state

            {:accept, b, v, p} ->
                if b >= state.bal do
                    state = %{state | bal: b, a_bal: b, a_val: v}
                    send(p, {:accepted, b})
                else
                    send(p, {:nack, b})
                end

            {:accepted, b} ->
                state = %{state | accepted_acks: state.accepted_acks ++ [b]}
                if length(state.accepted_acks) > round(length(state.participants)/2) do
                    for p <- state.participants do
                        send(p, {:decision, state.a_val})
                    end
                    state = %{state | decided: true}
                else
                    state = receive do
                        {:nack, b} ->
                            {:abort}
                    end
                end
                state
        end
    end

    def propose(pid, inst, value, t) do

        start_timer(t, pid, {:timeout})

        for p <- inst.state.participants do
            send(p, {:prepare, inst.state.bal, pid})
        end

        if inst.v == value && decided == true do
            {:decision, v}
        end


        {:abort}



        end

    end

    def get_decision(pid, inst, t) do
        if inst.state.v != nil && inst.decided == true do
            inst.state.v
        else
            nil
        end
        state
    end

    defp decide_value(state) do     # Think this is too basic
        if state.a_bal > 0 do
            state.a_val
        else
            state.v
        end
    end
end
