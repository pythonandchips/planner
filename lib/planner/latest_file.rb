# frozen_string_literal: true

module Planner
  # The file a command uses when it is given a plan folder instead of a file.
  module LatestFile
    # Any numbered plan folder file: its kind, number and letters.
    NAME = /\A(?<kind>[A-Z]+)-(?<number>\d+)(?:-(?<letters>[a-z]+))?\.md\z/

    # path itself when it is not a folder. Otherwise the folder's file whose name matches accepted with the
    # highest number, then the last letter. kinds names the accepted files in errors, e.g. "PLAN-<N>.md".
    def self.resolve(path, accepted, kinds)
      return path unless File.directory?(path)

      names = Dir.children(path).select { |name| File.file?(File.join(path, name)) && accepted.match?(name) }
      raise Error, "#{path} has no #{kinds} file" if names.empty?

      latest = latest_per_kind(names)
      if latest.size > 1
        raise Error, "#{path} has more than one latest file: #{latest.sort.join(', ')}; give the file instead"
      end

      File.join(path, latest.first)
    end

    # The last name of each kind among those with the highest number.
    def self.latest_per_kind(names)
      parsed = names.to_h { |name| [name, NAME.match(name)] }
      top = highest(parsed)
      top.group_by { |_, match| match[:kind] }.each_value.map { |group| last_letters(group) }
    end
    private_class_method :latest_per_kind

    # The [name, match] pairs of parsed with the highest number.
    def self.highest(parsed)
      highest = parsed.each_value.map { |match| match[:number].to_i }.max
      parsed.select { |_, match| match[:number].to_i == highest }
    end
    private_class_method :highest

    # The name in group, a list of [name, match] pairs, with the last letters.
    def self.last_letters(group) = group.max_by { |_, match| letters_order(match[:letters]) }.first
    private_class_method :last_letters

    # Base first, then by letter length, then alphabetically.
    def self.letters_order(letters) = [letters.to_s.length, letters.to_s]
    private_class_method :letters_order
  end
end
