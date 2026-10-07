#!/usr/bin/env ruby
# frozen_string_literal: true

# In-memory GET-only fixtures; never read API credentials or contact ASC.
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "zlib"
{
  "APP_STORE_CONNECT_APP_ID" => "fixture-app",
  "APP_STORE_CONNECT_VERSION_STRING" => "1.8",
  "APP_STORE_CONNECT_VERSION_ID" => "draft-version",
  "APP_STORE_CONNECT_BUILD_NUMBER" => "13",
  "APP_STORE_CONNECT_PREVIOUS_VERSION_STRING" => "1.7",
  "APP_STORE_CONNECT_CHECK_STORE_ASSETS_ONLY" => "true",
  "ASC_API_KEY_ID" => "fixture",
  "ASC_API_ISSUER_ID" => "fixture",
  "ASC_API_KEY_PATH" => "unused-fixture-key"
}.each { |key, value| ENV[key] = value }
require_relative "submit-app-store-review"

Object.send(:alias_method, :real_request, :request)
Object.send(:alias_method, :run_store_gate, :run)

def request(method, path, query: nil, body: nil)
  raise "Read-only store gate attempted a mutation" unless method == :get && body.nil?
  @requests << [path, query]
  case path
  when "/v1/apps/fixture-app/appStoreVersions"
    { "data" => [{ "id" => "previous-version", "attributes" => { "versionString" => "1.7", "platform" => "IOS", "appStoreState" => "READY_FOR_DISTRIBUTION" } }] }
  when "/v1/appStoreVersions/draft-version"
    { "data" => @version }
  when "/v1/appStoreVersions/draft-version/appStoreVersionLocalizations"
    { "data" => @localizations }
  when "/v1/apps/fixture-app/appInfos"
    { "data" => @infos }
  when "/v1/appInfos/draft-info/appInfoLocalizations"
    { "data" => @info_localizations }
  when "/v1/appAssetLibraryRefData"
    raise AscError.new(503, { "errors" => [{ "code" => "fixture-unavailable" }] }) if @fail_catalog
    { "data" => { "attributes" => @catalog } }
  else
    response = @placements[path]
    raise "Unexpected GET endpoint #{path}; never read published AppInfo metadata" unless response
    response
  end
end

def wait_for_valid_build
  raise "Asset-only gate attempted to wait for build 13"
end

class StoreAssetsGateTest < Minitest::Test
  def setup
    @app_store_version_id = nil
    @requests = []
    @directory = Dir.mktmpdir("store-gate-fixture")
    @old_screenshots_root = STORE_SCREENSHOTS_ROOT
    Object.send(:remove_const, :STORE_SCREENSHOTS_ROOT)
    Object.const_set(:STORE_SCREENSHOTS_ROOT, @directory)
    @version = { "id" => "draft-version", "attributes" => { "versionString" => "1.8", "platform" => "IOS", "appStoreState" => "PREPARE_FOR_SUBMISSION" }, "relationships" => { "app" => { "data" => { "id" => "fixture-app" } } } }
    @infos = [{ "id" => "live-info", "attributes" => { "state" => "READY_FOR_DISTRIBUTION" } }, { "id" => "draft-info", "attributes" => { "state" => "PREPARE_FOR_SUBMISSION" } }]
    @localizations = EXPECTED_SCREENSHOT_LOCALES.map do |locale|
      { "id" => "loc-#{locale}", "attributes" => { "locale" => locale }.merge(metadata(locale, VERSION_METADATA_FIELDS)) }
    end
    @info_localizations = EXPECTED_SCREENSHOT_LOCALES.map do |locale|
      { "id" => "info-#{locale}", "attributes" => { "locale" => locale }.merge(metadata(locale, APP_INFO_METADATA_FIELDS)) }
    end
    group_names = EXPECTED_SCREENSHOT_GROUPS.keys
    @catalog = {
      "placementProfileGroups" => group_names.map { |group| { "placementProfileGroupId" => group, "platform" => group.start_with?("IPAD") ? "IPAD_APP_STORE" : "IPHONE_APP_STORE" } },
      "placementTypes" => [{ "placementTypeId" => "APP_SCREENSHOT", "specMappings" => group_names.map { |group| { "placementGroupId" => group, "specs" => ["spec-#{group}"] } } }],
      "features" => [{ "featureId" => "APP_STORE_VERSIONS", "placementPolicies" => [{ "placementType" => "APP_SCREENSHOT", "groupLimits" => [{ "groupIds" => group_names, "maxCount" => 10 }] }] }],
      "imageSpecs" => group_names.map { |group| { "specId" => "spec-#{group}", "dimensions" => { "minWidth" => 4, "maxWidth" => 4, "minHeight" => 3, "maxHeight" => 3 }, "mimeTypes" => ["image/png"], "fileExtensions" => [".png"], "maxFileSize" => 10_000 } }
    }
    @placements = {}
    EXPECTED_SCREENSHOT_LOCALES.each do |locale|
      FileUtils.mkdir_p(File.join(@directory, locale))
      response = { "data" => [], "included" => [] }
      EXPECTED_SCREENSHOT_GROUPS.each do |group, prefix|
        SCREENSHOT_SUFFIXES.each_with_index do |suffix, index|
          filename = "#{prefix}-#{suffix}.png"
          bytes = png
          File.binwrite(File.join(@directory, locale, filename), bytes)
          id = "#{locale}-#{prefix}-#{index}"
          response["data"] << { "id" => "p-#{id}", "attributes" => { "placementType" => "APP_SCREENSHOT", "placementGroup" => group, "state" => "ACTIVE" }, "relationships" => { "image" => { "data" => { "id" => "i-#{id}" } } } }
          response["included"] << { "type" => "appAssetLibraryImages", "id" => "i-#{id}", "attributes" => { "fileName" => filename, "fileSize" => bytes.bytesize, "referenceName" => "release-1.8-#{Digest::SHA256.hexdigest(bytes)[0, 16]}", "specId" => "spec-#{group}", "state" => "PREPARE_FOR_SUBMISSION", "imageAsset" => { "width" => 4, "height" => 3 } } }
        end
      end
      @placements["/v1/appStoreVersionLocalizations/loc-#{locale}/placements"] = response
    end
  end

  def teardown
    FileUtils.remove_entry(@directory)
    Object.send(:remove_const, :STORE_SCREENSHOTS_ROOT)
    Object.const_set(:STORE_SCREENSHOTS_ROOT, @old_screenshots_root)
  end

  def metadata(locale, fields)
    fields.to_h { |field, file| [field, File.read(File.join(STORE_METADATA_ROOT, locale, "#{file}.txt")).sub(/[\r\n]+\z/, "")] }
  end

  def png
    chunk = ->(kind, bytes) { [bytes.bytesize].pack("N") + kind + bytes + [Zlib.crc32(kind + bytes)].pack("N") }
    "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", [4, 3, 8, 2, 0, 0, 0].pack("NNCCCCC")) + chunk.call("IDAT", Zlib.deflate(("\0".b + "\0\0\0".b * 4) * 3)) + chunk.call("IEND", "".b)
  end

  def first_response
    @placements.fetch("/v1/appStoreVersionLocalizations/loc-en-US/placements")
  end

  def blocked(message)
    error = assert_raises(RuntimeError) { capture_io { run_store_gate } }
    assert_includes error.message, message
  end

  def test_full_72_image_32_field_readonly_gate_without_build
    capture_io { run_store_gate }
    assert_equal 72, @placements.values.sum { |r| r["data"].length }
    assert @requests.any? { |path, _| path.end_with?("loc-zh-Hant/placements") }
    refute @requests.any? { |path, _| path.include?("builds") || path.include?("live-info/") }
  end

  def test_each_metadata_field_is_exact
    VERSION_METADATA_FIELDS.each_key do |field|
      original = @localizations.first["attributes"][field]
      @localizations.first["attributes"][field] = original + " changed"
      blocked(field)
      @localizations.first["attributes"][field] = original
    end
    APP_INFO_METADATA_FIELDS.each_key do |field|
      original = @info_localizations.first["attributes"][field]
      @info_localizations.first["attributes"][field] = original + " changed"
      blocked(field)
      @info_localizations.first["attributes"][field] = original
    end
  end

  def test_missing_locale_and_published_app_info_are_rejected
    saved = @localizations.pop
    blocked("four version metadata locales")
    @localizations << saved
    @infos.last["attributes"]["state"] = "READY_FOR_DISTRIBUTION"
    blocked("editable AppInfo")
  end

  def test_published_wrong_app_wrong_version_and_wrong_platform_are_rejected
    %w[READY_FOR_DISTRIBUTION WAITING_FOR_REVIEW].each do |state|
      @version["attributes"]["appStoreState"] = state
      blocked("exact editable")
    end
    @version["attributes"]["appStoreState"] = "PREPARE_FOR_SUBMISSION"
    @version["relationships"]["app"]["data"]["id"] = "another-app"
    blocked("exact editable")
    @version["relationships"]["app"]["data"]["id"] = "fixture-app"
    @version["attributes"]["versionString"] = "1.7"
    blocked("exact editable")
    @version["attributes"]["versionString"] = "1.8"
    @version["attributes"]["platform"] = "MAC_OS"
    blocked("exact editable")
  end

  def test_missing_duo_and_wrong_order_are_rejected
    saved = first_response["data"].pop
    blocked("Expected six")
    first_response["data"] << saved
    first_response["data"][0], first_response["data"][1] = first_response["data"][1], first_response["data"][0]
    blocked("identity/state mismatch")
  end

  def test_wrong_file_hash_spec_geometry_and_unusable_image_are_rejected
    attrs = first_response["included"].first["attributes"]
    { "fileName" => "old.png", "referenceName" => "release-1.8-stale", "fileSize" => 1, "state" => "REJECTED" }.each do |field, invalid|
      original = attrs[field]; attrs[field] = invalid
      blocked("identity/state mismatch")
      attrs[field] = original
    end
    attrs["specId"] = "another-group-spec"
    blocked("specification/dimensions")
    attrs["specId"] = "spec-IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"
    attrs["imageAsset"]["width"] = 3
    blocked("specification/dimensions")
  end

  def test_failed_placement_and_missing_catalog_group_are_rejected
    first_response["data"].first["attributes"]["state"] = "FAILED"
    blocked("identity/state mismatch")
    first_response["data"].first["attributes"]["state"] = "ACTIVE"
    @catalog["placementProfileGroups"].pop
    blocked("Missing live screenshot profile")
  end

  def test_unapproved_extra_group_is_rejected
    extra = Marshal.load(Marshal.dump(first_response["data"].first))
    extra["attributes"]["placementGroup"] = "UNAPPROVED_GROUP"
    first_response["data"] << extra
    blocked("Unexpected screenshot group")
  end

  def test_readonly_request_guard_blocks_mutation_before_key_access
    error = assert_raises(RuntimeError) { real_request(:patch, "/v1/appInfos/live-info", body: {}) }
    assert_includes error.message, "GET requests only"
  end

  def test_gate_failure_cannot_enter_review_submission_fallback
    @version["attributes"]["appStoreState"] = "PREPARE_FOR_SUBMISSION"
    @localizations.first["attributes"]["whatsNew"] = "stale"
    error = assert_raises(RuntimeError) { capture_io { submit_app_store_version } }
    assert_includes error.message, "whatsNew"
    refute @requests.any? { |path, _| path.include?("reviewSubmissions") }
  end

  def test_api_gate_failure_cannot_enter_review_submission_fallback
    @fail_catalog = true
    assert_raises(AscError) { capture_io { submit_app_store_version } }
    refute @requests.any? { |path, _| path.include?("reviewSubmissions") }
  end

  def test_legacy_cleanup_true_fails_before_any_request
    Object.send(:remove_const, :CLEAN_SCREENSHOT_DUPLICATES)
    Object.const_set(:CLEAN_SCREENSHOT_DUPLICATES, true)
    blocked("Legacy screenshot cleanup is disabled")
    assert_empty @requests
  ensure
    Object.send(:remove_const, :CLEAN_SCREENSHOT_DUPLICATES)
    Object.const_set(:CLEAN_SCREENSHOT_DUPLICATES, false)
  end
end
