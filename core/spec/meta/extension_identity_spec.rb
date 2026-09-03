# frozen_string_literal: true

require "json"

# **The extension's id, everywhere a reader is told to type it.**
#
# `docs/DOCUMENTATION_MAP.md`'s "Install steps, prerequisites, or the
# extension id" row names six documents and has nothing in its "Checked
# by" column. `vscode/package.json` is the only place the id is *true* —
# the Marketplace derives it from `publisher` and `name` — and every
# other mention is a copy. A copy of a fact is a fact that will be wrong
# in one place, which is the sentence that whole map opens with.
#
# Nothing had drifted when this was written; the id has been
# `teruz.ovallsp` since the first publish. That is what makes this cheap
# to add and not what makes it worth adding: the id is the one string a
# reader cannot recover if it is wrong, because `code --install-extension`
# on a wrong id installs nothing and says so in a way that looks like the
# extension does not exist.
RSpec.describe "the extension id, in every document that prints it" do
  def repo_root = File.expand_path("../../..", __dir__)

  def manifest = JSON.parse(File.read(File.join(repo_root, "vscode", "package.json"), encoding: "UTF-8"))

  def identity = "#{manifest.fetch('publisher')}.#{manifest.fetch('name')}"

  # **This publisher's ids only.** A first version matched any
  # `<publisher>.<name>` in an install command or an `itemName` query,
  # and reported both READMEs for `Shopify.ruby-lsp` -- which they name
  # correctly, in a paragraph about running the two side by side. What
  # can be wrong here is *our* id, so that is what is collected.
  def mentions(body)
    publisher = manifest.fetch("publisher")
    (body.scan(/itemName=(#{Regexp.escape(publisher)}\.[A-Za-z0-9_-]+)/).flatten +
      body.scan(/--install-extension\s+(#{Regexp.escape(publisher)}\.[A-Za-z0-9_-]+)/).flatten)
  end

  # The documents a reader installs from. Task records are history and
  # may name an id that was true when they were written.
  def documents
    %w[README.md README.ja.md docs/PUBLISHING.md
       vscode/README.md vscode/README.ja.md
       site/index.html site/ja/index.html site/getting-started.html site/ja/getting-started.html]
      .select { |path| File.file?(File.join(repo_root, path)) }
  end

  it "agrees with vscode/package.json wherever it is printed" do
    wrong = documents.flat_map do |path|
      mentions(File.read(File.join(repo_root, path), encoding: "UTF-8"))
        .reject { |id| id == identity }
        .map { |id| "#{path}: #{id}" }
    end

    expect(wrong).to be_empty,
                     "these name an extension id that is not #{identity}:\n  #{wrong.join("\n  ")}"
  end

  # The control. Without it this passes on a tree where no document
  # prints the id at all, which is what a rewrite could leave behind and
  # is indistinguishable from every mention agreeing.
  it "is reading documents that actually print it" do
    found = documents.to_h { |path| [path, mentions(File.read(File.join(repo_root, path), encoding: "UTF-8"))] }

    expect(identity).to match(/\A[a-z0-9-]+\.[a-z0-9-]+\z/)
    expect(found.values.flatten).not_to be_empty
    expect(found.count { |_, ids| ids.any? }).to be >= 3,
                                                "only #{found.count { |_, ids| ids.any? }} document(s) print the id"
  end

  # And it must be able to say no, or the assertion above would hold on a
  # scanner that matches nothing.
  it "would report an id that is not the manifest's" do
    planted = "run `code --install-extension #{manifest.fetch('publisher')}.wrong-name` to install"

    expect(mentions(planted)).to eq(["#{manifest.fetch('publisher')}.wrong-name"])
    expect(mentions(planted)).not_to include(identity)
    # And a different publisher's extension is not this check's business.
    expect(mentions("`code --install-extension Shopify.ruby-lsp`")).to be_empty
  end
end
