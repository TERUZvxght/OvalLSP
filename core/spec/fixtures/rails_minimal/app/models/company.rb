# frozen_string_literal: true

class Company < ActiveRecord::Base
  column :id, :integer, null: false
  column :name, :string, null: false

  has_many :orders
end
