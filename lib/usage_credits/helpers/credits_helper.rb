# frozen_string_literal: true

module UsageCredits
  # View helpers for displaying credit information
  module CreditsHelper
    # Format credit amount for display
    def format_credits(amount)
      UsageCredits.configuration.credit_formatter.call(amount)
    end

    # Format price in currency
    def format_credit_price(cents, currency = nil)
      currency ||= UsageCredits.configuration.default_currency
      format("%.2f %s", cents / 100.0, currency.to_s.upcase)
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


    private

    def render_credit_pack_button_content(pack)
      safe_join([
        content_tag(:span, "#{format_credits(pack.credits)} Credits", class: "credit-amount"),
        pack.bonus_credits.positive? ? content_tag(:span, "+ #{format_credits(pack.bonus_credits)} Bonus", class: "bonus-amount") : nil,
        content_tag(:span, format_credit_price(pack.price_cents, pack.price_currency), class: "price")
      ].compact, " ")
    end

  end
end
