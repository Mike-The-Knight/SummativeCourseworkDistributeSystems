defmodule Paxos do
    # Takes an atom (name) and a full list of other atoms (participants) and creates a
    # Paxos process with the atom name and all the atoms (participants) that are participating in the protocol
    def start(name, participants) do
        pid = spawn(Paxos, :init, [name, participants])
        case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> :error
        end
        IO.puts "registered #{name}"
        pid
    end

    # The Initialisation function for start; assigns ballots, values, acks and whether a state has decided on a value
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
            decided: false,
            leader: 0,
            myBallot: 0
        }
        run(state)
    end

    # Run function for a certain state
    defp run(state) do
        state = receive do
            {:trust, p} ->
                state = %{state | leader: p}
                state

            {:decide, v} ->
                if state.decided == false do
                    state = %{state | decided = true}
                    state
                end
                state

            # Prepare - finds out if a process is ready
            {:prepare, b, p} ->
                # If the ballot value proposed is bigger than the current states ballot
                # acknowledge that ballot number and change the states ballot number to the new ballot number
                if b > state.bal do
                    state = %{state | bal: b}
                    send(p, {:prepared, b, state.a_bal, state.a_val})
                else
                    # If the new ballot number is not bigger than the current states ballot, return a non-acknowledgment
                    send(p, {:nack, b})
                end
                state

            # Prepared - checks to see if a qourum of processes have acknowledged the ballot value
            {:prepared, b, a_bal, a_val} ->
                # Check the current states prepared acknowledgments
                state = %{state | prepared_acks: state.prepared_acks
                 ++ [%{:b => b, :a_bal => a_bal, :a_val => a_val}]}
                # If there is a qourum (greater than half) of acknoeldgments do the following
                if length(state.prepared_acks) > round(length(state.participants)/2) do
                    # Set the decided value from the state
                    decided_value = decide_value(state)

                    # Send out an accept to all state participants with the decided value and ballot number
                    for p <- state.participants do
                        send(p, {:accept, b, decided_value})
                    end
                end
                state

            # Accept - accept the value proposed
            {:accept, b, v, p} ->
                # If the ballot sent is greater than or equal to the current states ballot do the following
                if b >= state.bal do
                    # Change the current states ballot value, highest accept ballot value, and the accepted value
                    state = %{state | bal: b, a_bal: b, a_val: v}
                    # Respond with an accepted with ballot value
                    send(p, {:accepted, b})
                    state
                else
                    # Else, just reply with a non-acknowledgement
                    send(p, {:nack, b})
                    state
                end

            # Accepted - checks to see if a quorum of processes have accepted
            {:accepted, b} ->
                # Check the current states accepted acknowledgments
                state = %{state | accepted_acks: state.accepted_acks ++ [b]}

                # Check if there is a quorum (greater than half) of accepted acknowledgments and do the following
                if length(state.accepted_acks) > round(length(state.participants)/2) do
                    # Send a decision with the accepted value from the state to all participants
                    for p <- state.participants do
                        send(p, {:decision, state.a_val})
                    end

                    # Set decided as true for the state
                    state = %{state | decided: true}
                    state
                end
                state

            {:nack, b} ->
                {:abort}

            {:abort} ->

        end
    end

    def propose(pid, inst, value, t) do

        if inst.state.leader == pid && inst.state.decided == false do
            inst.state = %{inst.state| myBallot: inst.state.myBallot + 1}

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
