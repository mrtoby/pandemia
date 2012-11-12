#!/usr/local/bin/ruby -w

# This is some things that relates to the machine code used by
# the pandemia* virtual machine.
#
# Author::    Tobias Wahlström (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlström
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlström is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

module MachineCode

	# Opcodes
	DATA = 0
	NOP = 1
	ASSIGN = 2
	ADD = 3
	SUB = 4
	MUL = 5
	DIV = 6
	MOD = 7
	COMPARE = 8
	JUMP = 9
	JUMP_ZERO = 10
	JUMP_NOT_ZERO = 11
	JUMP_LT_ZERO = 12
	JUMP_GT_ZERO = 13
	RESERVED = 14
	FORK = 15

	# Create and return the instruction specified by the arguments.
	#
	# Parameters:
	# +opcode+:: One of the constants OPCODE_XXX
	# +a+:: The first parameter for the instruction
	# +b+:: The second parameter for the instruction
	def self.create_instruction(opcode, a, b)
		return ((opcode & 0xf) << 28) | ((a & 0x3fff) << 14) | (b  & 0x3fff)
	end
	
	# Create and return a instruction that declare numeric data.
	def self.create_data_instruction(value)
		return (DATA << 28) | (value & 0x0fffffff)
	end
	
	# Create and return a literal parameter
	def self.create_literal_param(value, dereference_count)
		if dereference_count == 0
			# Top bits should be 00
			return value & 0x0fff
		elsif dereference_count == 1
			# Top bits should be 10
			return 0x2000 | (value & 0x0fff)
		else
			# Top bits should be 11
			return 0x3000 | (value & 0x0fff)			
		end
	end
		
	# Create and return a register parameter
	def self.create_register_param(register_number, dereference_count)
		if dereference_count == 0
			# Top bits should be 010
			return 0x1000 | ((register_number - 1) & 0xf)
		elsif dereference_count == 1
			# Top bits should be 011
			return 0x1800 | ((register_number - 1) & 0xf)
		else
			raise "Not supported dereference count: #{dereference_count}"
		end
	end

	# Get the opcode for an instruction
	def self.get_opcode(instruction)
		return (instruction >> 28) & 0xf
	end
	
	# Get the first parameter for the instruction
	def self.get_param_a(instruction)
		return (instruction >> 14) & 0x3fff
	end
	
	# Get the second parameter for the instruction
	def self.get_param_b(instruction)
		return instruction & 0x3fff
	end

	# Get the numeric value for a data instruction
	def self.get_data_value(instruction)
		if (instruction & 0x08000000) == 0
			# A positive number
			return instruction & 0x0fffffff
		else
			# A negative number
			return -((~instruction & 0x0fffffff) + 1)
		end
	end
	
	# Test if the parameter is a literal value
	def self.is_literal_param?(param)
		return (param & 0x3000) != 0x1000
	end

	# Test if the parameter is a register reference
	def self.is_register_param?(param)
		return (param & 0x3000) == 0x1000
	end

	# Get the register number
	def self.get_param_register_number(param)
		return (param & 0xf) + 1
	end
	
	# Get the literal value number
	def self.get_param_literal_value(param)
		if (param & 0x0800) == 0
			# This is a positive value
			return param & 0x0fff
		else
			# This is a negative value
			return -((~param & 0x0fff) + 1)
		end
	end
	
	# Get the number of dereferences for the parameter
	def self.get_dereference_count(param)
	    first_two_bits = (param & 0x3000)
		if first_two_bits == 0x0000
			# A plain literal value
			return 0
		elsif first_two_bits == 0x1000
			# A register value
			if (param & 0x3800) == 0x1000
				return 0
			else
				return 1
			end
		elsif first_two_bits == 0x2000
			# Direct memory access
			return 1
		elsif first_two_bits == 0x3000
			# Indirect memory access
			return 2
		end
	end

end