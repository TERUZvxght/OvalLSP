# frozen_string_literal: true

module Ovallsp
  module Index
    # `alias new old` or `alias_method :new, :old` found inside `owner`.
    # `singleton` mirrors Declaration's instance/singleton split: true for
    # an alias inside `class << self` or targeting a `def self.` method
    # (best-effort — only the lexical `class << self` context is tracked,
    # matching ParserService's own singleton-context detection).
    AliasFact = Data.define(:owner, :new_name, :old_name, :singleton, :location)
  end
end
