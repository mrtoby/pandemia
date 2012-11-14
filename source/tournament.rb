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
 
	attr_accessor :viruses_per_match, :rounds_per_setup
	
	# Create a tournament
	def initialize()
		# TODO	
	end
	
	def add_program(name, compiled_program)
		# TODO
	end
	
	def run(vm)
		raise("Not implemented!")
	end
	
end
