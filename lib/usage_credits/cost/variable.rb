# frozen_string_literal: true

module UsageCredits
  module Cost
    # Variable credit cost based on units (e.g., 1 credit per MB)
    class Variable < Base
      SUPPORTED_UNITS = %i[kb mb gb units].freeze

      attr_reader :unit

      def initialize(amount, unit)
        super(amount)
        @unit = unit.to_sym
        raise ArgumentError, "Unknown unit: #{unit}" unless SUPPORTED_UNITS.include?(@unit)
      end

      def calculate(params = {})
        size = extract_size(params)
        amount * size
      end

      private

      def extract_size(params)
        case unit
        when :kb, :mb, :gb
          # First check for direct MB value
          if params[:mb]
            convert_megabytes(params[:mb])
          # Then check for bytes that need conversion
          elsif params[:size]
            params[:size].to_f / bytes_per_unit
          else
            0
          end
        when :units
          params.fetch(:units, 0)
        end
      end

      def convert_megabytes(megabytes)
        (megabytes.to_f * 1.megabyte) / bytes_per_unit
      end

      def bytes_per_unit
        case unit
        when :kb then 1.kilobyte
        when :mb then 1.megabyte
        when :gb then 1.gigabyte
        end
      end
    end
  end
end
