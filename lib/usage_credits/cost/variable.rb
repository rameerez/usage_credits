# frozen_string_literal: true

module UsageCredits
  module Cost
    # Variable credit cost based on units (e.g., 1 credit per MB)
    class Variable < Base
      attr_reader :unit

      def initialize(amount, unit)
        super(amount)
        @unit = unit.to_sym
      end

      def calculate(params = {})
        size = extract_size(params)
        raw_cost = amount * size
        CreditCalculator.apply_rounding(raw_cost)
      end

      private

      def extract_size(params)
        case unit
        when :mb
          # First check for direct MB value
          if params[:mb]
            CreditCalculator.apply_rounding(params[:mb].to_f)
          # Then check for bytes that need conversion
          elsif params[:size]
            CreditCalculator.apply_rounding(params[:size].to_f / 1.megabyte)
          else
            0
          end
        when :units
          CreditCalculator.apply_rounding(params.fetch(:units, 0).to_f)
        else
          raise ArgumentError, "Unknown unit: #{unit}"
        end
      end
    end
  end
end
