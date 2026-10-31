#!/usr/bin/env ruby
# frozen_string_literal: true

# Exercise the review submission write path with an in-memory API that enforces
# App Store Connect's create rules; never read credentials or send requests.
require "minitest/autorun"
{
  "APP_STORE_CONNECT_APP_ID" => "fixture-app",
  "APP_STORE_CONNECT_VERSION_STRING" => "1.8.2",
  "APP_STORE_CONNECT_VERSION_ID" => "draft-version",
  "APP_STORE_CONNECT_BUILD_NUMBER" => "15",
  "ASC_API_KEY_ID" => "fixture",
  "ASC_API_ISSUER_ID" => "fixture",
  "ASC_API_KEY_PATH" => "unused-fixture-key"
}.each { |key, value| ENV[key] = value }
require_relative "submit-app-store-review"

def request(method, path, query: nil, body: nil)
  @calls << [method, path, body]
  case [method, path]
  when [:post, "/v1/reviewSubmissions"]
    if body.dig(:data, :relationships).key?(:appStoreVersionForReview)
      raise AscError.new(409, { "errors" => [{ "code" => "ENTITY_ERROR.RELATIONSHIP.NOT_ALLOWED" }] })
    end
    { "data" => { "id" => "new-submission" } }
  when [:post, "/v1/reviewSubmissionItems"]
    { "data" => { "id" => "new-item" } }
  when [:patch, "/v1/reviewSubmissions/new-submission"]
    { "data" => { "attributes" => { "state" => "WAITING_FOR_REVIEW" } } }
  when [:get, "/v1/reviewSubmissions"]
    { "data" => [] }
  else
    raise "Unexpected request #{method} #{path}"
  end
end

class ReviewSubmissionTest < Minitest::Test
  def setup
    @calls = []
    @app_store_version_id = nil
  end

  def writes
    @calls.reject { |method, _, _| method == :get }
  end

  def test_creates_with_app_only_then_adds_version_as_item_and_submits
    state = nil
    capture_io { state = create_and_submit_review_submission("fixture-app", "IOS") }

    assert_equal "WAITING_FOR_REVIEW", state
    assert_equal [
      [:post, "/v1/reviewSubmissions"],
      [:post, "/v1/reviewSubmissionItems"],
      [:patch, "/v1/reviewSubmissions/new-submission"]
    ], writes.map { |method, path, _| [method, path] }

    create_body = writes[0][2]
    assert_equal [:app], create_body.dig(:data, :relationships).keys
    assert_equal "fixture-app", create_body.dig(:data, :relationships, :app, :data, :id)

    item_relationships = writes[1][2].dig(:data, :relationships)
    assert_equal "new-submission", item_relationships.dig(:reviewSubmission, :data, :id)
    assert_equal "draft-version", item_relationships.dig(:appStoreVersion, :data, :id)

    assert_equal true, writes[2][2].dig(:data, :attributes, :submitted)
  end
end
