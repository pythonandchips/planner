# frozen_string_literal: true

module Planner
  # Dispatches argv to a command and turns errors into exit statuses.
  class CLI
    COMMANDS = {
      'new' => Commands::New,
      'plan' => Commands::Plan,
      'run' => Commands::Run,
      'review' => Commands::Review
    }.freeze

    USAGE = <<~TEXT
      usage: planner new <given-name>
             planner plan <iteration-file>
             planner run [--model <model>] <plan-file>
             planner review [--model <model>] [--lens <text>|-] <plan-file>
    TEXT

    def initialize(context:, stderr: $stderr)
      @context = context
      @stderr = stderr
    end

    def call(argv)
      command = COMMANDS[argv.first] or raise UsageError
      command.new(@context).call(argv.drop(1))
      0
    rescue UsageError
      @stderr.print USAGE
      1
    rescue Error => e
      @stderr.puts "[planner] #{e.message}"
      1
    end
  end
end
