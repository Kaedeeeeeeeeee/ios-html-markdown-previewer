#!/usr/bin/env ruby
# frozen_string_literal: true

# Offline authentication tests: stub asc and never access its keychain or API.
require "minitest/autorun"
{
  "APP_STORE_CONNECT_APP_ID" => "fixture-app",
  "APP_STORE_CONNECT_VERSION_STRING" => "1.8",
  "APP_STORE_CONNECT_BUILD_NUMBER" => "13",
  "ASC_API_KEY_ID" => "fixture-id",
  "ASC_API_ISSUER_ID" => "fixture-issuer",
  "ASC_API_KEY_PATH" => "unused-fixture-key"
}.each { |key, value| ENV[key] = value }
require_relative "submit-app-store-review"

class AscAuthenticationTest < Minitest::Test
  Status = Struct.new(:success?)

  def setup
    @cli_jwt_token = nil
    @cli_jwt_deadline = nil
  end

  def with_capture(value)
    original = Open3.method(:capture3)
    Open3.singleton_class.send(:define_method, :capture3) do |*argv|
      value.respond_to?(:call) ? value.call(*argv) : value
    end
    yield
  ensure
    Open3.singleton_class.send(:define_method, :capture3, original)
  end

  def token(exp: Time.now.to_i + 600)
    [base64url('{"alg":"ES256"}'), base64url(JSON.generate({ exp: exp })), base64url("fixture-signature")].join(".")
  end

  def test_valid_cli_token_is_memory_cached_for_at_most_nine_minutes
    expected = token
    calls = []
    capture = lambda do |*argv|
      calls << argv
      [expected + "\n", "", Status.new(true)]
    end
    with_capture(capture) do
      assert_equal expected, cli_jwt_token
      assert_equal expected, cli_jwt_token
    end
    assert_equal [["asc", "auth", "token", "--confirm"]], calls
    remaining = @cli_jwt_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_operator remaining, :>, 0
    assert_operator remaining, :<=, 540
  end

  def test_exp_claim_controls_cache_lifetime_and_expired_cache_refreshes
    first = token(exp: Time.now.to_i + 100)
    with_capture([first, "", Status.new(true)]) { assert_equal first, cli_jwt_token }
    assert_operator @cli_jwt_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), :<=, 70
    @cli_jwt_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1
    next_token = token(exp: Time.now.to_i + 300)
    with_capture([next_token, "", Status.new(true)]) { assert_equal next_token, cli_jwt_token }
  end

  def rejected(stdout, stderr = "", success = true)
    error = nil
    output = capture_io do
      with_capture([stdout, stderr, Status.new(success)]) do
        error = assert_raises(RuntimeError) { cli_jwt_token }
      end
    end
    assert_equal ["", ""], output
    assert_equal "ASC CLI token unavailable or invalid; check existing asc authentication.", error.message
    assert_nil error.cause
    assert_nil @cli_jwt_token
    assert_nil @cli_jwt_deadline
  end

  def test_empty_malformed_expired_and_missing_exp_tokens_are_rejected
    ["", "sensitive-malformed-output", "a.b.c", token(exp: Time.now.to_i + 20), token(exp: "not-an-exp")].each { |value| rejected(value) }
    missing_exp = [base64url("{}"), base64url("{}"), base64url("fixture")].join(".")
    rejected(missing_exp)
  end

  def test_cli_error_does_not_expose_stdout_stderr_or_token
    rejected(token, "sensitive-cli-error-detail", false)
    with_capture(->(*) { raise Errno::ENOENT, "sensitive-path" }) do
      error = assert_raises(RuntimeError) { cli_jwt_token }
      refute_includes error.message, "sensitive-path"
      assert_nil error.cause
    end
  end

  def require_mode(mode)
    env = {
      "ASC_USE_CLI_TOKEN" => mode,
      "ASC_API_KEY_ID" => nil,
      "ASC_API_ISSUER_ID" => nil,
      "ASC_API_KEY_PATH" => nil
    }
    Open3.capture3(env, RbConfig.ruby, "-e", 'require ARGV[0]; puts [USE_CLI_TOKEN, KEY_ID.nil?, ISSUER_ID.nil?, KEY_PATH.nil?].join(",")', File.expand_path("submit-app-store-review.rb", __dir__))
  end

  def test_cli_mode_loads_without_private_key_environment
    stdout, stderr, status = require_mode("true")
    assert status.success?, stderr
    assert_equal "true,true,true,true\n", stdout
  end

  def test_default_mode_still_requires_original_private_key_environment
    stdout, stderr, status = require_mode(nil)
    refute status.success?
    assert_empty stdout
    assert_includes stderr, "ASC_API_KEY_ID"
    assert_equal "fixture-id", KEY_ID
    assert_equal "fixture-issuer", ISSUER_ID
    assert_equal "unused-fixture-key", KEY_PATH
    refute USE_CLI_TOKEN
  end
end
