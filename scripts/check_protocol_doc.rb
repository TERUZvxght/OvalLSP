#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# Keeps `docs/design/docs/05-protocol.md` and the Runtime Agent in the same
# conversation.
#
# **The chain that broke.** 0.3.0 added `agent/gemIndex`, bumped
# `PROTOCOL_VERSION` from 1 to 2, and shipped a capability that depends on
# both. The protocol document was not touched: it still said
# `"protocolVersion": 1`, had no section for the new request, and had none
# for `agent/status` or `agent/ancestors` either. Nothing noticed, because
# `docs/DOCUMENTATION_MAP.md`'s row for this file is one of the eight whose
# "Checked by" column reads as nothing at all.
#
# It fails in the other direction too, and that half is worse. Seven methods
# the document specifies -- `agent/routeLocation`, `agent/restartRequired`,
# `agent/plugin/request`, `agent/progress`, `agent/invalidated`,
# `agent/log`, `agent/runtimeChanged` -- appear nowhere in `core/lib`. Six of
# the seven read as an ordinary specification, with a request shape and a
# response shape, so a reader cannot tell them from the five that are real.
# The map's own row says a section describing something unimplemented has to
# say so *in the section*; nothing enforced it.
#
# So three questions, each of which had a wrong answer when this was written:
#
#   1. Does the version in the code match every version the document states?
#   2. Does every method the Agent dispatches have a section?
#   3. Does every section name something that exists, or say that it does not?
#
# **Why the whole of `core/lib` and not just the dispatch table.** A
# notification is sent, not dispatched, so it never appears in the Agent's
# `case`. Asking whether the name appears anywhere in the Core's own source
# is the question that covers both directions without needing to know which
# side sends it.
#
# Usage: ruby scripts/check_protocol_doc.rb
# Exits non-zero, listing every problem found.

require "set"

module ProtocolDoc
  ROOT = File.expand_path("..", __dir__)
  AGENT_PATH = "core/lib/ovallsp/runtime_agent/agent.rb"
  DOC_PATH = "docs/design/docs/05-protocol.md"
  LIB_DIR = "core/lib"

  # A method name as this protocol spells one. `[A-Za-z/]` rather than `\w`
  # because `agent/plugin/request` has two segments and no underscores or
  # digits appear in any of them -- and because a greedy match is what keeps
  # `agent/model` from matching inside `agent/models`.
  METHOD = %r{agent/[A-Za-z]+(?:/[A-Za-z]+)*}

  # What a section says when it is describing something nobody has built.
  # Both languages, because this document is written in Japanese and the
  # rule it serves is stated in English.
  UNIMPLEMENTED = /未実装|将来用途|未実装予定|not implemented|unimplemented|not yet implemented/

  module_function

  # The methods the Agent answers, from its dispatch.
  def dispatched(agent_source)
    agent_source.scan(/^\s*when "(#{METHOD})"/).flatten.uniq.sort
  end

  def protocol_version(agent_source)
    agent_source[/PROTOCOL_VERSION\s*=\s*(\d+)/, 1]
  end

  def documented_versions(doc)
    doc.scan(/"protocolVersion":\s*(\d+)/).flatten.uniq
  end

  # Each `### agent/x` heading and the body under it, up to the next heading
  # of any level. The body is what carries the unimplemented marker, so it
  # has to be the whole body and not the first line.
  def sections(doc)
    result = {}
    current = nil
    doc.each_line do |line|
      if (m = line.match(/\A\#{2,4}\s+`?(#{METHOD})`?\s*\z/))
        current = m[1]
        result[current] = +""
      elsif line.start_with?("#")
        current = nil
      elsif current
        result[current] << line
      end
    end
    result
  end

  # Every protocol method named anywhere in the Core's own source. A
  # notification is sent rather than dispatched, so this is the question
  # that covers both directions.
  def mentioned_in_lib(lib_sources)
    lib_sources.flat_map { |src| src.scan(METHOD) }.to_set
  end

  # The whole verdict, as data, so the decision is testable without a tree.
  def problems(agent_source:, doc:, lib_sources:)
    found = []

    code_version = protocol_version(agent_source)
    if code_version.nil?
      found << "#{AGENT_PATH} states no PROTOCOL_VERSION, so there is nothing to compare the document against"
    else
      stated = documented_versions(doc)
      if stated.empty?
        found << "#{DOC_PATH} states no protocolVersion, so a bump to #{code_version} cannot be noticed here"
      else
        wrong = stated.reject { |v| v == code_version }
        unless wrong.empty?
          found << "#{DOC_PATH} says protocolVersion #{wrong.join(', ')} and the Agent says #{code_version}"
        end
      end
    end

    documented = sections(doc)
    dispatched(agent_source).each do |method|
      found << "`#{method}` is dispatched by the Agent and has no section in #{DOC_PATH}" unless documented.key?(method)
    end

    in_lib = mentioned_in_lib(lib_sources)
    documented.each do |method, body|
      next if in_lib.include?(method)
      next if body.match?(UNIMPLEMENTED)

      found << "#{DOC_PATH} specifies `#{method}`, nothing in #{LIB_DIR} names it, and the section does not say " \
               "it is unimplemented -- so it reads as a specification somebody may implement"
    end

    found
  end

  def lib_sources(root = ROOT)
    Dir.glob(File.join(root, LIB_DIR, "**", "*.rb")).sort.map { |p| File.read(p, encoding: "UTF-8") }
  end

  def run(root = ROOT)
    agent_path = File.join(root, AGENT_PATH)
    doc_path = File.join(root, DOC_PATH)
    [agent_path, doc_path].each do |p|
      unless File.file?(p)
        warn "check-protocol-doc: #{p} is not there, so this check cannot see what it checks"
        return 1
      end
    end

    agent_source = File.read(agent_path, encoding: "UTF-8")
    doc = File.read(doc_path, encoding: "UTF-8")
    sources = lib_sources(root)

    found = problems(agent_source: agent_source, doc: doc, lib_sources: sources)

    # The census, printed whether or not anything is wrong: a check that
    # reads nothing reports exactly what a passing check reports.
    puts "check-protocol-doc: protocol version #{protocol_version(agent_source)}, " \
         "#{dispatched(agent_source).length} dispatched, #{sections(doc).length} documented, " \
         "#{sources.length} file(s) read from #{LIB_DIR}."

    if found.empty?
      puts "check-protocol-doc: the document and the Agent agree."
      0
    else
      warn "check-protocol-doc: #{found.length} problem(s):"
      found.each { |p| warn "  - #{p}" }
      warn "check-protocol-doc: add the section, correct the version, or say in the section that nothing implements it."
      1
    end
  end
end

exit ProtocolDoc.run if $PROGRAM_NAME == __FILE__
