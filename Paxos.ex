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
    def init(name, participants) do
        initialise = %{
            name: name,
            participants: participants,
            instances: %[],
        }
    end

    def create_inst(name, participants, instance) do
        state = %{
            name: {name, instance},
            participants: participants,
            bal: 0,                         # ballot number - records highest ballot number which process participates in
            a_bal: 0,                       # highest ballot accepted by this process
            a_val: 0,                       # value assocated with a_bal
            v: 0,                           # value of the propose request
            prepAcks: [],
            accpAcks: [],
        }
        run(state)
    end

    # Run function for a certain state
    def run(state) do
        state = receive do

            # Get decision - retrieves a certain pid's v decision
            {:get_decision, p} ->


            # Prepare - finds out if a process is ready
            {:prepare, b, p, instance} ->
                # If the ballot value proposed is bigger than the current states ballot
                # acknowledge that ballot number and change the states ballot number to the new ballot number
                if b > state.bal do
                    state = %{state | bal: b}
                    send({p, instance}, {:prepared, b, state.a_bal, state.a_val})
                else
                    # If the new ballot number is not bigger than the current states ballot, return a non-acknowledgment
                    send({p, instance}, {:nack, b})
                end
                state

            # Prepared - checks to see if a qourum of processes have acknowledged the ballot value
            {:prepared, b, a_bal, a_val} ->
                # Update the amount of prepare acks
                state = %{state | prepAcks: state.prepAcks
                 ++ [%{:b => b, :a_bal => a_bal, :a_val => a_val}]}
                # If there is a qourum (greater than half) of acknowledgments do the following
                if length(state.prepAcks) > round(length(state.participants)/2) do
                    # Set the decided value from the state
                    decided_value = decide_value(state)

                    # Send out an accept to all state participants with the decided value and ballot number
                    for p <- state.participants do
                        send({p, instance}, {:accept, b, decided_value})
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
                    send({p, instance}, {:accepted, b})
                    state
                else
                    # Else, just reply with a non-acknowledgement
                    send({p, instance}, {:nack, b})
                    state
                end

            # Accepted - checks to see if a quorum of processes have accepted
            {:accepted, b} ->
                # Update the amount of accept acknowledgements 
                state = %{state | accpAcks: state.accpAcks ++ [b]}

                # Check if there is a quorum (greater than half) of accepted acknowledgments and do the following
                if length(state.accpAcks) > round(length(state.participants)/2) do
                    # Send a decision with the accepted value from the state to all participants
                    for p <- state.participants do
                        send({p, instance}, {:decision, state.a_val})
                    end

                    # Set decided as true for the state
                    state = %{state | decided: true}
                    state
                end
                state

            {:nack, b} ->
                {:abort}

            {:abort} ->
                IO.puts "Aborting"

        end
        run(state)
    end

    def propose(pid, inst, value, t) do

        if inst.state.leader == pid && inst.state.decided == false do
            inst.state = %{inst.state| myBal: inst.state.myBal + 1}

            From Elixir Process docs
            Process.send_after(self(), {:timeout}, t)

            for p <- pid.participants do
                send({p, instance}, {:prepare, inst.state.bal, pid})
            end

            if inst.v == value && inst.decided == true do
                {:decision, inst.v}
            end


            {:abort}

        end

    end

    def get_ballot_number(inst) do
      Paxos.
    end

    def get_decision(pid, inst, t) do
        
    end

    defp decide_value(state) do     # Think this is too basic
        if state.a_bal > 0 do
            state.a_val
        else
            state.v
        end
    end
end
