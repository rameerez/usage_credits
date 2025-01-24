# lib/usage_credits/jobs/fulfillment_job.rb
module UsageCredits
  class FulfillmentJob < ApplicationJob
    queue_as :default

    def perform
      Rails.logger.info "Starting credit fulfillment processing"
      start_time = Time.current

      count = FulfillmentService.process_pending_fulfillments

      elapsed = Time.current - start_time
      formatted_time = if elapsed >= 60
        "#{(elapsed / 60).floor}m #{(elapsed % 60).round}s"
      else
        "#{elapsed.round(2)}s"
      end

      Rails.logger.info "Completed processing #{count} fulfillments in #{formatted_time}"
    rescue StandardError => e
      Rails.logger.error "Error processing credit fulfillments: #{e.message}"
      raise # Re-raise to trigger job retry
    end
  end
end
