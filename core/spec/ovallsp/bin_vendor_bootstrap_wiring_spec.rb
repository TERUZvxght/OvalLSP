# frozen_string_literal: true

require "prism"

# `VendorBootstrap` exists so the which-directories decision can be
# tested, and its own spec tests it thoroughly. None of that reaches a
# user unless `bin/ovallsp` actually calls it -- and the branch this
# landed from recorded that call as unpinned rather than fixed (029's
# M-1 names it). Deleting the call, or restoring the `**` glob it
# replaced, leaves every other example in this suite green while a
# two-Ruby checkout goes back to loading the other ABI's native prism.
#
# Asserted against the *parsed* script rather than its text: a text
# match stays green when the call is commented out, which is the dodge
# merge round 6 of 0.2.3 found in a different guard. Prism is already a
# runtime dependency, so this costs nothing extra.
RSpec.describe "bin/ovallsp's vendor bootstrap wiring" do
  BIN_PATH = File.expand_path("../../bin/ovallsp", __dir__)

  let(:source) { File.read(BIN_PATH, encoding: "UTF-8") }
  let(:parsed) { Prism.parse(source) }

  def call_nodes(node, found = [])
    return found unless node.is_a?(Prism::Node)

    found << node if node.is_a?(Prism::CallNode)
    node.compact_child_nodes.each { |child| call_nodes(child, found) }
    found
  end

  let(:calls) { call_nodes(parsed.value) }

  it "parses at all" do
    expect(parsed.success?).to be(true), -> { parsed.errors.map(&:message).join("\n") }
  end

  it "delegates the bootstrap to VendorBootstrap.activate!" do
    activate = calls.find do |call|
      call.name == :activate! &&
        call.receiver.is_a?(Prism::ConstantPathNode) &&
        call.receiver.name == :VendorBootstrap
    end

    expect(activate).not_to be_nil,
                            "bin/ovallsp no longer calls Ovallsp::VendorBootstrap.activate! -- " \
                            "the ABI-scoping decision has left the one place that is tested for it"
  end

  it "passes it both the vendor root and the manifest, by keyword" do
    activate = calls.find { |call| call.name == :activate! }
    keywords = activate.arguments.arguments.grep(Prism::KeywordHashNode)
                       .flat_map { |hash| hash.elements.map { |pair| pair.key.unescaped.to_sym } }

    expect(keywords).to include(:vendor_root, :manifest_path)
  end

  # The specific shape that was wrong: a glob whose `**` spans every ABI
  # directory under vendor/bundle. VendorBootstrap scopes by engine and
  # `RbConfig::CONFIG["ruby_version"]` instead, so the script itself
  # should be doing no path globbing at all any more.
  it "does its own globbing nowhere" do
    globs = calls.select { |call| call.name == :glob }

    expect(globs).to be_empty,
                     "bin/ovallsp globs for load paths again -- that decision belongs to " \
                     "VendorBootstrap, which scopes it to the running interpreter's ABI"
  end
end
