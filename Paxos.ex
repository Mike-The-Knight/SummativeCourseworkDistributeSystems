defmodule Paxos do
    # Takes an atom (name) and a full list of other atoms (participants) and creates a
    # Paxos process with the atom name and all the atoms (participants) that are participating in the protocol
    def start(name, participants) do
        pid = spawn(Paxos, :init, [name, participants])
        case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> :error
        end
        #IO.puts "registered #{name}"

        :timer.sleep(1000)

        pid
    end

    # The Initialisation function for start; assigns (for each instance) bal, a_bal, a_val, v, prepAcks, accpAcks
    def init(name, participants) do
        state = %{
            name: name,
            participants: participants,
            bal: %{},                         # ballot number - records highest ballot number which process participates in
            a_bal: %{},                       # highest ballot accepted by this process
            a_val: %{},                       # value assocated with a_bal
            v: %{},                           # value of the propose request
            prepAcks: %{},                    # number of prepared acknowledgments received
            accpAcks: %{},                    # number of accepted acknowledgements received
            inst_list: MapSet.new(),          # List of initiated instances
            nack_received: %{},               # Map of instance to whether a nack has been received
            decided: %{},                     # Map of instance to whether a value has been decided
            decidedValues: %{},
            proposer: %{},
            initialBal: %{}
        }
        run(state)
    end

    # Run function for a certain state
    def run(state) do
        state = receive do

            {:proposal, instance, bal, value, pid, proposer} ->

                new_proposer = Map.put_new(state.proposer, instance, proposer)
                state = %{state | proposer: new_proposer}
                #IO.puts(inspect(Map.get(state.proposer, instance)))

                new_inst_list = MapSet.put(state.inst_list, instance)
                state = %{state | inst_list: new_inst_list}

                # Set the highest accepted ballot number of the state to 0
                new_a_bal = Map.put_new(state.a_bal, instance, 0)
                state = %{state | a_bal: new_a_bal}

                # Set the highest accepted value of the state to 0
                new_a_val = Map.put_new(state.a_val, instance, 0)
                state = %{state | a_val: new_a_val}

                # Set the value of the state to the value proposed
                new_v = Map.put(state.v, instance, elem(value, 1))
                state = %{state | v: new_v}

                # Set the ballot number of the state to the ballot number proposed
                new_bal = Map.put(state.bal, instance, bal)
                state = %{state | bal: new_bal}
                state = %{state | initialBal: new_bal}

                new_prepAcks = Map.put(state.prepAcks, instance, [])
                state = %{state | prepAcks: new_prepAcks}

                new_accpAcks = Map.put(state.accpAcks, instance, 0)
                state = %{state | accpAcks: new_accpAcks}

                new_nack_received = Map.put(state.nack_received, instance, false)
                state = %{state | nack_received: new_nack_received}

                new_decided = Map.put(state.decided, instance, false)
                state = %{state | decided: new_decided}

                #IO.puts "#{state.name} proposes #{Map.get(state.v, instance)} , instance: #{instance}, ballot: #{Map.get(state.initialBal, instance)}"

                # Send out a prepare to all state participants with the instance, ballot number, and the current process
                for p <- state.participants do
                    if p != state.name do
                        unicast({:prepare, instance, bal, pid, proposer}, p)
                        #IO.puts "#{state.name} sent prepare to particpant #{p}"
                    end
                end

                state

            # Prepare - finds out if a process is ready
            {:prepare, instance, b, p, proposer} ->

                new_proposer = Map.put_new(state.proposer, instance, proposer)
                state = %{state | proposer: new_proposer}

                new_inst_list = MapSet.put(state.inst_list, instance)
                state = %{state | inst_list: new_inst_list}

                # Set the highest accepted ballot number of the state to 0
                new_a_bal = Map.put_new(state.a_bal, instance, 0)
                state = %{state | a_bal: new_a_bal}

                # Set the highest accepted value of the state to 0
                new_a_val = Map.put_new(state.a_val, instance, 0)
                state = %{state | a_val: new_a_val}

                # Set the value of the state to 0
                new_v = Map.put_new(state.v, instance, 0)
                state = %{state | v: new_v}

                # Set the ballot number of the state to 0
                new_bal = Map.put_new(state.bal, instance, 0)
                state = %{state | bal: new_bal}
                state = %{state | initialBal: new_bal}

                new_decided = Map.put_new(state.decided, instance, false)
                state = %{state | decided: new_decided}

                # If the ballot value proposed is bigger than the current states ballot
                # acknowledge that ballot number and change the states ballot number to the new ballot number
                if b > Map.get(state.bal, instance) do
                    new_bal = Map.put(state.bal, instance, b)
                    state = %{state | bal: new_bal}
                    #IO.puts "Prepared message sent by #{state.name}: v = #{Map.get(state.v, instance)}, a_val = #{Map.get(state.a_val, instance)}, a_bal = #{Map.get(state.a_bal, instance)}, ballot accepted: #{b}"
                    send(p, {:prepared, instance, b, Map.get(state.a_bal, instance), Map.get(state.a_val, instance)})
                    state
                else
                    # If the new ballot number is not bigger than the current states ballot, return a non-acknowledgment
                    #IO.puts "nack #{b} sent by #{state.name} because #{b} < #{Map.get(state.bal, instance)}"
                    send(p, {:nack, instance, b})
                    state
                end


            # Prepared - checks to see if a qourum of processes have acknowledged the ballot value
            {:prepared, instance, b, a_bal, a_val} ->
                #IO.puts "Prepared received"

                new_prepAcks = Map.put(state.prepAcks, instance, Map.get(state.prepAcks, instance) ++ [%{:b => b, :a_bal => a_bal, :a_val => a_val}])

                state = %{state | prepAcks: new_prepAcks}

                # Check the current states prepared acknowledgments
                # If there is a qourum (greater than half) of acknowledgments do the following
                if length(Map.get(state.prepAcks, instance)) >= round((length(state.participants) - 1)/2) and Map.get(state.nack_received, instance) == false do
                    # Set the decided value from the state
                    decided_value = decide_value(state, instance)
                    #IO.puts "#{decided_value}"

                    # Send out an accept to all state participants with the decided value and ballot number
                    for p <- state.participants do
                        if p != state.name do
                            unicast({:accept, instance, b, decided_value, self()}, p)
                            #IO.puts "#{state.name} sent accept to particpant #{p}, proposer values are: v = #{Map.get(state.v, instance)}, a_val = #{Map.get(state.a_val, instance)}, a_bal = #{Map.get(state.a_bal, instance)}"
                        end
                    end
                    
                end
                state


            # Accept - accept the value proposed
            {:accept, instance, b, v, p} ->
                # If the ballot sent is greater than or equal to the current states ballot do the following
                if b >= Map.get(state.bal, instance)  do
                    # Change the current states ballot value, highest accept ballot value, and the accepted value
                    new_bal = Map.put(state.bal, instance, b)
                    new_a_bal = Map.put(state.a_bal, instance, b)
                    new_a_val = Map.put(state.a_val, instance, v)
                    state = %{state | bal: new_bal, a_bal: new_a_bal, a_val: new_a_val}
                    # Respond with an accepted with ballot value
                    send(p, {:accepted, instance, b})
                    #IO.puts "#{state.name} sent accepted message : v = #{Map.get(state.v, instance)}, a_val = #{Map.get(state.a_val, instance)}, a_bal = #{Map.get(state.a_bal, instance)}"
                    state
                else
                    # Else, just reply with a non-acknowledgement
                    send(p, {:nack, instance, b})
                    #IO.puts "nack #{b} sent by #{state.name} because #{b} < #{Map.get(state.bal, instance)}"
                    state
                end

            # Accepted - checks to see if a quorum of processes have accepted
            {:accepted, instance, b} ->
                
                # Check the current states accepted acknowledgments
                new_accpAcks = Map.put(state.accpAcks, instance, Map.get(state.accpAcks, instance) + 1)
                state = %{state | accpAcks: new_accpAcks}

                # Check if there is a quorum (greater than half) of accepted acknowledgments and do the following
                if Map.get(state.accpAcks, instance) >= round((length(state.participants) - 1)/2) and Map.get(state.nack_received, instance) == false do
                    new_decided = Map.put(state.decided, instance, true)
                    state = %{state | decided: new_decided}

                    new_decidedValues = Map.put(state.decidedValues, instance, Map.get(state.v, instance))
                    state = %{state | decidedValues: new_decidedValues}
                    # Send a decision with the accepted value from the state to all participants
                    for p <- state.participants do
                        unicast({:decision, instance, Map.get(state.v, instance)}, p)
                        #IO.puts "#{state.name} sent decision #{Map.get(state.decidedValues, instance)} to particpant #{p}: v = #{Map.get(state.v, instance)}, a_val = #{Map.get(state.a_val, instance)}, a_bal = #{Map.get(state.a_bal, instance)}"
                    end
                    send(Map.get(state.proposer, instance), {:final_decision, Map.get(state.v, instance)})
                    state
                else
                    state
                end

            {:nack, instance, b} ->
                new_nack = Map.put(state.nack_received, instance, true)
                state = %{state | nack_received: new_nack}
                send(Map.get(state.proposer, instance), {:abort})
                IO.puts "#{state.name} aborted its proposal"
                state

            {:decision, instance, v} ->
                new_decided = Map.put(state.decided, instance, true)
                state = %{state | decided: new_decided}

                new_decidedValues = Map.put(state.decidedValues, instance, v)
                state = %{state | decidedValues: new_decidedValues}
                
                #IO.puts "#{state.name} made decision for instance #{instance} with value #{Map.get(state.decidedValues, instance)}"

                state

            {:get_decision, instance, decider} ->
                if (Map.get(state.decidedValues, instance) != nil) do
                    IO.puts "Retrieved decision from #{state.name} for instance #{instance} with value #{Map.get(state.decidedValues, instance)}"
                    send(decider, {:return_decision, Map.get(state.decidedValues, Enum.max(state.inst_list))})
                else
                    send(decider, {:return_decision, nil})
                end
                state
                        
        end
        run(state)
    end

    # Proposal Function
    def propose(pid, inst, value, t) do

        # Create a Ballot number for the given PID and instance
        IO.puts "#{inspect pid} proposing #{elem(value, 1)} for instance #{inst}"
        b = get_ballot_number(pid, inst)

        # Send the propose request to the PID with a ballot number, instance and value
        send(pid, {:proposal, inst, b, value, pid, self()})

        # Get the final output from the propose call
        status = receive do
            {:final_decision, v} ->
                IO.puts "Proposer: final decision is #{v}"
                {:decision, v}

            {:abort} ->
                IO.puts "Proposer: abort"
                {:abort}

            after t ->
                IO.puts "Proposer: timeout"
                {:timeout}

        end
        status
    end


    def get_ballot_number(pid, inst) do
        time = System.system_time(:millisecond)  # Get the current time in milliseconds
        time = trunc(time)                       # Remove decimal points

        pidstr = inspect(pid)                  # pid to string
        pidstr = String.slice(pidstr, 5, 100)  # Remove the first 5 characters
        pidstr = String.trim(pidstr, ">")      # Remove the last character
        pidstr = String.split(pidstr, ".")     # Split the string into a list

        # Generate and return an integer that is unique in the current
        # runtime instance
        uniqueNum = abs(System.unique_integer())
        uniqueNum = Integer.to_string(uniqueNum)
        #IO.puts "#{uniqueNum}"

        # Concatenate pid, unique integer and time to create unique ballot
        b =  List.to_string(pidstr) <> uniqueNum <> "#{time}"  
        b = String.to_integer(b)                  # Convert to integer
        #IO.puts "My ballot number is #{b}"
        b
    end

    # Get the Decision from the given PID and given instance
    def get_decision(pid, inst, t) do

        # Send the request to get a decision
        send(pid, {:get_decision, inst, self()})


        status = receive do
            {:return_decision, v} ->
                #answer = {:val, v}
                #IO.puts "#{inspect answer}"
                {:val, v}

            after t ->
                nil
        end
        status
    end

    defp decide_value(state, instance) do
        find_highest = Enum.reduce(Map.get(state.prepAcks, instance),
        fn ack1, ack2 -> if Map.fetch!(ack1, :a_bal) > Map.fetch!(ack2, :a_bal), do: ack1, else: ack2 end)

        highest_a_bal = Map.fetch!(find_highest, :a_bal)
        highest_a_val = Map.fetch!(find_highest, :a_val)
        
        #IO.puts "Highest a_bal is #{highest_a_bal}"
        #IO.puts "Highest a_val is #{highest_a_val}"

        decided_value = 0

        if highest_a_bal != Map.get(state.initialBal, instance) and highest_a_bal != 0 do
            IO.puts "#{inspect state.name} decided #{highest_a_val} for instance #{instance}"
            decided_value = highest_a_val
            decided_value
        else
            IO.puts "#{inspect state.name} decided #{Map.get(state.v, instance)} for instance #{instance}"
            decided_value = Map.get(state.v, instance)
            decided_value
            
        end
    end

    defp unicast(m, p) do
        case :global.whereis_name(p) do
                pid when is_pid(pid) -> send(pid, m)
                :undefined -> :ok
        end
    end

    defp beb_broadcast(m, dest), do: for p <- dest, do: unicast(m, p)
end
