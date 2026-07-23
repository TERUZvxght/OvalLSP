# frozen_string_literal: true

class User < ActiveRecord::Base
  column :id, :integer, null: false
  column :email, :string, null: false
  column :company_id, :integer, null: true

  belongs_to :company, optional: true
end
