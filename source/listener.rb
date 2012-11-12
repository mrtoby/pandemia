#!/usr/local/bin/ruby -w

# This is a base class for listeners that can track the progress
# of the execution in the virtual machine.
#
# Author::    Tobias Wahlström (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlström
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlström is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

class ExecutionListener

	def initialize()
		# Nop
	end
	
	def on_program_added(program_id, name)
		# Nop
	end

	def on_execution_started(memory)
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
	
	def on_mem_read(program_id, thread_id, address)
		# Nop
	end
	
	def on_mem_write(program_id, thread_id, address)
		# Nop
	end
	
	def on_fetch_instruction(program_id, thread_id, address)
		# Nop
	end
end
