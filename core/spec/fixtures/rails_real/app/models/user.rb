class User < ApplicationRecord
  belongs_to :company, optional: true
  has_many :posts
end
