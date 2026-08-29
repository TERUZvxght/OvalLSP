# frozen_string_literal: true

# What a completion list says about a receiver that could be two things.
#
# `Member#conditional` is the one field separating "every branch answers
# this" from "picking this raises NoMethodError on the other branch", and
# `Server#member_completion_items` renders it straight into `sortText`
# (0.2.15) -- so it is not an internal detail, it is the order the user
# sees.
#
# It used to be decided by a *fifth* lookup, `#member_available_on?`,
# asked one name at a time after the four sources had already answered.
# That lookup agreed with none of the four, and disagreed in both
# directions at once: it asked RBS about the branch's own name with no
# ancestor chain (so every name Ruby gives every object came back
# absent), it asked `MethodResolver#resolve`, which does not filter
# visibility (so a method one branch declares `private` came back
# present), and Active Record's own API was not something it asked about
# at all. `024.249`, `024.250`, `024.252`, `024.253`, `024.254`.
#
# Enumerating one branch at a time answers the question by construction:
# a name is unconditional exactly when every branch's own enumeration
# produced it, and the enumeration that offers the member is the one that
# counts it. Nothing is left to agree with anything.
RSpec.describe "a Union receiver's members, one branch at a time" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  subject(:service) do
    Ovallsp::Semantic::QueryService.new(
      local_inferencer: stack.local_inferencer, method_resolver: stack.method_resolver,
      model_registry: model_registry, signatures: signatures, workspace_index: workspace_index
    )
  end

  def index_source(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    document
  end

  def nominal(name) = Ovallsp::Types::Nominal.new(name: name)
  def union(*types) = Ovallsp::Types.normalize_union(types)
  def class_object(name) = Ovallsp::Types.class_object(nominal(name))

  def member(receiver, name, context: {})
    service.members_of(receiver, prefix: "", context: context).find { |candidate| candidate.name == name }
  end

  # `024.253`. Every name `Object` and `Kernel` give every Ruby object is
  # on both branches of a Union of two workspace classes, and every one of
  # them was labelled one-branch-only -- 121 of 122 items sorting into the
  # bottom band, which inverts the list 0.2.15's `sortText` work exists to
  # order.
  #
  #   $ ruby -e '
  #   class P; def only_p; end; def both; end; end
  #   class Q; def both; end; end
  #   p [P.new.respond_to?(:to_s), Q.new.respond_to?(:to_s)]
  #   p [P.new.respond_to?(:only_p), Q.new.respond_to?(:only_p)]
  #   '
  #   # => [true, true]
  #   # => [true, false]
  #   # ruby 3.4.10
  describe "a name both branches inherit" do
    before { index_source("class P\n  def only_p; end\n  def both; end\nend\nclass Q\n  def both; end\nend\n") }

    let(:receiver) { union(nominal("P"), nominal("Q")) }

    it "calls a member every branch inherits from Object unconditional" do
      expect(member(receiver, "to_s").conditional).to be(false)
      expect(member(receiver, "frozen?").conditional).to be(false)
    end

    # The two controls that tell "correct" from "declines wholesale": a
    # fix that simply stopped saying `conditional` would pass the example
    # above and fail these.
    it "still calls a source method only one branch declares conditional" do
      expect(member(receiver, "only_p").conditional).to be(true)
    end

    it "still calls a source method both branches declare unconditional" do
      expect(member(receiver, "both").conditional).to be(false)
    end

    # The distinguishing count, rather than four spot checks: the failure
    # this closes is that *almost everything* was in the wrong band, and
    # an example naming four members cannot see the difference between
    # four repaired and the list repaired.
    it "puts all but the one-branch member in the every-branch band" do
      members = service.members_of(receiver, prefix: "")

      expect(members.count { |candidate| candidate.conditional }).to eq(1)
      expect(members.size).to be > 100
    end
  end

  # **What enumerating per branch costs**, pinned so it is visible rather
  # than discovered. `MethodResolver#complete` caps its answer at 50
  # names, and the cap is now applied to each branch instead of to the
  # merged list -- so a name past a large branch's own 50 has not been
  # produced by that branch, and the fold calls it conditional even
  # though both branches declare it.
  #
  # It errs the cheap way round: truncation only ever removes a name from
  # a branch, so it can only move a label *toward* conditional, never
  # into the every-branch band on a receiver that would raise. And it is
  # one name against the 119 the same fixture repairs -- driven at BASE
  # and here, `Big | Small` with 61 methods on `Big` gives 1 of 170
  # unconditional before and 120 of 171 after, with `zshared` the single
  # name that moves the wrong way.
  describe "the source-name cap, applied per branch" do
    def index_big(count)
      body = (1..count).map { |i| "  def a#{format('%02d', i)}; end\n" }.join
      index_source("class Big\n#{body}  def zshared; end\nend\nclass Small\n  def zshared; end\nend\n")
    end

    let(:receiver) { union(nominal("Big"), nominal("Small")) }

    it "keeps a name both branches declare unconditional while the branch fits under the cap" do
      index_big(49)

      expect(member(receiver, "zshared").conditional).to be(false)
    end

    # The distinguishing value: same fixture, twelve more methods on one
    # branch, and the shared name is still *offered* -- which is what a
    # user acts on -- but sorts into the one-branch-only band.
    it "still offers a name the cap cut from the larger branch, marked conditional" do
      index_big(60)

      expect(member(receiver, "zshared")).not_to be_nil
      expect(member(receiver, "zshared").conditional).to be(true)
      expect(service.members_of(receiver, prefix: "").count { |m| !m.conditional }).to be > 100
    end
  end

  # `024.252`, and the direction section 0 ranks worst: completion sorted
  # `shared` into the every-branch band while calling it raises. The old
  # availability lookup asked `MethodResolver#resolve`, which answers
  # regardless of visibility, while the enumeration that produced the
  # member filters it.
  #
  #   $ ruby -e '
  #   class Pub; def shared; end; end
  #   class Priv; private; def shared; end; end
  #   p [Pub.new.respond_to?(:shared), Priv.new.respond_to?(:shared)]
  #   '
  #   # => [true, false]
  #   # ruby 3.4.10
  describe "a name the other branch declares private" do
    it "keeps it conditional" do
      index_source("class Pub\n  def shared; end\nend\nclass Priv\n  private\n  def shared; end\nend\n")

      expect(member(union(nominal("Pub"), nominal("Priv")), "shared").conditional).to be(true)
    end

    # The control in the same fixture, one word apart: both public, and
    # the same name has to come back unconditional.
    it "calls the same name unconditional when both branches declare it public" do
      index_source("class Pub\n  def shared; end\nend\nclass Priv\n  def shared; end\nend\n")

      expect(member(union(nominal("Pub"), nominal("Priv")), "shared").conditional).to be(false)
    end
  end

  # `024.254`. `save`, `destroy` and `find` are the one thing two Active
  # Record models certainly both answer to, and they sorted *below*
  # columns only one of the two has -- the availability lookup consulted
  # source resolution, the model's columns and associations, and RBS, and
  # never `ModelRegistry#active_record_api`, so it could not see the
  # source that had produced the member.
  describe "the Active Record API on a Union of models" do
    def register_model(name, table, column)
      model_registry.register_from_agent_response(
        name, { tableName: table, partial: false,
                columns: [{ name: column, type: "string", nullable: false }], associations: [] }
      )
    end

    before do
      model_registry.install_active_record_api(
        { instance: %w[save destroy update hash], singleton: %w[find where all],
          instanceWithArguments: %w[update], singletonWithArguments: %w[find where] }
      )
    end

    it "calls the Active Record API unconditional when every branch is a model" do
      register_model("User", "users", "email")
      register_model("Post", "posts", "title")

      receiver = union(nominal("User"), nominal("Post"))

      expect(member(receiver, "save").origin).to eq(:model_api)
      expect(member(receiver, "save").conditional).to be(false)
      # The controls: a column only one model has stays one-branch-only.
      expect(member(receiver, "email").conditional).to be(true)
      expect(member(receiver, "title").conditional).to be(true)
    end

    it "still calls it conditional when one branch is not a model at all" do
      register_model("User", "users", "email")

      expect(member(union(nominal("User"), nominal("String")), "save").conditional).to be(true)
    end

    # The one pair of origins where the order the sources *run* in and the
    # order the finished list *sorts* by disagree: within a branch the
    # Active Record API is asked before RBS and so owns a name both
    # produce, while `ORIGIN_AUTHORITY` ranks a signature above it. The
    # fold across branches has to use the first of those, or a Union
    # answers with an origin the same receiver alone does not.
    it "keeps the origin a single branch would give a name two sources produce" do
      register_model("User", "users", "email")

      union_member = member(union(nominal("User"), nominal("String")), "hash")

      expect(union_member.origin).to eq(:model_api)
      expect(member(nominal("User"), "hash").origin).to eq(:model_api)
    end
  end

  # `024.255`. `k = cond ? Foo : Bar` types as a Union of *class objects*,
  # and completion answered nothing at all for it while either branch on
  # its own answered 198 names: `Types.class_object_lookup` unwraps a
  # receiver that IS a `ClassOf`, a Union of them is not one, so the
  # sources were asked about a class literally named `ClassOf`.
  #
  #   $ ruby -e '
  #   class Foo; def self.foo_only; end; def self.shared_cm; end; end
  #   class Bar; def self.shared_cm; end; end
  #   p [Foo.respond_to?(:shared_cm), Bar.respond_to?(:shared_cm)]
  #   p [Foo.respond_to?(:foo_only), Bar.respond_to?(:foo_only)]
  #   p [Foo.respond_to?(:name), Bar.respond_to?(:name)]
  #   '
  #   # => [true, true]
  #   # => [true, false]
  #   # => [true, true]
  #   # ruby 3.4.10
  describe "a Union of class objects" do
    before do
      index_source(
        "class Foo\n  def self.foo_only; end\n  def self.shared_cm; end\nend\n" \
        "class Bar\n  def self.shared_cm; end\nend\n"
      )
    end

    let(:receiver) { union(class_object("Foo"), class_object("Bar")) }

    it "offers the class methods both branches declare" do
      expect(member(receiver, "shared_cm")).not_to be_nil
      expect(member(receiver, "shared_cm").conditional).to be(false)
    end

    it "offers the class method only one branch declares, marked conditional" do
      expect(member(receiver, "foo_only").conditional).to be(true)
    end

    # A class object is an instance of `Class`, so `new` and `name` are on
    # both branches -- the half of the answer that comes from RBS rather
    # than from the workspace.
    it "offers Class's own instance methods on both branches" do
      expect(member(receiver, "new").conditional).to be(false)
      expect(member(receiver, "name").conditional).to be(false)
    end

    # Soundness in the same fixture: the Union must not start offering
    # anything the single-branch control does not, which is what would
    # happen if a branch were read as an *instance* receiver.
    it "offers no name the single class-object control does not" do
      union_names = service.members_of(receiver, prefix: "").map(&:name)
      control_names = service.members_of(class_object("Foo"), prefix: "").map(&:name)

      expect(control_names).to include("shared_cm", "foo_only", "new")
      expect(union_names - control_names).to eq([])
    end

    # `024.256`. Completion offering a name go to definition cannot reach
    # is the asymmetry this closes: `#definitions_of` handed the whole
    # Union to `MethodResolver#resolve`, whose `nominal_members` drops
    # every `ClassOf` branch, so the answer was zero for a name the user
    # can see in the list.
    it "answers go to definition for a name the completion list offers" do
      locations = service.definitions_of(receiver, "shared_cm")

      expect(locations.size).to eq(2)
      expect(locations.map { |location| location[:uri] }).to eq(["file:///a.rb", "file:///a.rb"])
    end

    it "answers go to definition for the name only one branch declares" do
      expect(service.definitions_of(receiver, "foo_only").size).to eq(1)
    end

    # The band below the source one, which is where the same flattening
    # showed: RBS was asked about a class named `ClassOf` rather than
    # about each branch's singleton chain. `Module#instance_methods` is
    # declared nowhere in this workspace, so only that band can answer.
    it "answers go to definition for a name only RBS declares on the class object" do
      expect(service.definitions_of(receiver, "instance_methods")).not_to be_empty
      expect(service.definitions_of(class_object("Foo"), "instance_methods")).not_to be_empty
    end

    # The control: a name neither branch has still answers nothing, so
    # this is not a handler that answers everything.
    it "still answers nothing for a name neither branch declares" do
      expect(service.definitions_of(receiver, "definitely_not_a_class_method")).to be_empty
    end
  end

  # The decision inside the `#definitions_of` change that reverting the
  # whole hunk cannot isolate, which is the hunk sweep's own documented
  # blind spot. Asking each branch separately means two branches that
  # inherit one method from a common ancestor each answer with the
  # *same* declaration; the whole-receiver `#resolve` this replaced
  # collapsed them by grouping on `symbol_id`, and go to definition
  # offering the identical jump twice is offering a choice the call does
  # not have -- which is `#chain_definition_locations`'s stated reason
  # for stopping at the first owner that answers.
  describe "two branches that inherit one method" do
    it "answers with that declaration once, not once per branch" do
      index_source("class Base\n  def shared_up; end\nend\nclass Left < Base\nend\nclass Right < Base\nend\n")

      locations = service.definitions_of(union(nominal("Left"), nominal("Right")), "shared_up")

      expect(locations.size).to eq(1)
      expect(locations.first[:uri]).to eq("file:///a.rb")
    end
  end

  # `024.250`. A `nil` branch could not be enumerated at all -- every one
  # of the four sources keys on a class name and `Types::NilType` is not
  # one -- so *every* member of a nilable Union came back conditional,
  # including the names `nil` itself answers. `Widget | nil` is the
  # commonest Union this engine builds.
  #
  #   $ ruby -e '
  #   class Widget; def spin; end; end
  #   p [Widget.new.respond_to?(:to_s), nil.respond_to?(:to_s)]
  #   p [Widget.new.respond_to?(:frozen?), nil.respond_to?(:frozen?)]
  #   p [Widget.new.respond_to?(:spin), nil.respond_to?(:spin)]
  #   p nil.class
  #   '
  #   # => [true, true]
  #   # => [true, true]
  #   # => [true, false]
  #   # => NilClass
  #   # ruby 3.4.10
  describe "a nilable receiver" do
    before { index_source("class Widget\n  def spin; end\nend\n") }

    let(:receiver) { union(nominal("Widget"), Ovallsp::Types::NIL) }

    it "calls a name nil answers to unconditional" do
      expect(member(receiver, "to_s").conditional).to be(false)
      expect(member(receiver, "frozen?").conditional).to be(false)
    end

    # The control, and the half of `024.250`'s own text that is not a
    # defect: the class's own method really is conditional on a nilable
    # receiver, because the nil branch really does raise. A change that
    # made everything unconditional would pass the example above and fail
    # this one.
    it "still calls the class's own method conditional" do
      expect(member(receiver, "spin").conditional).to be(true)
    end

    # And the other direction, which is where the nil branch differs from
    # every other one: it decides availability without being offered
    # from. `NilClass#to_a` is real and `Widget` has none, and nobody
    # types `widget.` meaning it. The distinguishing value is a name only
    # `nil` has, because a rule that merely counted the nil branch and a
    # rule that also offered from it agree about everything else.
    it "does not offer what only the nil branch has" do
      expect(service.members_of(receiver, prefix: "").map(&:name)).not_to include("to_a")
      # The same name, on the same NilClass, when nil is the whole
      # receiver: there is nothing else the call could mean.
      expect(service.members_of(Ovallsp::Types::NIL, prefix: "").map(&:name)).to include("to_a")
    end
  end
end
