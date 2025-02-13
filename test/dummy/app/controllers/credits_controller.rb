class CreditsController < ApplicationController
  before_action :set_pack, only: :checkout
  before_action :set_operation, only: :perform_operation

  def index
  end

  def perform_operation
    estimated_credits = current_user.estimate_credits_to(@operation_name)
    performed = false

    begin
      # Spend credits
      current_user.spend_credits_on(@operation_name) do
        if @operation_name == "fail"
          raise StandardError, "Operation failed as requested (no credits deducted)"
        end
        performed = true
      end

      flash[:notice] = "Operation #{@operation_name} performed correctly (#{estimated_credits} credits deducted)"
    rescue UsageCredits::InsufficientCredits => e
      flash[:alert] = "Not enough credits: #{e.message}"
    rescue UsageCredits::InvalidOperation => e
      flash[:alert] = "Invalid operation: #{e.message}"
    rescue StandardError => e
      flash[:alert] = "Operation failed: #{e.message}"
    end

    redirect_back fallback_location: credits_path
  end

  def checkout
    # Mock `pay` payment processor, so instead of creating a checkout session, just create a charge directly
    current_user.payment_processor.charge(@pack.price_cents, metadata: @pack.base_metadata )

    # Redirect to success page
    redirect_to credits_path, notice: "Successfully purchased #{@pack.credits} credits!"
  rescue Pay::Error => e
    redirect_to credits_path, alert: e.message
  end

  def checkout_subscription
    @credits_subscription_plan = UsageCredits.find_subscription_plan(:test_plan)

    # Mock fake subscription
    current_user.payment_processor.subscribe(plan: @credits_subscription_plan.plan_id_for(:fake_processor), metadata: @credits_subscription_plan.base_metadata)

    redirect_to credits_path, notice: "Successfully subscribed!"
    rescue Pay::Error => e
      redirect_to credits_path, alert: e.message
  end

  def award_bonus
    amount = credits_params[:bonus_amount]
    reason = credits_params[:bonus_reason]

    current_user.give_credits(amount, reason: reason)

    redirect_to credits_path, notice: "Successfully awarded a bonus of #{amount} credits with reason: #{reason}"
  end

  private

  def set_pack
    @pack = UsageCredits.find_pack(credits_params[:pack])
  end

  def set_operation
    @operation_name = credits_params[:operation]
  end

  def credits_params
    params.permit(:pack, :operation, :bonus_amount, :bonus_reason)
  end
end
