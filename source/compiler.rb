#!/usr/local/bin/ruby -w

# This is a compiler that given a textfile or string with a plain text 
# representation of a pandemia* program compiles it into machine code
# that will run in the pandemia* virtual machine.
#
# Author::    Tobias Wahlström (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlström
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlström is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

require 'machine_code.rb'

class Compiler

	attr_reader :errors, :warnings
  
	# Create a compiler
	def initialize()
		@predefined_symbols2value = Hash.new()
	end

	# This is a compiler that given a textfile or string with a plain text 
	# representation of a pandemia* program compiles it into machine code
	# that will run in the pandemia* virtual machine. An exception is raised
	# on failure.
	#
	# Returns an instance of Compiler::CompiledProgram
	#
	# Parameters:
	# +program+:: A multi line string with pandemia* code
	def compile_string(program)
		lines = program.split(/\n\r/)
		@source_name = '<string>'
		@lineno = 0
		@errors = 0
		@warnings = 0		
		_clear_labels()
		_clear_symbols()

		instructions = _compile(_preprocess(lines))

		start_offset = 0
		if _has_label?("start")
			start_offset = _get_label_address("start")
		end

		return CompiledProgram.new(start_offset, instructions)
	end

	# This is a compiler that given a filename will read the contents
	# of the file and compile the plain text pandemia* program into 
	# machine code that will run in the pandemia* virtual machine. 
	# An exception is raised on failure.
	#
	# Returns an instance of Compiler::CompiledProgram
	#
	# Parameters:
	# +filename+:: Name of the file to compile
	def compile_file(filename)
		file = File.new(filename, 'r')
		lines = Array.new()
		while line = file.gets
			lines.push(line)
		end
		@source_name = filename
		@lineno = 0
		@errors = 0
		@warnings = 0		
		_clear_labels()
		_clear_symbols()

		instructions = _compile(_preprocess(lines))

		start_offset = 0
		if _has_label?("start")
			start_offset = _get_label_address("start")
		end

		return CompiledProgram.new(start_offset, instructions)
	end

	# Decompile an instruction into a statement that would generate
	# the same instruction if compiled with this compiler.
	def decompile_instruction(instruction)
		opcode = MachineCode.get_opcode(instruction)
		if opcode == MachineCode::DATA
			return "data " + MachineCode.get_data_value(instruction).to_s
		else
			a = MachineCode.get_param_a(instruction)
			b = MachineCode.get_param_b(instruction)
			case opcode
			when MachineCode::NOP
				return "nop"
			when MachineCode::ASSIGN
				return _decompile_param(a) + " = " + _decompile_param(b)
			when MachineCode::ADD
				return _decompile_param(a) + " += " + _decompile_param(b)
			when MachineCode::SUB
				return _decompile_param(a) + " -= " + _decompile_param(b)
			when MachineCode::MUL
				return _decompile_param(a) + " *= " + _decompile_param(b)
			when MachineCode::DIV
				return _decompile_param(a) + " /= " + _decompile_param(b)
			when MachineCode::MOD
				return _decompile_param(a) + " %= " + _decompile_param(b)
			when MachineCode::COMPARE
				return _decompile_param(a) + " <=> " + _decompile_param(b)
			when MachineCode::JUMP
				return "jump " + _decompile_param(b)
			when MachineCode::JUMP_ZERO
				return "jump " + _decompile_param(b) + " if " + _decompile_param(a) + " == 0"
			when MachineCode::JUMP_NOT_ZERO
				return "jump " + _decompile_param(b) + " if " + _decompile_param(a) + " != 0"
			when MachineCode::JUMP_LT_ZERO
				return "jump " + _decompile_param(b) + " if " + _decompile_param(a) + " < 0"
			when MachineCode::JUMP_GT_ZERO
				return "jump " + _decompile_param(b) + " if " + _decompile_param(a) + " > 0"
			when MachineCode::DEC_JUMP_NOT_ZERO
				return "jump " + _decompile_param(b) + " if --" + _decompile_param(a) + " != 0"
			when MachineCode::FORK
				return "fork " + _decompile_param(b)
			else
				return "WTF!"
			end
		end
	end

	# Add a predefined symbol. Predefined symbols should be uppercase.
	#
	# The symbol +OFFSET+ will be defined by the compiler itself and
	# will be the offset in memory from the first instruction in the
	# resulting machine code.
	#
	# +symbol+:: A string with the name of the symbol
	# +value+:: The numeric value of the symbol
	def add_predefined_symbol(symbol, value)
		if symbol.eql?("OFFSET")
			raise("The name OFFSET will be defined by the compiler itself")
		elsif not(@predefined_symbols2value[symbol].nil?)
			raise("Predefined symbol is already defined: #{symbol}")
		elsif symbol.match(/^[A-Z_]+$/)
			@predefined_symbols2value[symbol] = value
		else
			raise("Bad name for predefined symbol: #{symbol}")
		end
	end
	
	class CompiledProgram
		attr_reader :start_offset, :instructions
		
		def initialize(start_offset, instructions)
			@start_offset = start_offset
			@instructions = instructions
		end
	end
	
	private

	
	# Decompile a parameter value
	def _decompile_param(param)
		dereference_count = MachineCode.get_dereference_count(param)
		prefix = '@' * dereference_count
		if MachineCode.is_literal_param?(param)
			# Literal parameter
			return prefix + MachineCode.get_param_literal_value(param).to_s
		else
			# Register parameter
			registerNumber = MachineCode.get_param_register_number(param)
			if registerNumber > 16
				return prefix + "s" + (registerNumber - 16).to_s
			else
				return prefix + "r" + registerNumber.to_s
			end
		end
	end
	
	# This is function will clean up the lines, only leaving statements
	# and empty lines in the list. Any labels will be stored for later
	# use.
	#
	# * On success an array of cleaned up lines is returned.
	# * On failure an exception is raised
	#
	# Parameters:
	# +lines+:: An array of single line strings
	def _preprocess(lines)
		@address = 0
		result_lines = Array.new()
		
		lines.length.times do |i|
			line = String.new(lines[i])
			@lineno = i + 1
			
			# Remove comments
			line.sub!(/\;.*$/, '')
			
			# Normalize spacing
			line.gsub!(/^\s+/, '')
			line.gsub!(/\s+$/, '')
			line.gsub!(/\s+/, ' ')
			
			if line.empty?
				# Empty lines do not increment the address, but is kept to
				# make sure that the line numbers are preserved.
				result_lines.push('')
			else
				result = line.match(/^(\w+)\s*\:\s*(.*)$/)
				if result
					# We found a label, save it and keep the statement without
					# the label. And increase the address.
					_add_label($1, @address)
					result_lines.push($2)
					@address += 1
				else
					# No match, this must be a statement without a label.
					# Keep it and increase the address
					result_lines.push(line)
					@address += 1
				end
			end
		end
		return result_lines
	end
	
	# Create and return a literal parameter
	def _create_literal_param(value, dereference_count)
		if value < -2048 or value > 2047
			_error("Literal parameter out of range [-2048, 2047]: #{value}")
			return MachineCode.create_literal_param(0, 0)
		else
			return MachineCode.create_literal_param(value, dereference_count)
		end
	end
		
	# Create and return a register parameter
	def _create_register_param(register_number, shared_register, dereference_count)
		if register_number < 1 or register_number > 16
			_error("Register number out of range [1, 16]: #{register_number}")
			return MachineCode.createRegisterParam(1, 0)
		else
			if shared_register
				register_number += 16
			end
			return MachineCode.create_register_param(register_number, dereference_count)
		end
	end
	
	# Get the opcode for the specified conditional jump condition
	def _get_conditional_jump_opcode(condition)
		if condition.eql?('==')
			return MachineCode::JUMP_ZERO
		elsif condition.eql?('!=')
			return MachineCode::JUMP_NOT_ZERO
		elsif condition.eql?('<')
			return MachineCode::JUMP_LT_ZERO
		elsif condition.eql?('>')
			return MachineCode::JUMP_GT_ZERO
		else
			_error("Unrecognized jump condition '#{condition}'")
			return MachineCode::JUMP_ZERO # May not be reached...
		end
	end
	
	# Get the opcode for the specified operator
	def _get_assignment_or_arithmetic_opcode(operator)
		if operator.eql?('=')
			return MachineCode::ASSIGN
		elsif operator.eql?('+=')
			return MachineCode::ADD
		elsif operator.eql?('-=')
			return MachineCode::SUB
		elsif operator.eql?('*=')
			return MachineCode::MUL
		elsif operator.eql?('/=')
			return MachineCode::DIV
		elsif operator.eql?('%=')
			return MachineCode::MOD
		else
			_error("Unrecognized operator '#{operator}'")
			return MachineCode::ASSIGN # May not be reached...
		end
	end

	# Parse an expression into a numeric value, the expression can contain
	# parenthesis, addition, subtraction, labels, literal numbers. 
	# Labels are evaluated based on the current address.
	def _parse_numeric_value(expr, should_suggest_parenthesis)
		# TODO: For now we only support plain labels or numbers
		if expr.match(/^[+-]*0x[\h]+$/)
			# Hexadecimal number
			return expr.hex()
		elsif expr.match(/^[+-]*\d+$/)
			# Decimal number
			return expr.to_i()
		elsif _has_label?(expr)
			# A label
			label_address = _get_label_address(expr)
			rel_address = label_address - @address
			return rel_address
		elsif _has_symbol?(expr)
			# A symbol
			return _get_symbol_value(expr)
		else
			_error("Expected number or label: '#{expr}'")
			return 0
		end
	end
	
	# Parse the given expression and return a parameter that can be used
	# at least for reading a value (but not necessarily for writing)
	def _parse_value_param(expr)
		if expr.match(/^(\@{0,2})(r|s)(\d{1,2})$/)
			return _create_register_param($3.to_i(), $2.eql?("s"), $1.length)
		elsif expr.match(/^(\@{1,2})(.+)$/)
			return _create_literal_param(_parse_numeric_value($2, true), $1.length)
		else
			return _create_literal_param(_parse_numeric_value(expr, false), 0)
		end
	end
	
	# Parse the given expression and return a parameter that can be used
	# for writing a value
	def _parse_value_ref_param(expr)
		if expr.match(/^(\@{0,2})(r|s)(\d{1,2})$/)
			return _create_register_param($3.to_i(), $2.eql?("s"), $1.length)
		elsif expr.match(/^(\@{1,2})(.+)$/)
			return _create_literal_param(_parse_numeric_value($2, true), $1.length)
		else
			_error("Expect memory reference or register, not: '#{expr}'")
			return _create_register_param(1, false, 0) # May not be reached...
		end
	end

	# Parse a data value for declared data
	def _parse_data_value(expr)
		value = _parse_numeric_value(expr, false)
		if value < -268435456 or value > 268435455
			_error("Literal parameter out of range [-268435456, 268435455]: #{value}")
			return 0 # May not be reached...
		else
			return value
		end
	end
	
	# Compile the passed statement into a single instruction
	def _compile_statement(stmt)
		if stmt.eql?('nop')
			# Nop!
			return MachineCode::create_instruction(
				MachineCode::NOP, 
				MachineCode::create_literal_param(0, 0), 
				MachineCode::create_literal_param(0, 0))
		elsif stmt.match(/^jump\s(.+?)\sif\s--(.+?)\s?(\=\=|\!\=|\<|\>)\s?0$/)
			# Decrement and jump
			if not($3.eql?("!="))
				_error("Decrement and jump can only be used with condition: != 0")
			end
			return MachineCode::create_instruction(
				MachineCode::DEC_JUMP_NOT_ZERO,
				_parse_value_ref_param($2), # Value ref to decrement and compare before jump
				_parse_value_param($1)) # Jump address
		elsif stmt.match(/^jump\s(.+?)\sif\s(.+?)\s?(\=\=|\!\=|\<|\>)\s?0$/)
			# Conditional jump
			return MachineCode::create_instruction(
				_get_conditional_jump_opcode($3), 
				_parse_value_param($2), # Value to compare before jump
				_parse_value_param($1)) # Jump address
		elsif stmt.match(/^jump\s(.+)$/)
			# Unconditional jump
			return MachineCode::create_instruction(
				MachineCode::JUMP,
				_create_literal_param(0, 0),
				_parse_value_param($1)) # Jump address
		elsif stmt.match(/^fork\s(.+)$/)
			# Create a new thread
			return MachineCode::create_instruction(
				MachineCode::FORK,
				_create_literal_param(0, 0),
				_parse_value_param($1)) # Fork address
		elsif stmt.match(/(.+?)\s?\<\=\>\s?(.+)/)
			# Compare operator
			return MachineCode::create_instruction(
				MachineCode::COMPARE,
				_parse_value_param($1),
				_parse_value_param($2))
		elsif stmt.match(/(.+?)\s?([\+\-\*\/\%]?\=)\s?(.+)/)
			# Assignment or arithmetics
			return MachineCode::create_instruction(
				_get_assignment_or_arithmetic_opcode($2),
				_parse_value_ref_param($1), # The left-hand-side
				_parse_value_param($3)) # The right-hand-side
		elsif stmt.match(/^data\s(.+)$/)
			# Declaration of literal data
			return MachineCode::create_data_instruction(_parse_data_value($1))
		else
			_error("Unrecognized statement: '#{stmt}'")
			return MachineCode::create_instruction(
				MachineCode::NOP, 
				MachineCode::create_literal_param(0, 0), 
				MachineCode::create_literal_param(0, 0))
		end
	end	
	
	# Compile the passed array of lines into an array of instructions
	def _compile(lines)
		instructions = Array.new()
		@address = 0		
		lines.length.times do |i|
			line = lines[i]
			@lineno = i + 1
			
			if line.empty?
				# The compiler ignore empty lines.
			else
				instructions.push(_compile_statement(line))
				@address += 1
			end
		end
		return instructions
	end

	# Check if the passed string is a keyword, e.g. register identifiers
	# textual parts of statements etc.
	def _is_keyword?(str)
		return str.match(/^[rs]\d{1,2}$/) || str.match(/^(jump|if|fork|data|nop)$/)
	end
	
	# Add a label to the lookup table
	#
	# +label+:: A string with the name of the label
	# +address+:: The absolute address of the label (program start is 0)
	def _add_label(label, address)
		if _is_keyword?(label)
			_error("Can not use keyword as label: #{label}")
			return false
		elsif _has_symbol?(label)
			_error("Symbol with same name already defined: #{label}")
			return false
		elsif _has_label?(label)
			_error("Label with same name already defined: #{label}")
			return false
		else
			@label2address[label] = address
			return true
		end
	end
	
	# Check if the passed label is in the lookup table
	def _has_label?(label)
		return not(@label2address[label].nil?)
	end

	# Get the address of passed label, if it is undefined nil is returned
	def _get_label_address(label)
		return @label2address[label]
	end
	
	# Clear the lookup table
	def _clear_labels()
		@label2address = Hash.new()
		return nil
	end
	
	# Add a symbol to symbol table
	#
	# +symbol+:: A string with the name of the symbol
	# +value+:: The value of the symbol, may be a Proc
	def _add_symbol(symbol, value)
		if _is_keyword?(symbol)
			_error("Can not use keyword as symbol: #{symbol}")
			return false
		elsif _has_symbol?(symbol)
			_error("Symbol with same name already defined: #{symbol}")
			return false
		elsif _has_label?(symbol)
			_error("Label with same name already defined: #{symbol}")
			return false
		else
			@symbol2value[symbol] = value
			return true
		end
		return nil
	end
	
	# Check if the passed symbol is added
	def _has_symbol?(symbol)
		return not(@symbol2value[symbol].nil?)
	end

	# Get the value of passed symbol, if it is undefined nil is returned
	def _get_symbol_value(symbol)
		value = @symbol2value[symbol]
		if value.nil?
			return nil
		elsif value.class == Proc
			return value.call()
		else
			return value
		end
	end
	
	# Clear the symbol table
	def _clear_symbols()
		@symbol2value = Hash.new()

		# Add predefined symbols
		@predefined_symbols2value.each_pair do |k, v|
			_add_symbol(k, v)
		end		
		
		# Add OFFSET symbol
		offset = Proc.new() do ||
			@address
		end
		_add_symbol("OFFSET", offset)

		return nil
	end

	# Call this on errors. The caller should assume that this call will
	# return, and do something to make the caller happy. The total result
	# will still fail, but the compiler may choose to show more than one
	# error.
	def _error(message)
		$stderr.puts("#{@source_name}:#{@lineno}:Error #{message}")
		@errors += 1
	end
	
	# Call this on warnings. The caller should assume that this call will
	# return, and do something to make the caller happy.
	def _warning(message)
		$stderr.puts("#{@source_name}:#{@lineno}:Warning #{message}")
		@warnings += 1
	end
	
end
