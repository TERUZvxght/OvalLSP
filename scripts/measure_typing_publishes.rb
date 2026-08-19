#!/usr/bin/env ruby
# frozen_string_literal: true

# Counts how many `publishDiagnostics` a burst of edits produces, and how
# long the burst takes to go quiet -- 037's C9 measured rather than
# recalled. 0.2.8's drive round reported 22 publishes for one method name
# typed on a 4,006-line file, and that number has not been re-derived
# since; C9 is not worth building against a number nobody can reproduce
# (CLAUDE.md, "a measurement is a claim").
#
#   ruby scripts/measure_typing_publishes.rb [file-to-type-into] [keystrokes] [interval-seconds]
#
# Drives a real server over a pipe, exactly as the client does: initialize,
# didOpen, then one didChange per keystroke at a fixed interval, then wait
# for the stream to go quiet.
require "open3"
require "json"

ROOT = File.expand_path("..", __dir__)
TARGET = ARGV[0] || File.join(ROOT, "core", "lib", "ovallsp", "server.rb")
KEYSTROKES = (ARGV[1] || "10").to_i
INTERVAL = (ARGV[2] || "0.15").to_f
QUIET_AFTER = 8.0

abort "no such file: #{TARGET}" unless File.file?(TARGET)

text = File.read(TARGET, encoding: Encoding::UTF_8)
puts "measure-typing-publishes: #{TARGET} (#{text.lines.size} lines), " \
     "#{KEYSTROKES} keystrokes #{INTERVAL}s apart"
puts "measure-typing-publishes: cwd #{Dir.pwd}, version #{File.read(File.join(ROOT, 'core/lib/ovallsp/version.rb'))[/"([^"]+)"/, 1]}"
# Which code this side actually ran, printed before it runs rather than
# assumed afterwards -- three of this project's corpus comparisons were
# false because both sides ran the same tree (CLAUDE.md).
puts "measure-typing-publishes: HEAD #{`git -C #{ROOT} rev-parse --short HEAD`.strip}, " \
     "server.rb #{`git -C #{ROOT} diff --stat -- core/lib/ovallsp/server.rb core/lib/ovallsp/io/framed_reader.rb`.strip.empty? ? 'clean' : 'MODIFIED'}"

def frame(message)
  body = JSON.generate(message)
  "Content-Length: #{body.bytesize}\r\n\r\n#{body}"
end

uri = "file://#{TARGET}"
publishes = []
hovers = {}
started = nil

Open3.popen3({ "OVALLSP_DISABLE_CACHE" => "1" }, "bundle", "exec", "ruby", "-Ilib", "bin/ovallsp", "--stdio",
             chdir: File.join(ROOT, "core")) do |stdin, stdout, stderr, _thread|
  reader = Thread.new do
    loop do
      header = +""
      header << stdout.readpartial(1) while !header.end_with?("\r\n\r\n")
      length = header[/Content-Length: (\d+)/, 1].to_i
      message = JSON.parse(stdout.read(length))
      publishes << [Time.now, message.dig("params", "version")] if message["method"] == "textDocument/publishDiagnostics"
      hovers[message["id"]] = Time.now if message["id"] && hovers.key?(message["id"])
    rescue EOFError, IOError
      break
    end
  end
  Thread.new { stderr.each_line { |l| warn "core: #{l}" } }

  stdin.write(frame(jsonrpc: "2.0", id: 1, method: "initialize",
                    params: { rootUri: "file://#{ROOT}", capabilities: {} }))
  stdin.write(frame(jsonrpc: "2.0", method: "initialized", params: {}))
  sleep 5

  stdin.write(frame(jsonrpc: "2.0", method: "textDocument/didOpen",
                    params: { textDocument: { uri: uri, languageId: "ruby", version: 1, text: text } }))
  # Wait for the *initial* workspace pass to go quiet before starting.
  # Without this the count is dominated by the cold pass over the whole
  # repository, which typing did not cause: a first run measured 179
  # publishes and 169 of them were that pass still arriving. A baseline
  # that has not settled is not a baseline (CLAUDE.md, "a measurement is
  # a claim").
  quiet_since = Time.now
  loop do
    last = publishes.map(&:first).max
    quiet_since = last if last && last > quiet_since
    break if Time.now - quiet_since > 5
    break if Time.now - quiet_since > 240

    sleep 1
  end
  puts "measure-typing-publishes: baseline settled after #{publishes.size} publish(es); starting to type"
  publishes.clear
  started = Time.now

  # A hover sent *during* the burst, timed. This is the number C9 is
  # actually about: every analysis runs on the dispatch thread holding
  # `@index_mutation_mutex`, which is the lock a hover needs, so an
  # analysis about text the developer has already moved past is paid for
  # by the next question they ask. Wasted work nobody waits on is cheap;
  # wasted work in front of the answer is not.
  hover_asked = {}
  KEYSTROKES.times do |i|
    stdin.write(frame(jsonrpc: "2.0", method: "textDocument/didChange",
                      params: { textDocument: { uri: uri, version: i + 2 },
                                contentChanges: [{ text: "#{text}\n# typing#{'x' * (i + 1)}\n" }] }))
    asked = Time.now
    hover_id = 100 + i
    hovers[hover_id] = nil
    stdin.write(frame(jsonrpc: "2.0", id: hover_id, method: "textDocument/hover",
                      params: { textDocument: { uri: uri }, position: { line: 0, character: 8 } }))
    hover_asked[hover_id] = asked
    sleep INTERVAL
  end
  finished_typing = Time.now

  sleep QUIET_AFTER
  stdin.write(frame(jsonrpc: "2.0", id: 2, method: "shutdown", params: {}))
  stdin.write(frame(jsonrpc: "2.0", method: "exit", params: {}))
  reader.join(5)

  puts
  puts "keystrokes:            #{KEYSTROKES}"
  puts "publishes after them:  #{publishes.size}"
  puts "versions published:    #{publishes.map(&:last).inspect}"
  quiet = publishes.map(&:first).max
  puts "typing took:           #{format('%.2f', finished_typing - started)} s"
  puts "last publish:          #{quiet ? format('%.2f', quiet - finished_typing) : 'n/a'} s after the last keystroke"
  hover_latencies = hover_asked.map { |id, asked| hovers[id] ? hovers[id] - asked : nil }
  answered = hover_latencies.compact
  puts "hovers answered:       #{answered.size} of #{hover_latencies.size}"
  unless answered.empty?
    puts "hover latency:         min #{format('%.3f', answered.min)} s, " \
         "median #{format('%.3f', answered.sort[answered.size / 2])} s, max #{format('%.3f', answered.max)} s"
  end
end
