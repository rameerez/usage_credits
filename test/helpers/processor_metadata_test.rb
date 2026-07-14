# frozen_string_literal: true

require "test_helper"

class ProcessorMetadataTest < ActiveSupport::TestCase
  test "normalizes keys and serializes structured values as JSON strings" do
    metadata = UsageCredits::ProcessorMetadata.normalize(
      purchase_type: "credit_pack",
      credits: 100,
      rollover: false,
      details: {tier: "pro"},
      tags: %w[one two]
    )

    assert_equal "credit_pack", metadata["purchase_type"]
    assert_equal "100", metadata["credits"]
    assert_equal "false", metadata["rollover"]
    assert_equal({"tier" => "pro"}, ActiveSupport::JSON.decode(metadata["details"]))
    assert_equal %w[one two], ActiveSupport::JSON.decode(metadata["tags"])
  end

  test "enforces processor key and value limits before checkout" do
    assert_raises(ArgumentError) do
      UsageCredits::ProcessorMetadata.normalize("x" * 41 => "value")
    end
    assert_raises(ArgumentError) do
      UsageCredits::ProcessorMetadata.normalize(value: "x" * 501)
    end
    assert_raises(ArgumentError) do
      UsageCredits::ProcessorMetadata.normalize((1..51).to_h { |index| ["key_#{index}", index] })
    end
  end

  test "rejects non hash metadata" do
    error = assert_raises(ArgumentError) do
      UsageCredits::ProcessorMetadata.normalize("not metadata")
    end

    assert_includes error.message, "hash-like"
  end
end
