# frozen_string_literal: true

require_relative "../../../scripts/repo_files"

# **One converter, and two places that did not use it.**
#
# `UriUtil.from_path` escapes: a `#` in a path is a URI *fragment*, so a
# workspace under a directory named with one produced a URI whose path
# stopped at the `#`, and `UriUtil.to_path` did not come back to a file
# that exists. The signature loaders built their URIs by hand --
# `"file://#{path}"` -- and skipped all of it, so RBS and RBI go-to-
# definition targets were unopenable there.
#
# `UriUtil`'s own header records the same defect being fixed once before,
# in `#from_path`; having the converter is not the same as every path
# going through it. Found by the 2026-09-05 critical review, R10.
#
# The rule reads the shape rather than the two files, because a list of
# the places somebody has already looked is what would rot.
RSpec.describe "a file URI built by hand" do
  ROOT_FOR_FILE_URI = File.expand_path("../../..", __dir__)

  # `uri_util.rb` is the converter: it is where the string is allowed to
  # be written, and the one place a reader looking for the rule will find
  # it.
  CONVERTER = "core/lib/ovallsp/uri_util.rb"

  def self.ruby_sources
    RepoFiles.list(ROOT_FOR_FILE_URI, "*.rb")
             .select { |path| path.start_with?("core/lib/") }
             .reject { |path| path == CONVERTER }
  end

  it "is reading the library, not an empty list" do
    expect(self.class.ruby_sources.length).to be > 50
    expect(self.class.ruby_sources).to include("core/lib/ovallsp/server.rb")
  end

  it "appears nowhere in core/lib outside the converter" do
    offenders = self.class.ruby_sources.flat_map do |relative|
      File.read(File.join(ROOT_FOR_FILE_URI, relative), encoding: "UTF-8").lines.each_with_index.filter_map do |line, i|
        # The interpolating form only: a fixed `"file:///a.rb"` in a
        # comment or a fixture name is not a path being converted.
        ["#{relative}:#{i + 1}  #{line.strip}"] if line.include?('file://#{')
      end
    end.flatten

    expect(offenders).to be_empty, lambda {
      "these build a file URI by hand instead of through UriUtil.from_path:\n#{offenders.join("\n")}\n" \
        "A path with a `#`, a space or a percent needs escaping, and the converter is where that lives."
    }
  end
end
