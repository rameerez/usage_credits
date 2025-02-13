class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user

  def current_user
    # For demo purposes, find or create a test user
    @current_user ||= User.find_or_create_by(email: 'test@example.com')
  end
end
