#!/usr/local/bin/ruby -w

# This is a base class for listeners that can track the progress
# of the execution in the virtual machine.
#
# Author::    Tobias Wahlstr�m (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlstr�m
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlstr�m is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

require 'compiler.rb'

class ExecutionListener

	def initialize()
		# Nop
	end

	def reset()
		# Nop
	end
	
	def on_program_added(program_id, name)
		# Nop
	end

	def on_execution_started()
		# Nop
	end
	
	def on_execution_completed()
		# Nop
	end

	def on_thread_created(program_id, thread_id)
		# Nop
	end
	
	def on_thread_create_failed(program_id)
		# Nop
	end
	
	def on_thread_terminated(program_id, thread_id)
		# Nop
	end
	
	def on_mem_read(program_id, thread_id, address, value)
		# Nop
	end
	
	def on_mem_write(program_id, thread_id, address, value)
		# Nop
	end

	def on_reg_write(program_id, thread_id, register, value)
		# Nop
	end
			
	def on_reg_read(program_id, thread_id, register, value)
		# Nop
	end
	
	def on_fetch_instruction(program_id, thread_id, address, value)
		# Nop
	end
end

class PrintingExecutionListener < ExecutionListener

	def initialize(verbose)
		@verbose = verbose
		reset()
	end

	def reset()
		@instruction_count = 0
		@compiler = Compiler.new()
	end
	
	def on_program_added(program_id, name)
		puts("Program added \##{program_id} \"#{name}\"")
	end

	def on_execution_started()
		puts("Execution started")
	end
	
	def on_execution_completed()
		puts("Execution completed")
	end

	def on_thread_created(program_id, thread_id)
		puts("Thread \##{program_id}:#{thread_id} created")
	end
	
	def on_thread_create_failed(program_id)
		puts("Program \##{program_id} failed to create thread")
	end
	
	def on_thread_terminated(program_id, thread_id)
		puts("Thread \##{program_id}:#{thread_id} is terminated")
	end
	
	def on_mem_read(program_id, thread_id, address, value)
		if @verbose
			puts("Read mem[0x%04x] => 0x%08x (%d)" % [ address, value, value ])
		end
	end

	def on_mem_write(program_id, thread_id, address, value)
		if @verbose
			puts("Wrote mem[0x%04x] <= 0x%08x (%d)" % [ address, value, value ])
		end
	end
	
	def on_reg_write(program_id, thread_id, register, value)
		if @verbose
			puts("Wrote reg[%d] <= 0x%08x (%d)" % [ register - 1, value, value ])
		end
	end
			
	def on_reg_read(program_id, thread_id, register, value)
		if @verbose
			puts("Read reg[%d] => 0x%08x (%d)" % [ register - 1, value, value ])
		end
	end

	def on_fetch_instruction(program_id, thread_id, address, instruction)
		decompiled_instruction = @compiler.decompile_instruction(instruction)
		puts("[%d] Thread \#%d:%d fetched mem[0x%04x] => 0x%08x %s" % [ @instruction_count, program_id, thread_id, address, instruction, decompiled_instruction ])
		@instruction_count += 1
	end
end

class ResultExecutionListener < ExecutionListener

	class ProgramInfo
		
		attr_accessor :name, :thread_count, :max_thread_count, :instruction_count
		
		def initialize(name)
			@name = name
			@thread_count = 0
			@max_thread_count = 0
			@instruction_count = 0
		end
		
	end

	def initialize(quiet, verbose)
		@verbose = verbose
		@quiet = quiet
		reset()
	end
	
	def reset()
		@program_infos = Hash.new()
		@program_ids = Array.new()
		@won_program_ids = nil
		@tie = false
	end

	def is_tie?()
		return @tie
	end
	
	def is_winner?(program_id)
		return @won_program_ids.include?(program_id)
	end
	
	def on_program_added(program_id, name)
		@program_ids.push(program_id)
		@program_infos[program_id] = ProgramInfo.new(name)
	end

	def on_execution_completed()
		active_programs = Array.new()
		stopped_programs = Array.new()
		
		@program_ids.each do |program_id|
			info = @program_infos[program_id]
			if @verbose
				puts("Program #{program_id}:#{info.name}")
				puts("\tThreads on completion: #{info.thread_count}")
				puts("\tTop number of threads: #{info.max_thread_count}")
				puts("\tInstructions executed: #{info.instruction_count}")
			end
			if info.thread_count == 0
				stopped_programs.push(program_id)
			else
				active_programs.push(program_id)
			end
		end
		

		if @quiet
			if (stopped_programs.length == 0) or (active_programs.length == 0)
				@tie = true
			else
				@won_program_ids = Array.new(active_programs)
			end
		else
			all_programs_str = "All programs"
			if @program_ids.length == 1
				all_programs_str = "The program"
			elsif @program_ids.length == 2
				all_programs_str = "Both programs"
			end

			if stopped_programs.length == 0
				unless @quiet
					if @program_ids.length == 1
						puts("The program is still running - nice!")
					else
						puts("#{all_programs_str} still running - its a tie")
					end
				end
			elsif active_programs.length == 0
				unless @quiet
					if @program_ids.length == 1
						puts("The program has stopped - too bad...")
					else
						puts("#{all_programs_str} stopped - its a tie")
					end
				end
			elsif active_programs.length == 1
				unless @quiet
					program_id = active_programs[0]
					info = @program_infos[program_id]
					puts("The winner is #{program_id}:#{info.name}")
				end
			else
				program_list_str = ""
				active_programs.each do |prog_id|
					info = @program_infos[prog_id]
					if program_list_str.length == 0
						program_list_str += "#{prog_id}:#{info.name}"
					else
						program_list_str += ", #{prog_id}:#{info.name}"
					end
				end
				puts("The winners are: #{program_list_str}")
			end
		end
	end

	def on_thread_created(program_id, thread_id)
		info = @program_infos[program_id]
		info.thread_count += 1
		if info.thread_count > info.max_thread_count
			info.max_thread_count = info.thread_count
		end
	end
	
	def on_thread_terminated(program_id, thread_id)
		info = @program_infos[program_id]
		info.thread_count -= 1
	end
	
	def on_fetch_instruction(program_id, thread_id, address, value)
		info = @program_infos[program_id]
		info.instruction_count += 1		
	end
end