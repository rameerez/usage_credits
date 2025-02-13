class User < ApplicationRecord
  has_credits

  pay_customer default_payment_processor: :fake_processor, allow_fake: true
end
