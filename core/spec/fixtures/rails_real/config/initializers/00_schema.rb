# Hand-written in-memory schema instead of migrations -- this fixture
# exists purely to exercise the Runtime Agent against a genuinely
# installed Rails/ActiveRecord (docs/design/tasks/008.5-runtime-and-index-corrections.md),
# not to model a real app's data model.
ActiveRecord::Schema.define do
  self.verbose = false

  create_table :companies, force: true do |t|
    t.string :name, null: false
  end

  create_table :users, force: true do |t|
    t.string :name, null: false
    t.string :email, null: true
    t.integer :company_id
  end

  create_table :posts, force: true do |t|
    t.string :title, null: false
    t.text :body, null: true
    t.integer :user_id
  end
end
