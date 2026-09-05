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
      analyze: analyze || ->(document) { analyzed << document.uri; [[], 1] },
      # The document is what the pass analysed, handed to the funnel
      # rather than discarded (037's C3) -- recorded here so an example
      # can assert the answer and the text it came from travel together.
      publish: ->(uri, findings, document: nil, generation: nil) { published << [uri, findings, document, generation] },
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

  # 037's C3. The pass reads a file, builds a document from it, analyses
  # that document -- and then published a `uri` and nothing else, so the
  # funnel had no way to tell an answer about this text from an answer
  # about whatever the file said a second later. The document it actually
  # analysed now travels with the answer.
  #
  # The fixture writes text the document must be distinguishable *by*: an
  # example asserting only that some document arrived would pass if the
  # pass invented an empty one.
  it "hands the funnel the document it analysed, not just the uri" do
    Dir.mktmpdir do |root|
      path = File.join(root, "only.rb")
      File.write(path, "class OnlyThisText
end
")
      uri = Ovallsp::UriUtil.from_path(path)

      pass = build(root)
      pass.run([uri], pass.begin_pass)

      document = published.first[2]
      expect(document.text).to eq("class OnlyThisText\nend\n")
      expect(document.uri).to eq(uri)
      # Nil, which is what makes the funnel read it as a disk answer that
      # may not speak over an open buffer.
      expect(document.version).to be_nil
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

  # An analysis takes long enough for a `didOpen` to arrive inside it.
  # Checking only beforehand lets the pass overwrite the buffer path's
  # correct diagnostics with disk-derived ones, for text the user is not
  # looking at, with nothing to correct it until the next edit.
  it "does not publish for a file that was opened while it was being analyzed" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 1)
      pass = build(root, analyze: lambda do |document|
        open_uris << document.uri
        [[], 1]
      end)

      pass.run(uris, pass.begin_pass)

      expect(published).to be_empty
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
        [[], 1]
      end)

      outcome = pass.run(uris, pass.begin_pass)

      expect(outcome.superseded).to be(true)
      expect(published.size).to be < 5
    end
  end

  # `begin_pass` is also how a shutdown asks a running pass to stop: it
  # invalidates the token the pass is carrying, and the pass returns at
  # the next file boundary rather than being killed by the join that
  # follows -- possibly between a frame's header and its body.
  it "lets a caller with no new work to start stop the pass that is running" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 5)
      pass = build(root)
      generation = pass.begin_pass
      pass.begin_pass

      outcome = pass.run(uris, generation)

      expect(outcome.superseded).to be(true)
      expect(published).to be_empty
    end
  end

  # Shutdown's problem is not "stop this pass" but "stop all of them": a
  # pass is started from inside another background thread, so invalidating
  # the current one can be undone a moment later by that thread starting a
  # fresh, valid one -- which then has to be killed by the join.
  it "refuses to start a pass once it has been closed" do
    Dir.mktmpdir do |root|
      uris = write_files(root, 3)
      pass = build(root)
      pass.close

      outcome = pass.run(uris, pass.begin_pass)

      expect(outcome.superseded).to be(true)
      expect(published).to be_empty
    end
  end

  it "refuses a single-file publish once it has been closed" do
    Dir.mktmpdir do |root|
      uri = write_files(root, 1).first
      pass = build(root)
      pass.close

      expect(pass.publish_for(uri)).to be(false)
      expect(published).to be_empty
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

        [[], 1]
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
      pass = build(root, analyze: ->(document) { language_ids << document.language_id; [[], 1] })

      pass.run([uri], pass.begin_pass)

      expect(language_ids).to eq(["erb"])
    end
  end
end
