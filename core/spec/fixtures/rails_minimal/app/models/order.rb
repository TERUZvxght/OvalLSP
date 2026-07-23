# frozen_string_literal: true

class Order < ActiveRecord::Base
  column :id, :integer, null: false
  column :company_id, :integer, null: false
  column :total, :decimal, null: false

  belongs_to :company, optional: false
end
