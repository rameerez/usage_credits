# frozen_string_literal: true

module UsageCredits
  # Immutable commercial terms used to fulfill one processor subscription.
  # Terms may come from checkout metadata, an existing fulfillment snapshot,
  # or (for legacy records) the current Ruby configuration.
  class SubscriptionTerms
    TRUE_VALUES = [true, 1, "1", "true"].freeze
    FALSE_VALUES = [false, 0, "0", "false"].freeze

    attr_reader :name,
      :processor_plan_id,
      :credits_per_period,
      :signup_bonus_credits,
      :trial_credits,
      :fulfillment_period_display,
      :rollover_enabled,
      :expire_credits_on_cancel,
      :credit_expiration_period_seconds,
      :configured_plan

    def self.from_plan(plan, processor_plan_id:)
      return if plan.nil?

      new(
        name: plan.name,
        processor_plan_id: processor_plan_id,
        credits_per_period: plan.credits_per_period,
        signup_bonus_credits: plan.signup_bonus_credits,
        trial_credits: plan.trial_credits,
        fulfillment_period: plan.fulfillment_period_display,
        rollover_enabled: plan.rollover_enabled,
        expire_credits_on_cancel: plan.expire_credits_on_cancel,
        credit_expiration_period: plan.credit_expiration_period&.to_i,
        configured_plan: plan
      )
    end

    def self.from_metadata(metadata, processor_plan_id:, configured_plan: nil)
      data = (metadata || {}).with_indifferent_access
      return unless data.key?(:credits_per_period) && data.key?(:fulfillment_period) && data.key?(:rollover_enabled)

      new(
        name: data[:plan_name].presence || data[:subscription_name].presence || configured_plan&.name || processor_plan_id,
        processor_plan_id: processor_plan_id,
        credits_per_period: data[:credits_per_period],
        signup_bonus_credits: data.fetch(:signup_bonus_credits, 0),
        trial_credits: data.fetch(:trial_credits, 0),
        fulfillment_period: data[:fulfillment_period],
        rollover_enabled: parse_boolean(data[:rollover_enabled], "rollover_enabled"),
        expire_credits_on_cancel: boolean_from_metadata(
          data,
          :expire_credits_on_cancel,
          fallback: configured_plan&.expire_credits_on_cancel || false
        ),
        credit_expiration_period: value_from_metadata(
          data,
          :credit_expiration_period,
          fallback: configured_plan&.credit_expiration_period&.to_i
        ),
        configured_plan: configured_plan,
        allow_string_numbers: true
      )
    end

    def self.parse_boolean(value, name)
      return true if TRUE_VALUES.include?(value)
      return false if FALSE_VALUES.include?(value)

      raise ArgumentError, "#{name} must be true or false"
    end
    private_class_method :parse_boolean

    def self.boolean_from_metadata(data, key, fallback:)
      value = value_from_metadata(data, key, fallback: fallback)
      parse_boolean(value, key)
    end
    private_class_method :boolean_from_metadata

    def self.value_from_metadata(data, key, fallback:)
      value = data[key]
      (value.nil? || value == "") ? fallback : value
    end
    private_class_method :value_from_metadata

    def initialize(name:, processor_plan_id:, credits_per_period:, signup_bonus_credits:, trial_credits:,
      fulfillment_period:, rollover_enabled:, expire_credits_on_cancel: false, credit_expiration_period: nil,
      configured_plan: nil, allow_string_numbers: false)
      @name = name.respond_to?(:to_sym) ? name.to_sym : name
      @processor_plan_id = processor_plan_id.to_s
      @credits_per_period = parse_positive(credits_per_period, "credits_per_period", allow_string_numbers)
      @signup_bonus_credits = parse_non_negative(signup_bonus_credits, "signup_bonus_credits", allow_string_numbers)
      @trial_credits = parse_non_negative(trial_credits, "trial_credits", allow_string_numbers)
      @fulfillment_period_display = fulfillment_period.to_s
      @parsed_fulfillment_period = UsageCredits::PeriodParser.parse_persisted_period(@fulfillment_period_display)
      @rollover_enabled = rollover_enabled == true
      @expire_credits_on_cancel = expire_credits_on_cancel == true
      @credit_expiration_period_seconds = parse_expiration_period(credit_expiration_period, allow_string_numbers)
      @configured_plan = configured_plan
      freeze
    end

    attr_reader :parsed_fulfillment_period

    def callback_plan
      configured_plan || self
    end

    private

    def parse_non_negative(value, name, allow_string)
      number = Wallets::WholeNumber.parse(value, name: name, allow_string: allow_string)
      raise ArgumentError, "#{name} cannot be negative" if number.negative?

      number
    end

    def parse_positive(value, name, allow_string)
      number = parse_non_negative(value, name, allow_string)
      raise ArgumentError, "#{name} must be positive" unless number.positive?

      number
    end

    def parse_expiration_period(value, allow_string)
      return 0 if value.nil? || value == ""

      parse_non_negative(value, "credit_expiration_period", allow_string)
    end
  end
end
