#!/usr/bin/env ruby
# frozen_string_literal: true

# Exercise the upload gate with an in-memory API; never read credentials or send requests.
{
  "APP_STORE_CONNECT_APP_ID" => "fixture-app",
  "APP_STORE_CONNECT_VERSION_STRING" => "1.7.1",
  "APP_STORE_CONNECT_BUILD_NUMBER" => "13",
  "APP_STORE_CONNECT_PLATFORM" => "IOS",
  "APP_STORE_CONNECT_PREVIOUS_VERSION_STRING" => "1.7",
  "APP_STORE_CONNECT_CHECK_RELEASE_GATE_ONLY" => "true",
  "ASC_API_KEY_ID" => "fixture",
  "ASC_API_ISSUER_ID" => "fixture",
  "ASC_API_KEY_PATH" => "unused-fixture-key"
}.each { |key, value| ENV[key] = value }
require_relative "submit-app-store-review"

def request(method, path, query: nil, body: nil)
  raise "Gate attempted a mutation" unless method == :get && body.nil?
  raise "Unexpected gate endpoint" unless path == "/v1/apps/fixture-app/appStoreVersions"
  raise "Gate did not filter previous version/platform" unless
    query["filter[versionString]"] == "1.7" && query["filter[platform]"] == "IOS"

  { "data" => @fixture_versions }
end

def wait_for_valid_build
  raise "Read-only gate entered upload/submission work"
end

def fixture(state, version: "1.7", platform: "IOS")
  { "attributes" => { "versionString" => version, "platform" => platform, "appStoreState" => state } }
end

def expect_blocked(versions, message)
  @fixture_versions = versions
  begin
    run
  rescue RuntimeError => error
    raise unless error.message.include?(message)
    return
  end
  raise "Gate incorrectly allowed #{message}"
end

%w[WAITING_FOR_REVIEW IN_REVIEW REJECTED DEVELOPER_REJECTED PREPARE_FOR_SUBMISSION].each do |state|
  expect_blocked([fixture(state)], state)
end
expect_blocked([], "not found")
expect_blocked([fixture("READY_FOR_DISTRIBUTION", version: "1.6")], "not found")
expect_blocked([fixture("READY_FOR_DISTRIBUTION", platform: "MAC_OS")], "not found")
%w[READY_FOR_DISTRIBUTION READY_FOR_SALE PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE].each do |state|
  @fixture_versions = [fixture(state)]
  run
end
puts "Release gate passed 12 approval, rejection, missing-version and read-only-mode checks."
