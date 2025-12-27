# frozen_string_literal: true

module UsageCredits
  # A Wallet manages credit balance and transactions for a user/owner.
  #
  # It's responsible for:
  #   1. Tracking credit balance
  #   2. Performing credit operations (add/deduct)
  #   3. Managing credit expiration
  #   4. Handling low balance alerts

  class Wallet < ApplicationRecord
    self.table_name = "usage_credits_wallets"

    # =========================================
    # Associations & Validations
    # =========================================

    belongs_to :owner, polymorphic: true
    has_many :transactions, class_name: "UsageCredits::Transaction", dependent: :destroy
    has_many :fulfillments, class_name: "UsageCredits::Fulfillment", dependent: :destroy
    has_many :outbound_allocations, through: :transactions, source: :outgoing_allocations
    has_many :inbound_allocations, through: :transactions, source: :incoming_allocations
    has_many :allocations, ->(wallet) { unscope(:where).where("usage_credits_allocations.transaction_id IN (?) OR usage_credits_allocations.source_transaction_id IN (?)", wallet.transaction_ids, wallet.transaction_ids) }, class_name: "UsageCredits::Allocation", dependent: :destroy

    validates :balance, numericality: { greater_than_or_equal_to: 0 }, unless: :allow_negative_balance?

    # =========================================
    # Credit Balance & History
    # =========================================

    # Get current credit balance
    #
    # The first naive approach was to compute this as a sum of all non-expired transactions like:
    #   transactions.not_expired.sum(:amount)
    # but that fails when we mix expiring and non-expiring credits: https://x.com/rameerez/status/1884246492837302759
    #
    # So we needed to introduce the Allocation model
    #
    # Now to calculate current balance, instead of summing:
    # we sum only unexpired positive transactions’ remaining_amount
    def credits
      # Sum the leftover in all *positive* transactions that haven't expired
      transactions
        .where("amount > 0")
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
        .sum("amount - (SELECT COALESCE(SUM(amount), 0) FROM usage_credits_allocations WHERE source_transaction_id = usage_credits_transactions.id)")
        .yield_self { |sum| [sum, 0].max }.to_i
    end

    # Get transaction history (oldest first)
    def credit_history
      transactions.order(created_at: :asc)
    end

    # =========================================
    # Credit Operations
    # =========================================

    # Check if wallet has enough credits for an operation
    def has_enough_credits_to?(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)

      # Then check if we actually have enough credits
      credits >= operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error checking credits: #{e.message}"
    end

    # Calculate how many credits an operation would cost
    def estimate_credits_to(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)

      # Then calculate the cost
      operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error estimating cost: #{e.message}"
    end

    # Spend credits on an operation
    # @param operation_name [Symbol] The operation to perform
    # @param params [Hash] Parameters for the operation
    # @yield Optional block that must succeed before credits are deducted
    def spend_credits_on(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)

      cost = operation.calculate_cost(params)

      # Check if user has enough credits
      raise InsufficientCredits, "Insufficient credits (#{credits} < #{cost})" unless has_enough_credits_to?(operation_name, **params)

      # Create audit trail
      audit_data = operation.to_audit_hash(params)
      deduct_params = {
        metadata: audit_data.merge(operation.metadata).merge(
          "executed_at" => Time.current,
          "gem_version" => UsageCredits::VERSION
        ),
        category: :operation_charge
      }

      if block_given?
        # If block given, only deduct credits if it succeeds
        ActiveRecord::Base.transaction do
          lock!  # Row-level lock for concurrency safety

          yield  # Perform the operation first

          deduct_credits(cost, **deduct_params)  # Deduct credits only if the block was successful
        end
      else
        deduct_credits(cost, **deduct_params)
      end
    rescue StandardError => e
      raise e
    end

    # Give credits to the wallet with optional reason and expiration date
    # @param amount [Integer] Number of credits to give
    # @param reason [String, nil] Optional reason for giving credits (for auditing / trail purposes)
    # @param expires_at [DateTime, nil] Optional expiration date for the credits
    def give_credits(amount, reason: nil, expires_at: nil)
      raise ArgumentError, "Amount is required" if amount.nil?
      raise ArgumentError, "Cannot give negative credits" if amount.to_i.negative?
      raise ArgumentError, "Credit amount must be a whole number" unless amount.to_i.integer?
      raise ArgumentError, "Expiration date must be a valid datetime" if expires_at && !expires_at.respond_to?(:to_datetime)
      raise ArgumentError, "Expiration date must be in the future" if expires_at && expires_at <= Time.current

      category = case reason&.to_s
                when "signup" then :signup_bonus
                when "referral" then :referral_bonus
                when /bonus/i then :bonus
                else :manual_adjustment
                end

      add_credits(
        amount.to_i,
        metadata: { reason: reason },
        category: category,
        expires_at: expires_at
      )
    end

    # =========================================
    # Credit Management (Internal API)
    # =========================================

    # Add credits to the wallet (internal method)
    def add_credits(amount, metadata: {}, category: :credit_added, expires_at: nil, fulfillment: nil)
      with_lock do
        amount = amount.to_i
        raise ArgumentError, "Cannot add non-positive credits" if amount <= 0

        previous_balance = credits

        transaction = transactions.create!(
          amount: amount,
          category: category,
          expires_at: expires_at,
          metadata: metadata,
          fulfillment: fulfillment
        )

        # Sync the wallet's `balance` column
        self.balance = credits
        save!

        notify_balance_change(:credits_added, amount)
        check_low_balance if !was_low_balance?(previous_balance) && low_balance?

        # To finish, let's return the transaction that has been just created so we can reference it in parts of the code
        # Useful, for example, to update the transaction's `fulfillment` reference in the subscription extension
        # after the credits have been awarded and the Fulfillment object has been created, we need to store it
        return transaction
      end
    end

    # Remove credits from the wallet (Internal method)
    #
    # After implementing the expiring FIFO inventory-like system through the Allocation model,
    # we no longer just create one -X transaction. Now we also allocate that spend across whichever
    # positive transactions still have leftover.
    #
    # TODO: This code enumerates all unexpired positive transactions each time.
    # That's fine if usage scale is moderate. We're already indexing this.
    # If performance becomes a concern, we need to create a separate model to store the partial allocations efficiently.
    def deduct_credits(amount, metadata: {}, category: :credit_deducted)
      with_lock do
      amount = amount.to_i
      raise InsufficientCredits, "Cannot deduct a non-positive amount" if amount <= 0

      # Figure out how many credits are available right now
      available = credits
      if amount > available && !allow_negative_balance?
        raise InsufficientCredits, "Insufficient credits (#{available} < #{amount})"
      end

      # Create the negative transaction that represents the spend
      spend_tx = transactions.create!(
        amount: -amount,
        category: category,
        metadata: metadata
      ) # We'll attach allocations to it next.

      # We now allocate from oldest/soonest-expiring positive transactions
      remaining_to_deduct = amount

      # 1) Gather all unexpired positives with leftover, order by expire time (soonest first),
      #    then fallback to any with no expiry (which should come last).
      positive_txs = transactions
                      .where("amount > 0")
                      .where("expires_at IS NULL OR expires_at > ?", Time.current)
                      .order(Arel.sql("COALESCE(expires_at, '9999-12-31 23:59:59'), id ASC"))
                      .lock("FOR UPDATE")
                      .select(:id, :amount, :expires_at)
                      .to_a

      positive_txs.each do |pt|
        # Calculate leftover amount for this transaction
        allocated = pt.incoming_allocations.sum(:amount)
        leftover = pt.amount - allocated
        next if leftover <= 0

        allocate_amount = [leftover, remaining_to_deduct].min

        # Create allocation
        Allocation.create!(
          spend_transaction: spend_tx,
          source_transaction: pt,
          amount: allocate_amount
        )

        remaining_to_deduct -= allocate_amount
        break if remaining_to_deduct <= 0
      end

      # If anything’s still left to deduct (and we allow negative?), we just leave it unallocated
      # TODO: implement this edge case; typically we'd create an unbacked negative record.
      if remaining_to_deduct.positive? && allow_negative_balance?
        # The spend_tx already has -amount, so effectively user goes negative
        # with no “source bucket” to allocate from. That is an edge case the end user's business logic must handle.
      elsif remaining_to_deduct.positive?
        # We shouldn’t get here if InsufficientCredits is raised earlier, but just in case:
        raise InsufficientCredits, "Not enough credit buckets to cover the deduction"
      end

      # Keep the `balance` column in sync
      self.balance = credits
      save!

      # Fire your existing notifications
      notify_balance_change(:credits_deducted, amount)
      spend_tx
      end
    end


    private

    # =========================================
    # Helper Methods
    # =========================================

    # Find an operation and validate its parameters
    # @param name [Symbol] Operation name
    # @param params [Hash] Operation parameters to validate
    # @return [Operation] The validated operation
    # @raise [InvalidOperation] If operation not found or validation fails
    def find_and_validate_operation(name, params)
      operation = UsageCredits.operations[name.to_sym]
      raise InvalidOperation, "Operation not found: #{name}" unless operation
      operation.validate!(params)
      operation
    end

    def insufficient_credits?(amount)
      !allow_negative_balance? && amount > credits
    end

    def allow_negative_balance?
      UsageCredits.configuration.allow_negative_balance
    end

    # =========================================
    # Balance Change Notifications
    # =========================================

    def notify_balance_change(event, amount)
      UsageCredits.handle_event(
        event,
        wallet: self,
        amount: amount,
        balance: credits
      )
    end

    def check_low_balance
      return unless low_balance?
      UsageCredits.handle_event(:low_balance_reached, wallet: self)
    end

    def low_balance?
      threshold = UsageCredits.configuration.low_balance_threshold
      return false if threshold.nil? || threshold.negative?
      credits <= threshold
    end

    def was_low_balance?(previous_balance)
      threshold = UsageCredits.configuration.low_balance_threshold
      return false if threshold.nil? || threshold.negative?
      previous_balance <= threshold
    end
  end

end
