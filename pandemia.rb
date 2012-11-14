#!/usr/local/bin/ruby -w

# This is a frontend for pandemia* - a programming game strongly inspired
# by core wars. When you want to compile, test or run tournaments you may 
# use this script.
#
# Author::    Tobias Wahlstr�m (mailto:tobias@tanke.se)
# Copyright:: Copyright (c) 2012 Tobias Wahlstr�m
# License::   Creative Commons Attribution-ShareAlike 3.0 Unported License
#
# pandemia* by Tobias Wahlstr�m is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License
# see http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB

# Add the source folder to the search path, if run directly
$:.push(File.dirname(__FILE__) + "/source")

require 'optparse'

require 'machine.rb'
require 'compiler.rb'
require 'tournament.rb'
require 'listener.rb'

class Pandemia

	# Create a new virtual machine with the configuration defined by the options
	def self.create_vm(options)
		vm = Machine.new()
		
		vm.memory_size = options[:memory_size]
		vm.max_threads = options[:max_threads]
		vm.cycles_to_completion = options[:cycles_to_completion]
		vm.max_program_length = options[:max_program_length]
		vm.min_program_distance = options[:min_program_distance]
		
		return vm
	end

	# Create a new compiler with the configuration defined by the options
	def self.create_compiler(options)
		compiler = Compiler.new()
		
		compiler.add_predefined_symbol("MEM_SIZE", options[:memory_size])
		compiler.add_predefined_symbol("MAX_THREADS", options[:max_threads])
		compiler.add_predefined_symbol("MAX_CYCLES", options[:cycles_to_completion])
		compiler.add_predefined_symbol("MAX_LENGTH", options[:max_program_length])
		compiler.add_predefined_symbol("MIN_DISTANCE", options[:min_program_distance])
		
		return compiler
	end

	# Verify the passed virus file (expect an array with a single one)
	def self.verify(options, virus_files)	
		if virus_files.length != 1
			$stderr.puts("Expect exactly one virus when verifying")
			exit(1)
		end
		virus_file = virus_files[0]
		
		# We only need the compiler, but create both to get the 
		# predefined variables set up properly.
		compiler = create_compiler(options)		
		compiler.add_predefined_symbol("VIRUSES", 1)
		compiler.add_predefined_symbol("ROUNDS", 1)
		
		compiled_program = compiler.compile_file(virus_file)
		if compiler.warnings > 0
			$stderr.puts("Got #{compiler.warnings} warnings")
		end
		if compiler.errors > 0
			$stderr.puts("Got #{compiler.errors} errors")
			exit 1
		end

		if options[:verbose]
			puts("")
			puts("Start offset is: #{compiled_program.start_offset}")
			puts("")
			puts("Offset\tMachine code\tDecompiled")
			puts("===============================================")
			address = 0
			compiled_program.instructions.each do |instruction|
				stmt = compiler.decompile_instruction(instruction)
				puts("%4d\t%04x.%04x\t%s" % [address, (instruction << 16) & 0xffff, instruction & 0xffff, stmt])
				address += 1
			end
		end
	end

	# Run a single match with the passed array of virus files.
	def self.run_single_match(options, virus_files, debug)
		vm = create_vm(options)
		compiler = create_compiler(options)
		compiler.add_predefined_symbol("VIRUSES", virus_files.length)
		compiler.add_predefined_symbol("ROUNDS", 1)

		# Compile all viruses
		virus_files.each do |virus_file|
			compiled_program = compiler.compile_file(virus_file)
			if compiler.errors > 0
				$stderr.puts("Failed to compile: #{virus_file}")
				exit 1
			end
			vm.add_program(File.basename(virus_file), compiled_program)
		end

		# Start running
		listener = nil
		if debug
			listener = PrintingExecutionListener.new(options[:verbose])
		else
			listener = ResultExecutionListener.new(options[:verbose])
		end
		vm.run(listener)
	end

	def self.tournament(options, virus_files)
		vm = create_vm(options)
		
		compiler = create_compiler(options)
		compiler.add_predefined_symbol("VIRUSES", options[:viruses_per_match])
		compiler.add_predefined_symbol("ROUNDS", options[:rounds_per_setup])
		
		tournament = Tournament.new()
		Tournament.viruses_per_match = options[:viruses_per_match]
		Tournament.rounds_per_setup = options[:rounds_per_setup]
		
		# Compile all viruses
		virus_files.each do |virus_file|
			compiled_program = compiler.compile_file(virus_file)
			if compiler.errors > 0
				$stderr.puts("Failed to compile: #{virus_file}")
				exit 1
			end
			tournament.add_program(File.basename(virus_file), compiled_program)
		end

		# Start running
		tournament.run(vm);
	end

	def self.run(argv)
	
		# Set default values for options
		options = Hash.new()
		options[:memory_size] = Machine::DEFAULT_MEMORY_SIZE
		options[:max_threads] = Machine::DEFAULT_MAX_THEADS
		options[:cycles_to_completion] = Machine::DEFAULT_CYCLES_TO_COMPLETION
		options[:max_program_length] = Machine::DEFAULT_MAX_PROGRAM_LENGTH
		options[:min_program_distance] = Machine::DEFAULT_MIN_PROGRAM_DISTANCE
		options[:viruses_per_match] = Tournament::DEFAULT_VIRUSES_PER_MATCH
		options[:rounds_per_setup] = Tournament::ROUNDS_PER_SETUP
		
		# Parse options		
		OptionParser.new do |opts|
			opts.banner = "Usage: pandemia.rb <action> [options] <input files>...

This is the fontend for pandemia and can be used to verify, test,
run single matches and run a full tournament. If you're in a hurry,
just type the first letter of the action.

Actions:
  verify      Try to compile the virus and tell if the virus is ok
  debug       Test to run one or more viruses and get a detailed log
  run         Run a match between one or more viruses and get result
  tournament  TODO - Run a full tournament with two or more viruses
  
Options:"

			opts.on("-v", "--verbose", "Verbose output") do |v|
				options[:verbose] = v
			end
			opts.on("-s", "--size N", OptionParser::DecimalInteger, "Memory size, default is #{Machine::DEFAULT_MEMORY_SIZE}") do |n|
				options[:memory_size] = n
			end
			opts.on("-t", "--threads N", OptionParser::DecimalInteger, "Max total number of threads, default is #{Machine::DEFAULT_MAX_THEADS}") do |n|
				options[:max_threads] = n
			end
			opts.on("-c", "--cycles N", OptionParser::DecimalInteger, "Cycles to completion, default is #{Machine::DEFAULT_CYCLES_TO_COMPLETION}") do |n|
				options[:cycles_to_completion] = n
			end
			opts.on("-l", "--length N", OptionParser::DecimalInteger, "Max program length, default is #{Machine::DEFAULT_MAX_PROGRAM_LENGTH}") do |n|
				options[:max_program_length] = n
			end
			opts.on("-d", "--distance N", OptionParser::DecimalInteger, "Min program distance, default is #{Machine::DEFAULT_MIN_PROGRAM_DISTANCE}") do |n|
				options[:min_program_distance] = n
			end
			opts.on("-n", "--viruses N", OptionParser::DecimalInteger, "Number of viruses per match, default is ?") do |n|
				options[:viruses_per_match] = n
			end
			opts.on("-r", "--rounds N", OptionParser::DecimalInteger, "Number of rounds for each setup, default is ?") do |n|
				options[:rounds_per_permutation] = n
			end
			opts.on_tail("-h", "--help", "Show this message") do
				puts(opts)
				exit(0)
			end	
		end.parse!(argv)

		# Fetch action
		action = argv.shift()
		if action.nil? then
			$stderr.puts("No action specified, see help (-h)")
			exit(1)
		end

		# Rest of the input should be the viruses...
		virus_files = argv
		if virus_files.length == 0
			$stderr.puts("No virus files, see help (-h)")
			exit(1)
		end

		# Dispatch action
		action = action.downcase
		if "verify".start_with?(action)
			verify(options, virus_files)
		elsif "debug".start_with?(action)
			run_single_match(options, virus_files, true)
		elsif "run".start_with?(action)
			run_single_match(options, virus_files, false)
		elsif "tournament".start_with?(action)
			tournament(options, virus_files)
		else
			$stderr.puts("Unknown action: #{action}")
			help()
			exit(1)
		end
	end
end
	
if __FILE__ != $0
	raise("You are supposed to run this script directly!")
end

Pandemia.run(ARGV)
