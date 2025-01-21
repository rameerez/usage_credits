# frozen_string_literal: true

UsageCredits.configure do |config|

  # Default test operations
  operation :test_operation do
    cost 1.credits
  end

  operation :expensive_operation do
    cost 10.credits
  end

  operation :absurdly_expensive_operation do
    cost 1000.credits
  end

  operation :variable_op do
    cost 10.credits + 2.credits_per(:units)
  end

  operation :edge_op do
    cost 10.credits + 1.credits_per(:mb)
  end

  operation :mb_op do
    cost 1.credits_per(:megabytes)
  end

  operation :kb_op do
    cost 1.credits_per(:kilobytes)
  end

  operation :gb_op do
    cost 1.credits_per(:gigabytes)
  end

  operation :unit_op do
    cost 1.credits_per(:units)
  end

  operation :compound_op do
    cost 10.credits + 1.credits_per(:mb) + 2.credits_per(:units)
  end

  operation :size_op do
    cost 1.credits_per(:mb)
  end

  operation :process_image do
    cost 10.credits + 1.credits_per(:mb)
    validate ->(params) { params[:size].to_i <= 100.megabytes }, "File too large (max: 100 MB)"
  end

  operation :meta_op do
    cost 10.credits
    meta category: :test, description: "Test operation", version: "1.0"
  end

  operation :validated_op do
    cost 10.credits
    validate ->(params) { params[:value] > 0 }, "Value must be positive"
  end

  operation :multi_validated_op do
    cost 10.credits
    validate ->(params) { params[:value] > 0 }, "Value must be positive"
    validate ->(params) { params[:value] < 100 }, "Value must be less than 100"
  end

  operation :dynamic_op do
    cost ->(params) { params[:base_cost].to_i + 2 * params[:multiplier].to_i }.credits
  end

  operation :invalid_op do
    cost ->(params) { 1.5 }.credits
  end

  # Define test subscription plans
  subscription_plan :test_plan do
    gives 1000.credits
    signup_bonus 100.credits
    trial_includes 50
    unused_credits :rollover
  end

  subscription_plan :no_trial_plan do
    gives 1000.credits
  end

  subscription_plan :no_rollover_plan do
    gives 1000.credits
    unused_credits :expire
  end

  subscription_plan :rollover_plan do
    gives 1000.credits
    unused_credits :rollover
  end

  subscription_plan :trial_plan do
    gives 1000.credits
    trial_includes 50
    unused_credits :expire
  end

  subscription_plan :expiring_plan do
    gives 1000.credits
    unused_credits :expire
    expire_after 30.days
  end

  # Define test credit packs
  credit_pack :starter do
    includes 1000.credits
    costs 49.dollars
    currency :usd
  end

  credit_pack :pro do
    includes 5000.credits
    costs 199.dollars
    currency :usd
  end

  credit_pack :euro_pack do
    includes 1000.credits
    costs 49.dollars
    currency :eur
  end

end
