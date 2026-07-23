# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Rslsp::ColdIndexer do
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }
  let(:parser_service) { Rslsp::ParserService.new }
  let(:workspace_index) { Rslsp::WorkspaceIndex.new }
  let(:document_store) { Rslsp::DocumentStore.new }

  def write(dir, relative_path, content)
    full = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def run_indexer(root)
    described_class.new(
      root: root, parser_service: parser_service, workspace_index: workspace_index,
      document_store: document_store, logger: logger
    ).run
  end

  def class_declared?(name)
    !workspace_index.find_by_simple_name(name).empty?
  end

  it "indexes .rb files nested under the workspace root" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      write(dir, "app/controllers/posts_controller.rb", "class PostsController\nend\n")

      run_indexer(dir)

      expect(class_declared?("User")).to be(true)
      expect(class_declared?("PostsController")).to be(true)
    end
  end

  it "indexes .rake files" do
    Dir.mktmpdir do |dir|
      write(dir, "lib/tasks/thing.rake", "class RakeHelper\nend\n")

      run_indexer(dir)

      expect(class_declared?("RakeHelper")).to be(true)
    end
  end

  it "extracts Ruby regions from .erb files rather than feeding raw HTML+ERB to Prism" do
    Dir.mktmpdir do |dir|
      write(dir, "app/views/users/show.html.erb", "<h1><%= @user.name %></h1>\n<% ClassInErb = 1 %>\n")

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("ClassInErb")).to be(true)
    end
  end

  %w[.git node_modules vendor/bundle tmp log coverage public/assets storage].each do |excluded|
    it "does not descend into #{excluded}" do
      Dir.mktmpdir do |dir|
        write(dir, "#{excluded}/should_not_be_indexed.rb", "class ShouldNotBeIndexed\nend\n")
        write(dir, "app/models/user.rb", "class User\nend\n")

        run_indexer(dir)

        expect(class_declared?("ShouldNotBeIndexed")).to be(false)
        expect(class_declared?("User")).to be(true)
      end
    end
  end

  it "does not overwrite an already-open document's contribution with stale on-disk content" do
    Dir.mktmpdir do |dir|
      path = write(dir, "app/models/user.rb", "class User\nend\n")
      uri = Rslsp::UriUtil.from_path(path)

      # An editor has unsaved edits: the buffer says "Renamed", the disk
      # still says "User".
      document_store.open(uri: uri, text: "class Renamed\nend\n", version: 1, language_id: "ruby")
      workspace_index.replace_file(parser_service.summarize(document_store.fetch(uri: uri)))

      run_indexer(dir)

      expect(class_declared?("Renamed")).to be(true)
      expect(class_declared?("User")).to be(false)
    end
  end

  it "avoids an infinite loop on a symlink cycle" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      FileUtils.mkdir_p(File.join(dir, "app", "cyclic"))
      File.symlink(dir, File.join(dir, "app", "cyclic", "back_to_root"))

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("User")).to be(true)
    end
  end

  it "does not follow a symlink that points outside the workspace root" do
    Dir.mktmpdir do |workspace|
      Dir.mktmpdir do |outside|
        write(outside, "secret.rb", "class ShouldNeverBeIndexed\nend\n")
        write(workspace, "app/models/user.rb", "class User\nend\n")
        File.symlink(outside, File.join(workspace, "app", "escape_hatch"))

        run_indexer(workspace)

        expect(class_declared?("ShouldNeverBeIndexed")).to be(false)
        expect(class_declared?("User")).to be(true)
      end
    end
  end

  it "does not index the same file twice when reached via two symlinked paths" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      File.symlink(File.join(dir, "app"), File.join(dir, "app_alias"))

      run_indexer(dir)

      symbol_id = Rslsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::User", discriminator: nil)
      expect(workspace_index.declarations(symbol_id).size).to eq(1)
    end
  end

  it "reads non-ASCII file content as UTF-8 rather than the process's default external encoding" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", <<~RUBY)
        # 日本語コメントです — em dash and emoji: 😀
        class User
        end
      RUBY

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("User")).to be(true)
      expect(logger).not_to have_received(:error)
    end
  end

  it "logs and continues rather than crashing when a file can't be read" do
    Dir.mktmpdir do |dir|
      write(dir, "app/models/user.rb", "class User\nend\n")
      write(dir, "app/models/broken.rb", "class Broken\n") # unterminated, but Prism tolerates this gracefully

      expect { run_indexer(dir) }.not_to raise_error
      expect(class_declared?("User")).to be(true)
    end
  end
end
