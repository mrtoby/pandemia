#!/usr/local/bin/ruby -w

# This is a class that will manage tournaments. It will create a schedule
# and execute matches using a virtual machine and collect statistics.
#
# Author::    Tobias Wahlstr�m (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlstr�m
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlstr�m is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

# TODO!

class Tournament

	DEFAULT_VIRUSES_PER_MATCH = 2
	DEFAULT_ROUNDS_PER_SETUP = 4

	POINTS_WIN = 2
	POINTS_TIE = 1
	POINTS_LOOSE = 0
	
	attr_accessor :viruses_per_match, :rounds_per_setup
	attr_reader :program_count
	
	class ProgramInfo
		attr_reader :name, :id, :compiled_program, :wins, :losses, :ties, :matches, :points
		
		def initialize(id, name, compiled_program)
			@id = id
			@name = name
			@compiled_program = compiled_program
			@matches = 0
			@wins = 0
			@ties = 0
			@losses = 0
			@points = 0
		end
		
		def won_match()
			@matches += 1
			@wins += 1;
			@points += POINTS_WIN
		end
		
		def tie_match()
			@matches += 1
			@ties += 1
			@points += POINTS_TIE
		end
		
		def lost_match()
			@matches += 1
			@losses += 1
			@points += POINTS_LOOSE
		end
	end
	
	# Create a tournament
	def initialize()
		@program_count = 0
		@program_infos = Array.new()
	end
	
	def add_program(name, compiled_program)
		program_id = @program_count
		@program_count += 1		
		@program_infos.push(ProgramInfo.new(program_id, name, compiled_program))
	end
	
	def run(vm)
		# Must have at least as many programs as the number of programs per round!
		if @program_count < @viruses_per_match
			raise("Less viruses than the number of viruses per match: #{@program_count} < #{@viruses_per_match}")
		end

		# Create list of program ids
		program_ids = Array.new()
		@program_infos.each do |info|
			program_ids.push(info.id)
		end
		
		# Create a match schedule
		match_schedule = _create_match_schedule(program_ids)

		# Output a header
		header = [ "Setup", "Round" ]
		@program_infos.each do |info|
			header.push(info.name)
		end
		header_str = header.join("\t")
		puts(header_str)
		puts("="*(header_str.length + 3 + @program_infos.length * 3))
		
		# Start running the tournament
		setup_count = 0
		match_count = 0
		listener = ResultExecutionListener.new(true, false)
		match_schedule.each do |programs|
			setup_count += 1
			
			# Setup programs to run
			vm.clear_programs()
			programs.each do |id|
				vm.add_program(@program_infos[id].name, @program_infos[id].compiled_program, id)
			end
			
			# Start running match, perhaps with several rounds
			round_count = 0
			@rounds_per_setup.times do 
				round_count += 1
				match_count += 1
				listener.reset()
				vm.run(listener)
				
				# Collect statistics
				stats = [ "#{setup_count}", "#{round_count}" ]
				@program_infos.each do |info|
					if programs.include?(info.id)
						if listener.is_tie?()
							stats.push("tie")
							info.tie_match()
						elsif listener.is_winner?(info.id)
							stats.push("won")
							info.won_match()
						else
							stats.push("lost")
							info.lost_match()
						end
					else
						stats.push("-")
					end
				end
				puts(stats.join("\t"))
			end
		end
		
		# Sum up the results in the end
		puts("")
		puts("Results after #{match_count} matches:")
		puts("")
		header = "Virus\tWins\tTies\tLosses\tPoints"
		puts(header)
		puts("="*(header.length + 4*3))
		@program_infos.each do |info|
			puts("#{info.name}\t#{info.wins}\t#{info.ties}\t#{info.losses}\t#{info.points}")
		end		
	end

	
	private
	
	
	def _create_match_schedule(virus_ids)
		def helper(setups, selected, left, pick_count_left)
			last_selected_id = -1
			if selected.length > 0
				last_selected_id = selected[-1]
			end
			if pick_count_left > 0
				left.each do |id|
					if id > last_selected_id
						new_selected = Array.new(selected)
						new_selected.push(id)
						new_left = Array.new(left)
						new_left.delete(id)
						helper(setups, new_selected, new_left, pick_count_left - 1)
					end
				end
			else
				setups << selected
			end
		end

		setups = Array.new()
		helper(setups, [], virus_ids, @viruses_per_match)
	   
		return setups
	end	
end
