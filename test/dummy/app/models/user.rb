class User < ApplicationRecord
  has_credits

  pay_customer
end
