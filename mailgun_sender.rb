#!/usr/bin/env ruby

# Mailgun CLI Bulk Email Sender
# A command-line tool for sending bulk emails via Mailgun API

require 'bundler/setup'
require_relative 'lib/cli_interface'

# Set up signal handling for graceful interruption
Signal.trap('INT') do
  puts "\nOperation cancelled by user."
  exit 1
end

Signal.trap('TERM') do
  puts "\nOperation terminated."
  exit 1
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    cli = CliInterface.new
    cli.run
  rescue LoadError => e
    puts 'Error: Missing required dependencies.'
    puts 'Please run: bundle install'
    puts "Details: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "Unexpected error: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
    exit 1
  end
end
