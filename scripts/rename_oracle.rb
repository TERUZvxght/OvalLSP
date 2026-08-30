#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "prism"
require "stringio"

require_relative "utf8"

# Renames every local variable in a corpus and checks that the file still
# means what it meant.
#
# For each local-variable binding in each file: ask the real Server for
# `textDocument/rename` to a fresh name, apply the edits it hands back,
# re-parse, and compare the two syntax trees with the new name mapped
# back to the old one. Two things can go wrong, and they are counted
# separately because they are not equally bad:
#
#   * **unparseable** -- the edited file no longer parses. The editor
#     handed the user a file that does not run.
#   * **meaning-changed** -- it parses, and its tree differs by more than
#     the name. The editor handed the user a file that runs and does
#     something else, which is the worse of the two to *notice*.
#
# **Why this exists.** 0.2.17 fixed nine shapes of local rename, and
# every one of them had a passing spec beside it. A spec asserts the
# edits; none of them could see a file that stops running, because that
# is a property of the program and not of the edit list. `CLAUDE.md`'s
# same-place rule was fired twice by the scope-frame work and asks for a
# mechanical countermeasure rather than a third hand-fix; this is it.
#
# The name is same-length and unique so the comparison is about meaning
# rather than about offsets, and so a partial rewrite is visible as a
# tree difference rather than hidden by a coincidental collision.
#
# Usage:
#
#   cd core && bundle exec ruby ../scripts/rename_oracle.rb <dir-or-file>...
#   cd core && bundle exec ruby ../scripts/rename_oracle.rb --json <dir>
#
# Nothing is written to the corpus: every edit is applied to a string.
module RenameOracle
  module_function

  # A name nothing in the file uses, so a leftover occurrence of the old
  # one is unambiguous. Derived from the old name rather than from a
  # counter, so a failure report names something a reader can find.
  def fresh_name(old)
    "zzz#{old}zzz"
  end

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  # Every local-variable node's name, in source order. This is the
  # comparison, and getting it right took two attempts.
  #
  # **Not `Prism::Node#inspect`.** That embeds source offsets, which
  # shift the moment the new name is a different length from the old one
  # -- so the first version reported every correct rename in the corpus
  # as a change of meaning. A tree comparison here has to be about
  # structure, and `inspect` is not.
  #
  # **And not the whole tree either.** The renamer legitimately changes
  # structure in one place: Ruby's hash shorthand. `{ name: }` is an
  # `ImplicitNode` wrapping a read, and the only edit that preserves
  # meaning writes `{ name: label }`, which is an ordinary assoc. Any
  # whole-tree comparison calls that a change of meaning; it is the fix
  # `024.272` shipped.
  #
  # So the subject is the sequence of local-variable *names*, which is
  # what a rename is about and what every one of 0.2.17's nine shapes got
  # wrong.
  def local_names(source)
    result = Prism.parse(source)
    return nil unless result.success?

    names = []
    walk = lambda do |node|
      return unless node.is_a?(Prism::Node)

      names << node.name.to_s if LOCAL_NODES.any? { |kind| node.is_a?(kind) }
      node.compact_child_nodes.each { |child| walk.call(child) }
    end
    walk.call(result.value)
    names
  end

  # Prism's six local-variable node kinds. Four of them were unread by
  # Find References and Rename until `024.266`, which is why the list is
  # spelled out rather than inferred from a name pattern.
  LOCAL_NODES = [
    Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode,
    Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
    Prism::LocalVariableAndWriteNode, Prism::LocalVariableTargetNode
  ].freeze

  # How many scopes in the file bind this name. A rename is only
  # unambiguous to check when the answer is one: with the same name bound
  # in two scopes, an occurrence left as the old name may be the *other*
  # binding and correctly untouched.
  def scopes_binding(source, name)
    result = Prism.parse(source)
    return 0 unless result.success?

    count = 0
    walk = lambda do |node|
      return unless node.is_a?(Prism::Node)

      count += 1 if node.respond_to?(:locals) && !node.is_a?(Prism::BlockParametersNode) &&
                    node.locals.map(&:to_s).include?(name)
      node.compact_child_nodes.each { |child| walk.call(child) }
    end
    walk.call(result.value)
    count
  end

  def local_binding_positions(source)
    result = Prism.parse(source)
    return [] unless result.success?

    found = []
    walk = lambda do |node|
      return unless node.is_a?(Prism::Node)

      if node.is_a?(Prism::LocalVariableWriteNode)
        found << [node.name.to_s, node.name_loc]
      end
      node.compact_child_nodes.each { |child| walk.call(child) }
    end
    walk.call(result.value)
    found
  end

  # **The caret, in the coordinate system LSP actually uses**, and this
  # was wrong in the oracle's first two runs.
  #
  # The first version sliced the whole source by *characters* up to
  # Prism's `start_offset`, which is a **byte** offset. Any multi-byte
  # character anywhere earlier in the file moved the caret, and the
  # server then answered about whatever symbol it landed on --
  # `activesupport`'s `redis_cache_store.rb` put it on `failsafe` and the
  # run recorded ten edits renaming a *method* as a failed local rename.
  # Every number the oracle produced before this was part measurement and
  # part that.
  #
  # Prism gives the line and the byte column within it directly, and the
  # column is converted to UTF-16 units per line -- the same conversion
  # `Index::SourceLocation.to_position` makes, because it is the
  # protocol's rule rather than this engine's choice. Reading it from the
  # engine's own recorded range instead would make the caret depend on
  # the thing under test.
  def caret_of(location)
    [location.start_line - 1, utf16_column(location.slice_lines.lines.first || "", location.start_column)]
  end

  def utf16_column(line, byte_column)
    return 0 if byte_column <= 0
    return byte_column if line.ascii_only?

    prefix = line.byteslice(0, byte_column) || ""
    prefix.encode("UTF-16LE", invalid: :replace, undef: :replace).bytesize / 2
  end

  def apply(source, edits)
    lines = source.lines
    edits.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }.each do |edit|
      index = edit[:range][:start][:line]
      return nil unless lines[index]

      lines[index] = lines[index].dup
      lines[index][edit[:range][:start][:character]...edit[:range][:end][:character]] = edit[:newText]
    end
    lines.join
  end

  def rename_once(uri, source, name, location, new_name)
    line, character = caret_of(location)
    input =
      frame(jsonrpc: "2.0", method: "textDocument/didOpen",
            params: { textDocument: { uri: uri, text: source, version: 1, languageId: "ruby" } }) +
      frame(jsonrpc: "2.0", id: 1, method: "textDocument/rename",
            params: { textDocument: { uri: uri }, position: { line: line, character: character },
                      newName: new_name }) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    output = StringIO.new
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: SilentLogger.new).run
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end
    answer = messages.find { |m| m[:id] == 1 }
    answer&.dig(:result, :changes, uri.to_sym)
  end

  # A rename that produces no edits is a *refusal*, and a refusal is the
  # safe answer -- section 0.4 ranks it above a wrong one. Counted, not
  # failed on.
  def check_file(path)
    source = File.read(path, encoding: "UTF-8")
    return nil unless Prism.parse(source).success?

    counts = { renames: 0, refused: 0, shadowed: 0, unparseable: 0, meaning_changed: 0 }
    details = []
    uri = "file://#{File.expand_path(path)}"

    local_binding_positions(source).each do |name, location|
      new_name = fresh_name(name)
      next if source.include?(new_name)

      # See `#scopes_binding`: with one name bound in two scopes, a
      # leftover cannot be told from a correctly untouched occurrence of
      # the other binding, so this file's answer would be a guess.
      if scopes_binding(source, name) != 1
        counts[:shadowed] += 1
        next
      end

      counts[:renames] += 1
      edits = rename_once(uri, source, name, location, new_name)
      if edits.nil? || edits.empty?
        counts[:refused] += 1
        next
      end

      edited = apply(source, edits)
      if edited.nil? || local_names(edited).nil?
        counts[:unparseable] += 1
        details << "#{path}: renaming `#{name}` leaves the file unparseable"
        next
      end

      before = local_names(source)
      after = local_names(edited)

      # **Two conditions, and the second one is the one that matters.**
      #
      # Mapping the new name back and comparing sequences catches a
      # rename that moved a name it was not asked to. It does *not* catch
      # a partial one: an occurrence left behind still reads `name`, and
      # so does the same position in the before-sequence, so the two
      # compare equal. The first version of this check had only that
      # comparison and reported the pre-0.2.17 tree clean on the very
      # shapes 0.2.17 was about.
      #
      # So a leftover is its own condition. `#scopes_binding` has already
      # established that exactly one scope binds this name, which is what
      # makes "the old name still appears" mean "an occurrence of *this*
      # binding was missed" rather than "another binding kept its name".
      complete = after.count(name).zero? && after.count(new_name) == before.count(name)
      next if complete && after.map { |n| n == new_name ? name : n } == before

      counts[:meaning_changed] += 1
      left = after.count(name)
      lost = before.count(name) - after.count(new_name)
      details << if left.positive?
                   "#{path}: renaming `#{name}` leaves #{left} occurrence(s) behind"
                 elsif lost.positive?
                   # The binding's *declaration* was not rewritten, so the
                   # uses that were renamed now name nothing -- Prism reads
                   # a bare identifier with no binding as a call, which is
                   # why they leave the local set entirely. `024.273`: a
                   # parameter's own range is not recorded, and this is
                   # what that costs, seen from the other end.
                   "#{path}: renaming `#{name}` leaves the binding behind, so #{lost} use(s) stop resolving"
                 else
                   "#{path}: renaming `#{name}` moves a name it was not asked to"
                 end
    end

    [counts, details]
  end

  class SilentLogger
    def info(*) = nil
    def warn(*) = nil
    def error(*) = nil
    def debug(*) = nil
  end
end

if $PROGRAM_NAME == __FILE__
  require "ovallsp"

  as_json = ARGV.delete("--json")
  roots = ARGV
  if roots.empty?
    warn "usage: rename_oracle.rb [--json] <dir-or-file>..."
    exit 2
  end

  files = roots.flat_map { |root| File.directory?(root) ? Dir.glob(File.join(root, "**", "*.rb")) : [root] }.sort
  totals = Hash.new(0)
  all_details = []
  files.each do |path|
    counts, details = RenameOracle.check_file(path)
    next unless counts

    totals[:files] += 1
    counts.each { |key, value| totals[key] += value }
    all_details.concat(details)
  end

  if as_json
    puts JSON.generate(totals)
  else
    warn "rename-oracle: files=#{totals[:files]} renames=#{totals[:renames]} " \
         "refused=#{totals[:refused]} shadowed=#{totals[:shadowed]} " \
         "unparseable=#{totals[:unparseable]} " \
         "meaning-changed=#{totals[:meaning_changed]}"
    all_details.first(40).each { |line| warn "  #{line}" }
    warn "  ... #{all_details.length - 40} more" if all_details.length > 40
  end

  exit(totals[:unparseable].zero? ? 0 : 1)
end
