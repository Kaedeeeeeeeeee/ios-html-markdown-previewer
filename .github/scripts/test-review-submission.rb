#!/usr/bin/env ruby
# frozen_string_literal: true

# Exercise review-submission creation with an in-memory API; never read credentials or send requests.
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
  @requests << [method, path, body]
  case [method, path]
  when [:post, "/v1/reviewSubmissions"]
    if body.dig(:data, :relationships, :appStoreVersionForReview)
      raise AscError.new(409, { "errors" => [{ "code" => "ENTITY_ERROR.RELATIONSHIP.INVALID" }] })
    end
    { "data" => { "id" => "new-submission" } }
  when [:post, "/v1/reviewSubmissionItems"]
    { "data" => { "id" => "item" } }
  when [:patch, "/v1/reviewSubmissions/new-submission"]
    { "data" => { "id" => "new-submission", "attributes" => { "state" => "WAITING_FOR_REVIEW" } } }
  else
    raise "Unexpected #{method} #{path}"
  end
end

class ReviewSubmissionTest < Minitest::Test
  def setup
    @requests = []
    @app_store_version_id = nil
  end

  def test_creates_submission_without_version_then_adds_version_item_and_submits
    state = create_and_submit_review_submission("fixture-app", "IOS")

    assert_equal "WAITING_FOR_REVIEW", state
    assert_equal [
      [:post, "/v1/reviewSubmissions"],
      [:post, "/v1/reviewSubmissionItems"],
      [:patch, "/v1/reviewSubmissions/new-submission"]
    ], @requests.map { |method, path, _| [method, path] }
    create_body = @requests.first[2]
    assert_equal({ app: { data: { type: "apps", id: "fixture-app" } } }, create_body.dig(:data, :relationships))
    item_body = @requests[1][2]
    assert_equal "draft-version", item_body.dig(:data, :relationships, :appStoreVersion, :data, :id)
    assert_equal "new-submission", item_body.dig(:data, :relationships, :reviewSubmission, :data, :id)
  end
end
