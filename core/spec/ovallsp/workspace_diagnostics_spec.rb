# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# The decisions a pass makes about *itself* -- how far it goes and when it
# stops -- which the Server-level specs cannot reach, because reproducing
# them there means either a workspace of thousands of files or a race (0.2.0).
RSpec.describe Ovallsp::WorkspaceDiagnostics do
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:published) { [] }
  let(:analyzed) { [] }
  let(:open_uris) { [] }

  def build(root, max_files: described_class::DEFAULT_MAX_FILES, analyze: nil)
    described_class.new(
      analyze: analyze || ->(document) { analyzed << document.uri; [] },
      publish: ->(uri, findings) { published << [uri, findings] },
      open_in_buffer: ->(uri) { open_uris.include?(uri) },
      logger: logger, max_files: max_files
    )
  end

  def write_files(root, count)
    (0...count).map do |i|
      path = File.join(root, "file_#{i}.rb")
      File.write(path, "class File#{i}\nend\n")
      Ovallsp::UriUtil.from_path(path)
    end
  end

  it "publishes for every file it is given" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 3)

      pass = build(root)
      outcome = pass.run(uris, pass.begin_pass)

      expect(published.map(&:first)).to match_array(uris)
      expect(outcome.analyzed).to eq(3)
      expect(outcome.truncated).to be(false)
    end
  end

  it "skips a file that is open in a buffer" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 3)
      open_uris << uris[1]

      pass = build(root)
      pass.run(uris, pass.begin_pass)

      expect(published.map(&:first)).not_to include(uris[1])
    end
  end

  # Without the cap, a pass over a monorepo is a background thread that
  # never ends -- and every file past the first few hundred is one nobody
  # was going to look at this session anyway.
  it "stops at the cap and says that it did" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 6)

      pass = build(root, max_files: 2)
      outcome = pass.run(uris, pass.begin_pass)

      expect(outcome.analyzed).to eq(2)
      expect(outcome.truncated).to be(true)
      expect(published.size).to eq(2)
    end
  end

  # A pass that only checked its token at the start would publish an
  # answer it already knew was stale for every file after the change --
  # which on a large workspace is most of them.
  it "abandons a pass superseded partway through, rather than finishing it" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 5)
      pass = nil
      pass = build(root, analyze: lambda do |document|
        pass.begin_pass if document.uri == uris[1]
        []
      end)

      outcome = pass.run(uris, pass.begin_pass)

      expect(outcome.superseded).to be(true)
      expect(published.size).to be < 5
    end
  end

  it "reports the newest pass as current and every older one as not" do
    Dir.mktmpdir do |root|
      pass = build(root)
      first = pass.begin_pass
      second = pass.begin_pass

      expect(pass.current?(second)).to be(true)
      expect(pass.current?(first)).to be(false)
    end
  end

  # One unreadable file must not end the pass: the other several hundred
  # are still worth reporting on, and the failure is a property of that
  # file rather than of the workspace.
  it "carries on past a file that cannot be analyzed" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 3)
      pass = build(root, analyze: lambda do |document|
        raise "boom" if document.uri == uris[0]

        []
      end)

      outcome = pass.run(uris, pass.begin_pass)

      expect(outcome.analyzed).to eq(2)
      expect(published.map(&:first)).to match_array(uris[1..])
    end
  end

  # A file deleted between the index recording it and this pass reaching
  # it is an ordinary race, not a failure. Letting the read raise and be
  # rescued produces the same empty result -- and an error line per file,
  # which is how a normal race becomes a wall of noise hiding the
  # failures worth reading.
  it "does not publish, or complain, for a URI with no file behind it" do
    Dir.mktmpdir do |root|
      missing = Ovallsp::UriUtil.from_path(File.join(root, "gone.rb"))

      pass = build(root)
      outcome = pass.run([missing], pass.begin_pass)

      expect(published).to be_empty
      expect(outcome.analyzed).to eq(0)
      expect(logger).not_to have_received(:error)
    end
  end

  # An `.erb` file parsed as Ruby is a syntax error on its first tag, and
  # a syntax error reported for every view in the workspace is exactly the
  # noise that makes people turn a check off.
  it "reads an ERB template as ERB, not as Ruby" do
    Dir.mktmpdir do |root|
      path = File.join(root, "show.html.erb")
      File.write(path, "<p><%= @user %></p>\n")
      uri = Ovallsp::UriUtil.from_path(path)
      language_ids = []
      pass = build(root, analyze: ->(document) { language_ids << document.language_id; [] })

      pass.run([uri], pass.begin_pass)

      expect(language_ids).to eq(["erb"])
    end
  end
end
