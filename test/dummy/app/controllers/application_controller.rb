class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user

  def current_user
    # For demo purposes, create a unique test user per session
    @current_user ||= User.find_or_create_by(email: "test-#{session.id}@example.com")
  end

  def reset_demo!
    if current_user
      # First delete the Pay::Customer which will cascade delete all Pay-related records
      if pay_customer = current_user.payment_processor
        pay_customer.destroy
      end

      # Then delete the user which will cascade delete all usage_credits records
      # (wallet, transactions, fulfillments, allocations) via has_credits association
      current_user.destroy

      # Clear the memoized current_user
      @current_user = nil
    end

    redirect_to credits_path, notice: "The demo has been successfully reset."
  end
end
