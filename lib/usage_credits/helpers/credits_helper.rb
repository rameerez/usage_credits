# frozen_string_literal: true

module UsageCredits
  # View helpers for displaying credit information
  module CreditsHelper
    # Format credit amount for display
    def format_credits(amount)
      UsageCredits.configuration.credit_formatter.call(amount)
    end

    # Format credit balance with sign
    def format_credit_balance(amount)
      prefix = amount.positive? ? "+" : ""
      "#{prefix}#{format_credits(amount)}"
    end

    # Format price in currency
    def format_credit_price(cents, currency = nil)
      currency ||= UsageCredits.configuration.default_currency
      format("%.2f %s", cents / 100.0, currency.to_s.upcase)
    end

    # Format credits per dollar ratio
    def format_credits_per_dollar(credits, cents)
      return "0" if cents.zero?

      ratio = (credits * 100.0) / cents
      format("%.2f", ratio)
    end

    # Progress bar for credit usage
    def credit_usage_progress(current, total, options = {})
      percentage = total.zero? ? 0 : [(current.to_f / total * 100), 100].min
      css_class = options[:class] || "credit-usage-progress"

      content_tag :div, class: css_class do
        content_tag :div,
                   class: "#{css_class}-bar",
                   style: "width: #{percentage}%",
                   "aria-valuenow": percentage,
                   "aria-valuemin": 0,
                   "aria-valuemax": 100 do
          "#{percentage.round}%"
        end
      end
    end

    # Credit pack purchase button
    def credit_pack_button(pack, options = {})
      button_to options[:path] || credit_pack_purchase_path(pack),
                class: options[:class] || "credit-pack-button",
                method: :post,
                data: {
                  turbo: false,
                  pack_name: pack.name,
                  credits: pack.credits,
                  bonus_credits: pack.bonus_credits,
                  price: pack.price_cents
                } do
        render_credit_pack_button_content(pack)
      end
    end

    # Subscription credit info
    def subscription_credit_info(subscription)
      return unless subscription.provides_credits?

      content_tag :div, class: "subscription-credit-info" do
        safe_join([
          monthly_credits_info(subscription),
          rollover_info(subscription),
          trial_credits_info(subscription)
        ].compact, tag.br)
      end
    end

    private

    def render_credit_pack_button_content(pack)
      safe_join([
        content_tag(:span, "#{format_credits(pack.credits)} Credits", class: "credit-amount"),
        pack.bonus_credits.positive? ? content_tag(:span, "+ #{format_credits(pack.bonus_credits)} Bonus", class: "bonus-amount") : nil,
        content_tag(:span, format_credit_price(pack.price_cents, pack.price_currency), class: "price")
      ].compact, " ")
    end

    def monthly_credits_info(subscription)
      return unless subscription.monthly_credits.positive?

      "#{format_credits(subscription.monthly_credits)} credits per month"
    end

    def rollover_info(subscription)
      return unless subscription.rollover_credits?

      "Unused credits roll over to next month"
    end

    def trial_credits_info(subscription)
      return unless subscription.trial? && subscription.credit_rule&.trial_credits&.positive?

      "#{format_credits(subscription.credit_rule.trial_credits)} trial credits"
    end
  end
end
