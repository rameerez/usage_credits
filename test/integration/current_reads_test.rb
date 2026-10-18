# frozen_string_literal: true

require "test_helper"

# A credits command may run inside a caller's transaction that has already
# read something. Under MySQL's default repeatable read that first read fixes
# the transaction's snapshot, and taking the wallet lock afterwards does not
# refresh it. The wallets core tells a stale snapshot from a current one and
# then reads current rows, but only for what it reads inside its mutation
# context. usage_credits adds commands on top of the core, so these tests
# interleave two real connections, through those commands, to prove that each
# one decides on the ledger as it is now: `spend_credits_on`'s affordability
# check, and cancellation expiry followed by another debit in the same
# transaction. PostgreSQL reads current rows per statement and runs every test
# as well. SQLite serializes writers for the whole database, so none of these
# interleavings can exist there.
class UsageCredits::CurrentReadsTest < ActiveSupport::TestCase
  # Real connections must see each other's commits.
  self.use_transactional_tests = false

  PATIENCE = 10 # seconds

  setup do
    skip "SQLite serializes writers: no transaction can read, wait, then write" if sqlite?

    @owners = []
    UsageCredits.configure do |config|
      config.operation(:sixty_credit_task) { costs 60.credits }
      config.operation(:twenty_five_credit_task) { costs 25.credits }
    end
  end

  teardown do
    @owners&.each { |owner| owner.reload.destroy! }
  end

  # ───────────────────────────────────────────────────────────────────────────
  # spend_credits_on
  # ───────────────────────────────────────────────────────────────────────────

  test "spend_credits_on refuses credits that a debit committed after its caller's first read took, before its block runs" do
    wallet = new_wallet(credits: 100)
    refusals = Queue.new
    UsageCredits.configure { |config| config.on_insufficient_credits { |context| refusals << context.metadata } }
    block_ran = false

    outcome = after_a_stale_read(wallet, -> { UsageCredits::Wallet.find(wallet.id).deduct_credits(60) }) do |stale|
      stale.spend_credits_on(:sixty_credit_task) { block_ran = true }
    rescue UsageCredits::InsufficientCredits => error
      error
    end

    assert_kind_of UsageCredits::InsufficientCredits, outcome
    assert_equal "Insufficient credits (40 < 60)", outcome.message
    refute block_ran, "the block never runs on credits another request already took"
    assert_equal [{available: 40, required: 60, params: {}}], drain(refusals), "reported once, with the operation's own payload"
    assert_equal [-60], wallet.transactions.debits.pluck(:amount), "only the other request's debit"
    assert_equal 40, wallet.reload.credits
  end

  test "spend_credits_on accepts credits that a credit committed after its caller's first read added" do
    wallet = new_wallet(credits: 10)
    block_ran = false

    spend = after_a_stale_read(wallet, -> { UsageCredits::Wallet.find(wallet.id).give_credits(100, reason: "top_up") }) do |stale|
      stale.spend_credits_on(:twenty_five_credit_task) { block_ran = true }
    end

    assert block_ran, "a stale balance of 10 must not refuse 25 of the 110 there are"
    assert_equal(-25, spend.amount)
    assert_equal 85, wallet.reload.credits
    assert_equal 85, wallet.read_attribute(:balance), "the cached balance matches the ledger"
  end

  test "spend_credits_on spends only what a debit committed after its caller's first read left" do
    wallet = new_wallet
    expiring = wallet.give_credits(50, reason: "promo", expires_at: 10.days.from_now)
    evergreen = wallet.give_credits(50, reason: "signup")

    spend = after_a_stale_read(wallet, -> { UsageCredits::Wallet.find(wallet.id).deduct_credits(50) }) do |stale|
      stale.spend_credits_on(:twenty_five_credit_task)
    end

    assert_equal [[evergreen.id, 25]], spend.outgoing_allocations.pluck(:source_transaction_id, :amount)
    assert_equal 50, expiring.incoming_allocations.sum(:amount), "the expiring credit is never over-allocated"
    assert_equal 25, evergreen.reload.remaining_amount
    assert_equal 25, wallet.reload.credits
    assert_equal 25, wallet.read_attribute(:balance), "the cached balance matches the ledger"
  end

  # ───────────────────────────────────────────────────────────────────────────
  # expire_fulfillment_credits!
  # ───────────────────────────────────────────────────────────────────────────

  test "a debit after cancellation expiry in the same transaction sees what another request committed" do
    # B credits and spends after A's first read. A then shortens a
    # fulfillment's credits and debits in the same transaction. Expiry writes
    # the wallet row, so A's snapshot shows A's own revision: unless expiry
    # itself found the snapshot stale, the debit would trust it, spend the
    # subscription credit B already used up, and over-allocate it.
    wallet = new_wallet
    fulfillment = UsageCredits::Fulfillment.create!(wallet: wallet, credits_last_fulfillment: 100, fulfillment_type: "manual")
    subscription_credit = wallet.add_credits(100, category: :subscription_credits, expires_at: 30.days.from_now, fulfillment: fulfillment)
    evergreen = nil

    credit_and_spend = lambda do
      other = UsageCredits::Wallet.find(wallet.id)
      evergreen = other.give_credits(50, reason: "signup")
      other.deduct_credits(120) # the subscription credit's 100 first, then 20 of the new 50
    end

    expired, cached_after_expiry, spend = after_a_stale_read(wallet, credit_and_spend) do |stale|
      expired = stale.expire_fulfillment_credits!(fulfillment: fulfillment, expires_at: 10.days.from_now)
      [expired, stale.read_attribute(:balance), stale.deduct_credits(20)]
    end

    assert_equal 1, expired
    assert_equal 30, cached_after_expiry, "expiry caches the balance as it is now, not as A's snapshot saw it"
    assert_equal [[evergreen.id, 20]], spend.outgoing_allocations.pluck(:source_transaction_id, :amount)
    assert_equal 100, subscription_credit.incoming_allocations.sum(:amount), "the subscription credit is never over-allocated"
    assert_equal 40, evergreen.incoming_allocations.sum(:amount)
    assert_equal 10, wallet.reload.credits
    assert_equal 10, wallet.read_attribute(:balance), "the cached balance matches the ledger"
  end

  private

  def drain(queue)
    Array.new(queue.size) { queue.pop }
  end

  def sqlite?
    ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)
  end

  def new_wallet(credits: 0)
    owner = User.create!(email: "current-reads-#{SecureRandom.hex(6)}@example.com", name: "Current Reads")
    @owners << owner
    owner.credit_wallet.tap { |wallet| wallet.give_credits(credits, reason: "signup") if credits.positive? }
  end

  # Runs the block on its own connection, inside a transaction that first
  # takes an ordinary read of `wallet` (fixing a MySQL snapshot) and then
  # waits while `interleaved` commits on this test's connection.
  #
  # An error on either side fails the test with that error, at once, and
  # strands neither side: by the time this returns or raises, the worker has
  # ended, its transaction is committed or rolled back, and its connection
  # is back in the pool.
  def after_a_stale_read(wallet, interleaved)
    read_taken = Queue.new
    go_on = Queue.new

    worker = Thread.new do
      Thread.current.report_on_exception = false # the test raises what the worker ended with
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        UsageCredits::Wallet.transaction do
          stale = UsageCredits::Wallet.find(wallet.id)
          stale.credits
          read_taken << connection
          await(go_on, "the interleaved write")
          yield stale
        end
      end
    ensure
      read_taken.close # wakes the test should the worker fail before its read
    end

    worker_connection = await(read_taken, "the worker's first read", from: worker)
    refute_same ActiveRecord::Base.connection, worker_connection, "the worker runs on a connection of its own"
    interleaved.call
    go_on << true
    finish(worker)
  ensure
    go_on.close # a worker still waiting gives up, and its transaction rolls back
    settle(worker)
  end

  # The next value on `queue`, waited for no longer than `patience` seconds.
  # When none comes, a thread `from` that ended with an error fails the test
  # with that error: a sender that fails closes its queue on the way out.
  def await(queue, what, from: [], patience: PATIENCE)
    value = queue.pop(timeout: patience)
    return value unless value.nil?

    Array(from).each { |sender| sender.join(queue.closed? ? patience : 0) }
    flunk(queue.closed? ? "Stopped waiting for #{what}: the other side gave up" : "Gave up after #{patience} s waiting for #{what}")
  end

  # What the thread returned, waited for no longer than PATIENCE. An error
  # it ended with is raised here, as the test's own.
  def finish(thread)
    thread.join(PATIENCE) || flunk("Gave up after #{PATIENCE} s waiting for the worker to finish")
    thread.value
  end

  # Ends the worker before the test does: it gets PATIENCE to end on its
  # own, then is killed, which unwinds it all the same. Either way its
  # transaction is rolled back unless it committed, and its connection goes
  # back to the pool.
  def settle(thread)
    thread&.join(PATIENCE) || thread&.kill&.join(PATIENCE)
  rescue Minitest::Assertion, StandardError
    # Raised already by `finish`, or the test is failing for another reason.
  end
end
