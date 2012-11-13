#!/usr/local/bin/ruby -w

# This class is the virtual machine which can be used to run programs
# for pandemia*. The program code must be compiled to machine code
# before it can be run.
#
# Author::    Tobias Wahlström (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlström
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlström is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

require 'machine_code.rb'
require 'listener.rb'

class Machine

	DEFAULT_MEMORY_SIZE = 8000
	DEFAULT_MAX_THEADS = 2000
	DEFAULT_CYCLES_TO_COMPLETION = 80000
	DEFAULT_MAX_PROGRAM_LENGTH = 100
	DEFAULT_MIN_PROGRAM_DISTANCE = 100

	attr_accessor :memory_size, :max_threads, :cycles_to_completion, :max_program_length, :min_program_distance
	
	# Create a new virtual machine with default configuration
	def initialize()
		reset()		
	end
	
	# Add a program to the virtual machine
	def add_program(name, instructions, start_offset)
		@programs.push(Program.new(@program_id, name, instructions, start_offset))
		@program_id += 1
		return nil
	end

	# Start running the virtual machine, if the virtual machine has a bad
	# configuration an exception will be raised.
	def run(listener = nil)
		begin
			if @max_threads <= 0
				raise "The max threads must a positive number: #{@max_threads}"
			end
			
			_initialize_memory()
			context = Context.new(@memory, @max_threads, listener)
			
			@programs.each do |program|
				if not(listener.nil?)
					listener.on_program_added(program.program_id, program.name)
				end
			end

			if not(listener.nil?)
				listener.on_execution_started(@memory)
			end
			
			_locate_programs_and_create_threads(context)
			_run(context)
			reset()
			if not(listener.nil?)
				listener.on_execution_completed()
			end			
		rescue Exception => e
			reset()
			if not(listener.nil?)
				listener.on_execution_completed()
			end
			raise e
		end
		return nil
	end
	
	# Reset the virtual machine. This will clear all programs
	# and reset the configuration to default values.
	def reset()
		@programs = Array.new()
		@program_id = 0
		@memory_size = DEFAULT_MEMORY_SIZE
		@max_threads = DEFAULT_MAX_THEADS
		@cycles_to_completion = DEFAULT_CYCLES_TO_COMPLETION
		@max_program_length = DEFAULT_MAX_PROGRAM_LENGTH
		@min_program_distance = DEFAULT_MIN_PROGRAM_DISTANCE
		return nil
	end

	private
	
	# Check the configuration and initialize the memory
	def _initialize_memory()
		if @memory_size < 256 and @memory_size > 65536
			raise "Memory size should be within [256, 65536] but is: #{@memory_size}"
		end
		@memory = Array.new(@memory_size, 0)
		return nil
	end

	# Locate programs into memory and create the initial thread for each program
	def _locate_programs_and_create_threads(context)
	
		# Check that we can create enough threads
		if @max_threads < @programs.length
			raise "The max threads must be at least as great as the number of programs to run: #{@max_threads} < #{@programs.length}"
		end

		# Calculate total program length
		total_program_length = 0
		@programs.each do |program|
			if program.length > @max_program_length
				raise "Program exceeds max program length: #{program.length} > #{@max_program_length}"
			end
			total_program_length += program.length
		end

		# The amount of free memory after writing programs
		free_memory = @memory_size - total_program_length
		free_per_program = free_memory / @programs.length
		if free_per_program < @min_program_distance
			raise "Too little memory to have room for programs with minimum program distance"
		end

		# Shuffle the programs randomly to make execution less predictable
		shuffled_programs = @programs.sort_by { rand }
		
		# TODO: The algorithm below will not make the programs evenly spread out
		#       since the avarage of the rand function is the half of its argument.
		#       So typically only half of the space that is free per program will
		#       be used.
		
		# Place the first program at start of memory
		shuffled_programs[0].write_instructions(context, 0)
		shuffled_programs[0].create_thread(context, 0 + shuffled_programs[0].start_offset)
		offset = shuffled_programs[0].length
		(shuffled_programs.length - 1).times do |i|
			distance_to_next = @min_program_distance + rand(free_per_program - @min_program_distance)
			offset += distance_to_next
			shuffled_programs[1 + i].write_instructions(context, offset)
			shuffled_programs[1 + i].create_thread(context, offset + shuffled_programs[1 + i].start_offset)
			offset += shuffled_programs[1 + i].length
		end
		
		if offset > @memory_size
			raise "WTF! I laid out the programs outside the limit of the memory"
		end
		
		return nil
	end

	# Run the programs until there are no programs left with active threads or if
	# all the cycles that is allowed until completion has been executed. The number
	# of instructions executed is returned.
	def _run(context)
		active_programs = Array.new(@programs)

		# Check configuration
		if @cycles_to_completion <= 0
			raise "The least number of cycles must be a positive number, not: #{@cycles_to_completion}"
		end
		
		# Then run programs, instruction-by-instruction.
		@cycles_to_completion.times do |i|
			program = active_programs.shift()
			result = program.run_single_instruction(context)
			if result
				active_programs.push(program)
			elsif active_programs.length == 0
				# There are no more active programs
				return nil
			end
		end		
		return nil
	end

	# This class model the execution context for the programs and threads
	# in the virtual machine. It holds the memory and keeps track of 
	# the global limits.
	class Context
		
		attr_reader :listener, :curr_program, :curr_program_id, :curr_thread, :curr_thread_id
		
		# Create a context
		#
		# +memory+:: The array of memory slots
		# +maxThreads+:: The max number of threads
		# +listener+:: Listener for events in the virtual machine
		def initialize(memory, max_threads, listener)
			@thread_count = 0
			@thread_id = 0
			@max_threads = max_threads
			@memory = memory
			@memory_size = memory.length
			@listener = listener
			@curr_program = nil
			@curr_thread = nil
			@curr_program_id = nil
			@curr_thread_id = nil
		end

		# Set the current scope, i.e. program and thread id. Can be accessed 
		# with +curr_program_id+ and +program_id+. It is ok to pass a nil 
		# value as thread id before any threads has been created.
		def set_curr_scope(program, thread = nil)
			@curr_program = program
			@curr_program_id = program.program_id
			if thread.nil?
				@curr_thread = nil
				@curr_thread_id = nil
			else
				@curr_thread = thread
				@curr_thread_id = thread.thread_id
			end
		end
		
		# Clear the current scope
		def clear_curr_scope()
			@curr_program = nil
			@curr_program_id = nil
			@curr_thread = nil
			@curr_thread_id = nil
		end
		
		# Wrap the passed absolute memory offset to an offset that will fit
		# natively into the memory. This could be used for e.g. program counters
		# so that they are less obfuscated.
		def wrap_address(address)
			return address % @memory_size
		end
		
		# Read the value of a single memory slot with given absolute memory offset.
		# The memory offset will be wrapped around to fit the memory size
		def read_mem(address)
			address = address % @memory_size
			
			if not(@listener.nil?) then
				@listener.on_mem_read(@curr_program_id, @curr_thread_id, address)
			end

			return @memory[address]
		end
		
		# Write one or more values to the memory at the given absolute memory
		# offset. If the value is an integer, a single value is written. If the
		# value is an array, all values in the array is written to the memory.
		def write_mem(address, value)
			address = address % @memory_size
			if value.is_a? Integer
				# Write a single value
				@memory[address] = value
				if not(@listener.nil?) then
					@listener.on_mem_write(@curr_program_id, @curr_thread_id, address)
				end
			elsif value.is_a? Array
				# Write an array of values
				value.length.times do |i|
					@memory[address] = value[i]
					if not(@listener.nil?) then
						@listener.on_mem_write(@curr_program_id, @curr_thread_id, address)
					end
					address += 1
					if address >= @memory_size
						address = 0
					end
				end
			else
				raise "Can only write integers or arrays of integers to memory"
			end
			return nil
		end

		# Get a thread id for a new thread that has been created. These numbers
		# will be globally unique.
		def create_new_thread_id()
			new_thread_id = @thread_id
			@thread_id += 1
			return new_thread_id
		end
		
		# Try to increase the thread count. If possible, true is returned
		# otherwise false. This should be done before a new thread is created.
		def increase_thread_count()
			if @thread_count >= @max_threads
				return false
			else
				@thread_count += 1
				return true
			end
		end
		
		# Decrease the thread count. This should be done when a thread has
		# been terminated.
		def decrease_thread_count()
			if @thread_count > 0
				@thread_count -= 1
			end
			return nil
		end
	end
	
	# This class represent a program running in the virtual machine.
	# It is relevant to think of it as a process but it also keeps track
	# of the initial source code and a program can exist even without
	# having any threads.
	class Program
	
		attr_reader :name, :program_id, :start_offset, :registers
	
		# Create a new program. No thread will be created and the instructions will
		# not be copied to memory. The user of this class will have to do this
		# explicitly.
		#
		# +program_id+:: A unique program id (within this virtual machine)
		# +name+:: Some user readable name for the program
		# +instructions+:: An array of machine code instructions for the program
		# +start_offset+:: The start offset for the program
		def initialize(program_id, name, instructions, start_offset)
			@name = name
			@instructions = instructions
			@start_offset = start_offset
			@threads = Array.new()
			@running = false
			@program_id = program_id
			@registers = Array.new(16, 0)
		end
		
		# Get the length of the program
		def length()
			return @instructions.length
		end
		
		# Check is the program is running
		def running?()
			return @running
		end
		
		# Write instructions to the memory in the virtual machine context at the
		# specified offset.
		def write_instructions(context, offset)
			context.set_curr_scope(self)
			context.write_mem(offset, @instructions)
			context.clear_curr_scope()
			return nil
		end

		# Create a new thread. The limitations stored in the context will be followed.
		# The new thread will copy registers from the template thread (if any). If it
		# is possible to create a new thread it will be returned, otherwise nil.
		#
		# +context+:: Context that specify the limitations for the thread
		# +pc+:: The initial program counter for the thread
		# +template+:: The thread will copy register content from this thread
		def create_thread(context, pc, template = nil)
			if context.increase_thread_count()
				thread_id = context.create_new_thread_id()
				thread = Thread.new(thread_id, context.wrap_address(pc), template)
				@threads.push(thread)
				if not(context.listener.nil?)
					context.listener.on_thread_created(@program_id, thread_id)
				end
				return thread
			else
				if not(context.listener.nil?)
					context.listener.on_thread_create_failed(@program_id)
				end
				return nil
			end
		end
		
		# Get the number of active threads
		def get_thread_count()
			return @threads.length
		end
		
		# Run a single instruction for any thread in the program, if any. If the program still have any
		# active threads it will return true, otherwise false.
		def run_single_instruction(context)
			if @threads.length > 0
				thread = @threads.shift()
				context.set_curr_scope(self, thread)
				result = thread.run_single_instruction(context, self)
				context.clear_curr_scope()
				if result
					@threads.push(thread)
					return true
				else
					if not(context.listener.nil?)
						context.listener.on_thread_terminated(@program_id, thread.thread_id)
					end
					if @threads.length > 0
						return true
					else
						return false
					end
				end
			else
				return false
			end
		end

		# This class is the actual worker that execute instructions
		class Thread
		
			attr_reader :registers, :thread_id
		
			# Create a new thread. If the template thread is omitted the thread will
			# get empty registers.
			#
			# +thread_id+:: Unique id for thread (within this virtual machine)
			# +pc+:: The initial program counter for the thread
			# +template_thread+:: The thread will copy register content from this thread
			def initialize(thread_id, pc, template = nil)
				@thread_id = thread_id
				if template.nil?
					@registers = Array.new(16, 0)
				else
					@registers = Array.new(template.registers)
				end
				@pc = pc
			end
					
			# Helper method for the other two methods that set parameter values.
			def _set_param_value(param, value, is_data_value)
				offset = 0
				dereference_count = MachineCode.get_dereference_count(param)
				if MachineCode.is_literal_param?(param)
					# Literal param
					if dereference_count == 0
						# Can not set a value to a direct literal value
						return false
					end
					offset = MachineCode.get_param_literal_value(param)
				else
					# Register param
					register = MachineCode.get_param_register_number(param)
					if dereference_count == 0
						# Write to register directly
						# Note: Registers can hold values directly without the
						#       data instruction prefix. But they can also 
						#       hold instructions, both are 32-bit.
						if register > 16
							@context.program.registers[registers - 17] = value & 0xffffffff
						else
							@registers[register - 1] = value & 0xffffffff
						end
						return true
					end
					if register > 16
						offset = @context.program.registers[registers - 17]
					else
						offset = @registers[register - 1]
					end
				end
				if dereference_count == 2
					ptr_address = @context.wrap_address(@pc + offset)
					offset = MachineCode.get_data_value(@context.read_mem(ptr_address))
					if is_data_value
						@context.write_mem(ptr_address + offset, MachineCode.create_data_instruction(value))
					else
						@context.write_mem(ptr_address + offset, value)
					end
				elsif dereference_count == 1
					if is_data_value
						@context.write_mem(@pc + offset, MachineCode.create_data_instruction(value))
					else
						@context.write_mem(@pc + offset, value)
					end
				end
				return true
			end

			# Set a value for given parameter. If it is possible to assign
			# a value to the parameter, it will be done and true is returned.
			# Otherwise false is returned.
			def set_param_value(param, value)
				return _set_param_value(param, value, false)
			end
			
			# As setParamValue, but before value is stored it is converted
			# to a data instruction.
			def set_param_data_value(param, value)
				return _set_param_value(param, value, true)
			end

			# Helper method for the other two methods that set parameter values.
			def _get_param_value(param, is_data_value)
				value_or_offset = 0
				dereference_count = MachineCode.get_dereference_count(param)
				if MachineCode.is_literal_param?(param)
					# Literal param
					value_or_offset = MachineCode.get_param_literal_value(param)
				else
					# Register param
					register = MachineCode.get_param_register_number(param)
					if register > 16
						value_or_offset = @context.program.registers[registers - 17]
					else
						value_or_offset = @registers[register - 1]
					end
				end
				# We do not actually care if the instruction is a data
				# instruction or not
				if dereference_count == 2
					ptr_address = @context.wrap_address(@pc + value_or_offset)
					value_or_offset = MachineCode.get_data_value(@context.read_mem(ptr_address))
					if is_data_value
						value_or_offset = MachineCode.get_data_value(@context.readMem(ptr_address + value_or_offset))
					else
						value_or_offset = @context.read_mem(ptr_address + value_or_offset)
					end					
				elsif dereference_count == 1
					if is_data_value
						value_or_offset = MachineCode.get_data_value(@context.read_mem(@pc + value_or_offset))
					else
						value_or_offset = @context.read_mem(@pc + value_or_offset)				
					end
				end
				return value_or_offset
			end
		
			# Get the value for the parameter. The numeric value is returned.
			def get_param_value(param)
				return _get_param_value(param, false)
			end

			# As getParamValue, but before value is returned it is assumed
			# to be a data instruction and the actual value is evaluated
			def get_param_data_value(param)
				return _get_param_value(param, true)
			end

			# Run a single instruction for the thread. If the thread hits an illegal
			# instruction and should be terminated, false is returned. If the thread
			# should continue execution, true is returned.
			#
			# +context+:: The virtual machine context
			# +program+:: The program that the thread belongs to
			def run_single_instruction(context, program)

				# Fetch instruction
				if not(context.listener.nil?)
					context.listener.on_fetch_instruction(context.curr_program_id, @thread_id, @pc)
				end
				instruction = context.read_mem(@pc)
				next_pc = context.wrap_address(@pc + 1)
				@context = context
			
				# Decode instruction
				opcode = MachineCode.get_opcode(instruction)
				if (opcode == MachineCode::DATA)
					# Data is an illegal instruction
					@context = nil
					return false
				end

				param_a = MachineCode.get_param_a(instruction)
				param_b = MachineCode.get_param_b(instruction)
				
				case opcode
				when MachineCode::NOP
					@pc = next_pc
				when MachineCode::ASSIGN
					if not(set_param_value(param_a, get_param_value(param_b)))
						# Not able to assign
						@context = nil
						return false
					end
					@pc = next_pc
				when MachineCode::ADD
					if not(set_param_data_value(param_a, get_param_data_value(param_a) + get_param_data_value(param_b)))
						# Not able to assign
						@context = nil
						return false
					end
					@pc = next_pc
				when MachineCode::SUB
					if not(set_param_data_value(param_a, get_param_data_value(param_a) - get_param_data_value(param_b)))
						# Not able to assign
						@context = nil
						return false
					end
					@pc = next_pc
				when MachineCode::MUL
					if not(set_param_data_value(param_a, get_param_data_value(param_a) * get_param_data_value(param_b)))
						# Not able to assign
						@context = nil
						return false
					end
					@pc = next_pc
				when MachineCode::DIV
					value_b = get_param_data_value(param_b)
					if value_b == 0
						# Division by zero is invalid
						@context = nil
						return false
					end
					if not(set_param_data_value(param_a, get_param_data_value(param_a) / value_b))
						# Not able to assign
						@context = nil
						return false
					end
					@pc = next_pc
				when MachineCode::MOD
					if not(set_param_data_value(param_a, get_param_data_value(param_a) % get_param_data_value(param_b)))
						# Not able to assign
						@context = nil
						return false
					end
					@pc = next_pc
				when MachineCode::COMPARE
					@registers[0] = get_param_data_value(param_a) <=> get_param_data_value(param_b)
					@pc = next_pc
				when MachineCode::JUMP
					@pc = context.wrap_address(@pc + get_param_data_value(param_b))
				when MachineCode::JUMP_ZERO
					if get_param_value(param_a) == 0
						@pc = context.wrap_address(@pc + get_param_data_value(param_b))
					else
						@pc = next_pc
					end
				when MachineCode::JUMP_NOT_ZERO
					if get_param_value(param_a) != 0
						@pc = context.wrap_address(@pc + get_param_data_value(param_b))
					else
						@pc = next_pc
					end
				when MachineCode::JUMP_LT_ZERO
					if get_param_value(param_a) < 0
						@pc = context.wrap_address(@pc + get_param_data_value(param_b))
					else
						@pc = next_pc
					end
				when MachineCode::JUMP_GT_ZERO
					if get_param_value(param_a) > 0
						@pc = context.wrap_address(@pc + get_param_data_value(param_b))
					else
						@pc = next_pc
					end
				when MachineCode::DEC_JUMP_NOT_ZERO
					# Decrement
					value = get_param_value(param_a) - 1
					if not(set_param_data_value(param_a, value))
						# Not able to assign
						@context = nil
						return false
					end
					# Check and jump
					if value != 0
						@pc = context.wrap_address(@pc + get_param_data_value(param_b))
					else
						@pc = next_pc
					end
				when MachineCode::FORK
					new_thread_pc = context.wrap_address(@pc + get_param_data_value(param_b))
					thread = program.create_thread(context, new_thread_pc, self)
					if thread.nil?
						@registers[0] = 0
					else
						@registers[0] = 1
					end
					@pc = next_pc
				else
					# Unknown instruction - should never happend
					@context = nil
					return false
				end
				
				@context = nil
				return true
			end
		end	
	end
end
