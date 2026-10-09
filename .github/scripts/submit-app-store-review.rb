#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "open3"
require "openssl"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
APP_ID = ENV.fetch("APP_STORE_CONNECT_APP_ID")
CONFIGURED_APP_STORE_VERSION_ID = ENV["APP_STORE_CONNECT_VERSION_ID"]
APP_STORE_VERSION_STRING = ENV.fetch("APP_STORE_CONNECT_VERSION_STRING")
BUILD_NUMBER = ENV.fetch("APP_STORE_CONNECT_BUILD_NUMBER")
PLATFORM = ENV.fetch("APP_STORE_CONNECT_PLATFORM", "IOS")
USE_CLI_TOKEN = ENV["ASC_USE_CLI_TOKEN"] == "true"
KEY_ID = USE_CLI_TOKEN ? nil : ENV.fetch("ASC_API_KEY_ID")
ISSUER_ID = USE_CLI_TOKEN ? nil : ENV.fetch("ASC_API_ISSUER_ID")
KEY_PATH = USE_CLI_TOKEN ? nil : ENV.fetch("ASC_API_KEY_PATH")
SUBMISSION_READY_RETRY_COUNT = Integer(ENV.fetch("APP_STORE_CONNECT_SUBMIT_RETRIES", "4"))
CLEAN_SCREENSHOT_DUPLICATES = ENV.fetch("APP_STORE_CONNECT_CLEAN_SCREENSHOT_DUPLICATES", "false") == "true"
SUBMIT_FOR_REVIEW = ENV.fetch("APP_STORE_CONNECT_SUBMIT_FOR_REVIEW", "false") == "true"
RELEASE_TYPE = ENV.fetch("APP_STORE_CONNECT_RELEASE_TYPE", "AFTER_APPROVAL")
EXPECTED_SCREENSHOT_GROUPS = {
  "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE" => "iphone",
  "IPAD_13_PROFILE" => "ipad",
  "IPHONE_DUO_PROFILE" => "duo"
}.freeze
SCREENSHOT_SUFFIXES = %w[01-html-report 02-markdown-preview 03-json-preview 04-yaml-preview 05-batch-import 06-library].freeze
EXPECTED_SCREENSHOT_LOCALES = %w[en-US zh-Hans ja zh-Hant].freeze
REPOSITORY_ROOT = File.expand_path("../..", __dir__)
STORE_METADATA_ROOT = ENV.fetch("FASTLANE_METADATA_PATH", File.join(REPOSITORY_ROOT, "fastlane/metadata"))
STORE_SCREENSHOTS_ROOT = ENV.fetch("APP_STORE_CONNECT_SCREENSHOTS_PATH", File.join(REPOSITORY_ROOT, "docs/app-store-screenshots"))
RELEASE_NOTES_HANDOFF = File.join(REPOSITORY_ROOT, "docs/updates/#{APP_STORE_VERSION_STRING}-release-notes.md")
VERSION_METADATA_FIELDS = { "description" => "description", "keywords" => "keywords", "promotionalText" => "promotional_text", "whatsNew" => "release_notes", "supportUrl" => "support_url" }.freeze
APP_INFO_METADATA_FIELDS = { "name" => "name", "subtitle" => "subtitle", "privacyPolicyUrl" => "privacy_url" }.freeze
USABLE_IMAGE_STATES = %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW WAITING_FOR_REVIEW IN_REVIEW ACCEPTED APPROVED COMPLETE].freeze
USABLE_PLACEMENT_STATES = %w[PARENT_PREPARE_FOR_SUBMISSION PARENT_READY_FOR_REVIEW PARENT_WAITING_FOR_REVIEW PARENT_IN_REVIEW PARENT_APPROVED ACTIVE].freeze

class AscError < StandardError
  attr_reader :status, :body

  def initialize(status, body)
    @status = status
    @body = body
    super("App Store Connect API returned #{status}: #{JSON.pretty_generate(body)}")
  end
end

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def raw_ecdsa_signature(der_signature)
  sequence = OpenSSL::ASN1.decode(der_signature)
  sequence.value.map { |integer| integer.value.to_s(2).rjust(32, "\0")[-32, 32] }.join
end

def jwt_token
  return cli_jwt_token if USE_CLI_TOKEN

  key = OpenSSL::PKey.read(File.read(KEY_PATH))
  now = Time.now.to_i
  header = { alg: "ES256", kid: KEY_ID, typ: "JWT" }
  payload = { iss: ISSUER_ID, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" }
  signing_input = [base64url(JSON.generate(header)), base64url(JSON.generate(payload))].join(".")
  signature = raw_ecdsa_signature(key.sign(OpenSSL::Digest.new("SHA256"), signing_input))
  [signing_input, base64url(signature)].join(".")
end

def cli_jwt_token
  now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  return @cli_jwt_token if @cli_jwt_token && now < @cli_jwt_deadline

  # Capture argv directly, without a shell. A live JWT or CLI error output must
  # never be printed, exported to the environment, or written to a report.
  stdout, _stderr, status = Open3.capture3("asc", "auth", "token", "--confirm")
  token = stdout.strip
  unless status.success? && token.match?(/\A[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/)
    raise "Invalid CLI token"
  end
  payload = JSON.parse(Base64.urlsafe_decode64(token.split(".")[1]))
  expiry = payload.fetch("exp")
  raise "Invalid CLI token expiration" unless expiry.is_a?(Integer)

  lifetime = [expiry - Time.now.to_i - 30, 9 * 60].min
  raise "CLI token is already expired" unless lifetime.positive?

  @cli_jwt_token = token
  @cli_jwt_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + lifetime
  token
rescue StandardError
  @cli_jwt_token = nil
  @cli_jwt_deadline = nil
  raise "ASC CLI token unavailable or invalid; check existing asc authentication.", cause: nil
end

def request(method, path, query: nil, body: nil)
  if ENV["APP_STORE_CONNECT_CHECK_STORE_ASSETS_ONLY"] == "true" && method != :get
    raise "Store-assets-only mode permits GET requests only."
  end
  uri = URI("#{API_BASE}#{path}")
  uri.query = URI.encode_www_form(query) if query

  klass = {
    delete: Net::HTTP::Delete,
    get: Net::HTTP::Get,
    post: Net::HTTP::Post,
    patch: Net::HTTP::Patch
  }.fetch(method)

  attempts = 0
  loop do
    attempts += 1
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 20
    http.read_timeout = 90

    req = klass.new(uri)
    req["Authorization"] = "Bearer #{jwt_token}"
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(body) if body

    response = http.request(req)
    begin
      parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
    rescue JSON::ParserError
      raise AscError.new("invalid-json", { raw: response.body.to_s })
    end
    return parsed if response.is_a?(Net::HTTPSuccess)

    if response.code.to_i == 429 && attempts < 5
      sleep(15 * attempts)
      next
    end

    raise AscError.new(response.code, parsed)
  end
end

def app_store_version_id
  return @app_store_version_id if @app_store_version_id

  unless CONFIGURED_APP_STORE_VERSION_ID.to_s.empty?
    @app_store_version_id = CONFIGURED_APP_STORE_VERSION_ID
    puts "Using configured App Store version #{@app_store_version_id}."
    return @app_store_version_id
  end

  12.times do |attempt|
    versions = request(
      :get,
      "/v1/apps/#{APP_ID}/appStoreVersions",
      query: {
        "limit" => "50",
        "fields[appStoreVersions]" => "versionString,appStoreState,platform"
      }
    ).fetch("data", [])

    version = versions.find do |candidate|
      attributes = candidate.fetch("attributes", {})
      attributes["versionString"] == APP_STORE_VERSION_STRING &&
        attributes["platform"] == PLATFORM
    end
    if version
      @app_store_version_id = version.fetch("id")
      state = version.fetch("attributes", {})["appStoreState"]
      puts "Resolved App Store version #{APP_STORE_VERSION_STRING}: id=#{@app_store_version_id} state=#{state}."
      return @app_store_version_id
    end

    puts "App Store version #{APP_STORE_VERSION_STRING} is not visible yet."
    sleep(10) unless attempt == 11
  end

  raise "Could not resolve App Store version #{APP_STORE_VERSION_STRING} for app #{APP_ID}."
end

def fetch_builds
  queries = [
    ["/v1/apps/#{APP_ID}/builds", {
      "limit" => "50",
      "sort" => "-uploadedDate",
      "fields[builds]" => "version,processingState,uploadedDate,expired,usesNonExemptEncryption"
    }],
    ["/v1/builds", {
      "filter[app]" => APP_ID,
      "filter[version]" => BUILD_NUMBER,
      "limit" => "50",
      "sort" => "-uploadedDate",
      "fields[builds]" => "version,processingState,uploadedDate,expired,usesNonExemptEncryption"
    }]
  ]

  last_error = nil
  queries.each do |path, query|
    return request(:get, path, query: query).fetch("data", [])
  rescue AscError => e
    last_error = e
  end
  raise last_error
end

def wait_for_valid_build
  60.times do |attempt|
    builds = fetch_builds.select do |build|
      build.fetch("attributes", {}).fetch("version", nil) == BUILD_NUMBER &&
        build.fetch("attributes", {}).fetch("expired", false) != true
    end

    build = builds.first
    if build
      attrs = build.fetch("attributes", {})
      puts "Found build #{BUILD_NUMBER}: id=#{build.fetch("id")} processingState=#{attrs["processingState"]}"
      return build if attrs["processingState"] == "VALID"
    else
      puts "Build #{BUILD_NUMBER} is not visible in App Store Connect yet."
    end

    sleep(attempt < 10 ? 30 : 60)
  end

  raise "Timed out waiting for App Store Connect build #{BUILD_NUMBER} to become VALID"
end

def patch_build_encryption(build_id)
  request(
    :patch,
    "/v1/builds/#{build_id}",
    body: {
      data: {
        type: "builds",
        id: build_id,
        attributes: {
          usesNonExemptEncryption: false
        }
      }
    }
  )
  puts "Marked build #{build_id} usesNonExemptEncryption=false."
rescue AscError => e
  puts "Warning: could not update build encryption flag: #{e.message}"
end

def attach_build_to_version(build_id)
  request(
    :patch,
    "/v1/appStoreVersions/#{app_store_version_id}/relationships/build",
    body: {
      data: {
        type: "builds",
        id: build_id
      }
    }
  )
  puts "Attached build #{build_id} to App Store version #{app_store_version_id}."
end

OPEN_REVIEW_SUBMISSION_STATES = %w[
  READY_FOR_REVIEW
  UNRESOLVED_ISSUES
].freeze

PENDING_REVIEW_SUBMISSION_STATES = %w[
  WAITING_FOR_REVIEW
  IN_REVIEW
].freeze

BLOCKING_REVIEW_SUBMISSION_STATES = (OPEN_REVIEW_SUBMISSION_STATES + %w[CANCELING]).freeze

def fetch_app_store_version
  request(
    :get,
    "/v1/appStoreVersions/#{app_store_version_id}",
    query: {
      "include" => "app,build",
      "fields[appStoreVersions]" => "versionString,appStoreState,platform,app,build"
    }
  ).fetch("data")
end

def app_store_version_context(label)
  version = fetch_app_store_version
  attrs = version.fetch("attributes", {})
  app_id = version.dig("relationships", "app", "data", "id") || APP_ID
  build_id = version.dig("relationships", "build", "data", "id")
  platform = attrs["platform"] || PLATFORM
  state = attrs.fetch("appStoreState")
  puts "#{label}: App Store version #{attrs["versionString"]} app=#{app_id} platform=#{platform} appStoreState=#{state} build=#{build_id || "-"}."
  {
    app_id: app_id,
    build_id: build_id,
    platform: platform,
    app_store_state: state
  }
end

def asc_error_code?(error, code)
  error.body.fetch("errors", []).any? { |item| item["code"] == code }
end

def retryable_version_not_ready?(error)
  JSON.generate(error.body).include?("Version is not ready to be submitted yet")
end

def app_store_version_localizations(fields: "locale")
  request(
    :get,
    "/v1/appStoreVersions/#{app_store_version_id}/appStoreVersionLocalizations",
    query: {
      "limit" => "50",
      "fields[appStoreVersionLocalizations]" => fields
    }
  ).fetch("data", [])
end

# Paginated GET-only collection reader. Never forward a JWT to a links.next host.
def asc_collection(path, query: nil)
  data, included, visited = [], {}, []
  loop do
    key = [path, query]
    raise "ASC pagination cycle" if visited.include?(key)
    visited << key
    response = request(:get, path, query: query)
    data.concat(response.fetch("data"))
    response.fetch("included", []).each { |item| included[[item.fetch("type"), item.fetch("id")]] = item }
    next_url = response.dig("links", "next")
    break if next_url.to_s.empty?

    uri = URI(next_url)
    unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com" && uri.port == 443
      raise "Unexpected ASC pagination host"
    end
    path = uri.path
    query = URI.decode_www_form(uri.query.to_s).to_h
  end
  { "data" => data, "included" => included.values }
end

def require_editable_store_version!
  version = fetch_app_store_version
  attrs = version.fetch("attributes")
  unless attrs["versionString"] == APP_STORE_VERSION_STRING && attrs["platform"] == PLATFORM &&
      attrs["appStoreState"] == "PREPARE_FOR_SUBMISSION" &&
      version.dig("relationships", "app", "data", "id") == APP_ID
    raise "Store asset gate requires this app's exact editable #{APP_STORE_VERSION_STRING} #{PLATFORM} version."
  end
  version
end

def verify_metadata_fields!(locale, attributes, fields)
  fields.each do |field, filename|
    expected = File.read(File.join(STORE_METADATA_ROOT, locale, "#{filename}.txt")).sub(/[\r\n]+\z/, "")
    raise "Empty local metadata #{locale}/#{filename}" if expected.empty?
    unless attributes[field] == expected
      raise "Store metadata mismatch: #{locale}/#{field}. Synchronize the draft before continuing."
    end
  end
end

def verify_store_metadata!
  localizations = asc_collection("/v1/appStoreVersions/#{app_store_version_id}/appStoreVersionLocalizations")["data"]
  actual_locales = localizations.map { |item| item.fetch("attributes").fetch("locale") }
  unless actual_locales.sort == EXPECTED_SCREENSHOT_LOCALES.sort
    raise "Expected exactly four version metadata locales, found #{actual_locales.inspect}."
  end
  infos = asc_collection("/v1/apps/#{APP_ID}/appInfos")["data"]
  drafts = infos.select { |info| (info.dig("attributes", "state") || info.dig("attributes", "appStoreState")) == "PREPARE_FOR_SUBMISSION" }
  raise "Expected one editable AppInfo; published AppInfo must remain untouched." unless drafts.length == 1
  info_localizations = asc_collection("/v1/appInfos/#{drafts.first.fetch('id')}/appInfoLocalizations")["data"]
  unless info_localizations.map { |item| item.fetch("attributes").fetch("locale") }.sort == EXPECTED_SCREENSHOT_LOCALES.sort
    raise "Expected exactly four draft AppInfo locales."
  end
  by_locale = info_localizations.to_h { |item| [item.fetch("attributes").fetch("locale"), item] }
  localizations.each do |item|
    locale = item.fetch("attributes").fetch("locale")
    verify_metadata_fields!(locale, item.fetch("attributes"), VERSION_METADATA_FIELDS)
    verify_metadata_fields!(locale, by_locale.fetch(locale).fetch("attributes"), APP_INFO_METADATA_FIELDS)
  end
  puts "Store metadata verified: 4 locales, 32 fields exact; draft AppInfo=#{drafts.first.fetch('id')}."
  localizations
end

def screenshot_group_specs(catalog, group)
  profile = catalog.fetch("placementProfileGroups").find { |item| item["placementProfileGroupId"] == group }
  raise "Missing live screenshot profile #{group}" unless profile && %w[IPHONE_APP_STORE IPAD_APP_STORE].include?(profile["platform"])
  screenshot_type = catalog.fetch("placementTypes").find { |item| item["placementTypeId"] == "APP_SCREENSHOT" }
  mapping = screenshot_type&.fetch("specMappings")&.find { |item| item["placementGroupId"] == group }
  raise "Missing live APP_SCREENSHOT mapping #{group}" unless mapping
  feature = catalog.fetch("features").find { |item| item["featureId"] == "APP_STORE_VERSIONS" }
  limits = feature&.fetch("placementPolicies")&.select { |item| item["placementType"] == "APP_SCREENSHOT" }&.flat_map do |policy|
    policy.fetch("groupLimits").select { |limit| limit.fetch("groupIds").include?(group) }.map { |limit| limit.fetch("maxCount") }
  end
  raise "Live screenshot limit does not allow six #{group} images" if limits.nil? || limits.empty? || limits.min < SCREENSHOT_SUFFIXES.length
  specs = catalog.fetch("imageSpecs").select { |item| mapping.fetch("specs").include?(item.fetch("specId")) }
  raise "Missing live image specs #{group}" if specs.empty?
  specs
end

def local_screenshot_identity(locale, filename)
  bytes = File.binread(File.join(STORE_SCREENSHOTS_ROOT, locale, filename))
  unless bytes.bytesize >= 33 && bytes.start_with?("\x89PNG\r\n\x1a\n".b) && bytes.byteslice(12, 4) == "IHDR"
    raise "Expected a PNG screenshot: #{locale}/#{filename}"
  end
  width, height = bytes.byteslice(16, 8).unpack("NN")
  color_type = bytes.getbyte(25)
  raise "Screenshot has an alpha channel: #{locale}/#{filename}" if [4, 6].include?(color_type)
  { width: width, height: height, size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
end

# Reused screenshots keep the reference name of the version that uploaded them.
# Only this version's own release-note handoff can declare that earlier version.
def screenshot_source_version
  handoff = File.file?(RELEASE_NOTES_HANDOFF) ? File.read(RELEASE_NOTES_HANDOFF) : ""
  handoff[/Screenshots carried over unchanged from (\d+(?:\.\d+)+) \(\d+\)\./, 1] || APP_STORE_VERSION_STRING
end

def verify_expected_screenshot_inventory!(localizations = nil)
  localizations ||= app_store_version_localizations
  source_version = screenshot_source_version
  puts "Expecting screenshot reference names from version #{source_version}."
  catalog_data = request(:get, "/v1/appAssetLibraryRefData").fetch("data")
  if catalog_data.is_a?(Array)
    raise "Expected one live asset catalog" unless catalog_data.length == 1
    catalog_data = catalog_data.first
  end
  catalog = catalog_data.fetch("attributes")
  specs = EXPECTED_SCREENSHOT_GROUPS.to_h { |group, _| [group, screenshot_group_specs(catalog, group)] }
  by_locale = localizations.to_h { |item| [item.fetch("attributes").fetch("locale"), item] }
  total = 0
  EXPECTED_SCREENSHOT_LOCALES.each do |locale|
    loc = by_locale.fetch(locale) { raise "Missing screenshot locale #{locale}" }
    response = asc_collection("/v1/appStoreVersionLocalizations/#{loc.fetch('id')}/placements", query: {
      "limit" => "200", "sort" => "placementGroupPosition", "include" => "image",
      "fields[appAssetLibraryImages]" => "category,fileName,fileSize,referenceName,specId,state,imageAsset"
    })
    screenshots = response.fetch("data").select { |item| item.dig("attributes", "placementType") == "APP_SCREENSHOT" }
    unless (screenshots.map { |item| item.dig("attributes", "placementGroup") }.uniq - EXPECTED_SCREENSHOT_GROUPS.keys).empty?
      raise "Unexpected screenshot group in #{locale}; only the approved three profiles are permitted."
    end
    images = response.fetch("included").select { |item| item["type"] == "appAssetLibraryImages" }.to_h { |item| [item.fetch("id"), item] }
    EXPECTED_SCREENSHOT_GROUPS.each do |group, prefix|
      placements = screenshots.select { |item| item.dig("attributes", "placementGroup") == group }
      raise "Expected six #{locale}/#{group} screenshots, found #{placements.length}" unless placements.length == SCREENSHOT_SUFFIXES.length
      # ASC supports sort=placementGroupPosition but does not expose that value
      # in placement attributes. Verify its returned order by exact image names.
      placements.zip(SCREENSHOT_SUFFIXES).each do |placement, suffix|
        filename = "#{prefix}-#{suffix}.png"
        local = local_screenshot_identity(locale, filename)
        image = images.fetch(placement.dig("relationships", "image", "data", "id")) { raise "Missing included screenshot image" }
        attrs = image.fetch("attributes")
        expected_reference = "release-#{source_version}-#{local.fetch(:sha256)[0, 16]}"
        unless attrs["fileName"] == filename && attrs["fileSize"] == local.fetch(:size) && attrs["referenceName"] == expected_reference &&
            USABLE_IMAGE_STATES.include?(attrs["state"]) && USABLE_PLACEMENT_STATES.include?(placement.dig("attributes", "state"))
          raise "Screenshot identity/state mismatch: #{locale}/#{group}/#{filename}"
        end
        spec = specs.fetch(group).find { |item| item["specId"] == attrs["specId"] }
        dimensions = spec&.fetch("dimensions")
        pixels = attrs.fetch("imageAsset", {}) || {}
        unless dimensions && dimensions.values_at("minWidth", "maxWidth") == [local[:width], local[:width]] &&
            dimensions.values_at("minHeight", "maxHeight") == [local[:height], local[:height]] &&
            pixels.values_at("width", "height") == [local[:width], local[:height]] &&
            spec.fetch("mimeTypes").include?("image/png") && spec.fetch("fileExtensions").include?(".png") && local[:size] <= spec.fetch("maxFileSize")
          raise "Screenshot live specification/dimensions mismatch: #{locale}/#{group}/#{filename}"
        end
        total += 1
      end
      puts "Asset Library inventory verified: locale=#{locale} group=#{group} count=#{placements.length}."
    end
  end
  raise "Expected 72 approved screenshots, found #{total}" unless total == 72
end

def verify_store_assets!
  require_editable_store_version!
  localizations = verify_store_metadata!
  verify_expected_screenshot_inventory!(localizations)
  puts "Store assets verified: four locales and 72 ordered screenshots; no remote writes."
end

def dump_readiness(context)
  puts "Readiness: state=#{context.fetch(:app_store_state)} editable=#{context.fetch(:app_store_state) == "PREPARE_FOR_SUBMISSION"}."

  build_id = context.fetch(:build_id)
  if build_id
    build = request(
      :get,
      "/v1/builds/#{build_id}",
      query: {
        "fields[builds]" => "version,processingState,expired,usesNonExemptEncryption"
      }
    ).fetch("data")
    attrs = build.fetch("attributes", {})
    puts "Readiness: build linked id=#{build_id} version=#{attrs["version"]} processingState=#{attrs["processingState"]} expired=#{attrs["expired"]} usesNonExemptEncryption=#{attrs["usesNonExemptEncryption"]}."
  else
    puts "Readiness: no build linked to App Store version."
  end

  begin
    request(:get, "/v1/apps/#{context.fetch(:app_id)}/appPriceSchedule")
    puts "Readiness: app price schedule exists."
  rescue AscError => e
    puts "Readiness: app price schedule missing or unreadable: #{e.message}"
  end

  app = request(
    :get,
    "/v1/apps/#{context.fetch(:app_id)}",
    query: {
      "fields[apps]" => "primaryLocale"
    }
  ).fetch("data")
  primary_locale = app.dig("attributes", "primaryLocale")
  puts "Readiness: app primaryLocale=#{primary_locale || "-"}."

  localizations = app_store_version_localizations(fields: "locale,description,keywords,supportUrl,whatsNew")

  localizations.each do |localization|
    attrs = localization.fetch("attributes", {})
    placements = asc_collection("/v1/appStoreVersionLocalizations/#{localization.fetch('id')}/placements")["data"]
    screenshot_inventory = placements.select { |item| item.dig("attributes", "placementType") == "APP_SCREENSHOT" }
                                     .group_by { |item| item.dig("attributes", "placementGroup") }
                                     .map { |group, items| "#{group}=#{items.length}" }
    puts "Readiness: localization #{attrs["locale"]} primary=#{attrs["locale"] == primary_locale} description=#{!attrs["description"].to_s.empty?} keywords=#{!attrs["keywords"].to_s.empty?} supportUrl=#{!attrs["supportUrl"].to_s.empty?} whatsNew=#{!attrs["whatsNew"].to_s.empty?} screenshotInventory=#{screenshot_inventory.join(",")}."
  end
rescue AscError => e
  puts "Readiness: could not complete readiness dump: #{e.message}"
end

def list_review_submissions(app_id, platform, states: OPEN_REVIEW_SUBMISSION_STATES)
  query = {
    "filter[app]" => app_id,
    "filter[platform]" => platform,
    "limit" => "20",
    "fields[reviewSubmissions]" => "platform,state,submittedDate"
  }
  query["filter[state]"] = states.join(",") if states && !states.empty?

  request(:get, "/v1/reviewSubmissions", query: query).fetch("data", [])
end

def open_review_submissions(app_id, platform)
  submissions = list_review_submissions(app_id, platform)
  submissions = list_review_submissions(app_id, platform, states: nil) if submissions.empty?

  submissions.each do |submission|
    attrs = submission.fetch("attributes", {})
    puts "Review submission candidate #{submission.fetch("id")}: platform=#{attrs["platform"]} state=#{attrs["state"]}."
  end

  submissions.select do |submission|
    attrs = submission.fetch("attributes", {})
    attrs["platform"] == platform && OPEN_REVIEW_SUBMISSION_STATES.include?(attrs["state"])
  end
rescue AscError => e
  puts "Warning: could not list review submissions: #{e.message}"
  []
end

def fetch_review_submission(submission_id)
  request(
    :get,
    "/v1/reviewSubmissions/#{submission_id}",
    query: {
      "fields[reviewSubmissions]" => "platform,state,submittedDate"
    }
  ).fetch("data")
end

def wait_for_review_submission_to_unblock(submission_id)
  12.times do |attempt|
    submission = fetch_review_submission(submission_id)
    state = submission.fetch("attributes", {}).fetch("state", nil)
    puts "Review submission #{submission_id} state after cancel: #{state || "unknown"}."
    return unless BLOCKING_REVIEW_SUBMISSION_STATES.include?(state)

    sleep(10) unless attempt == 11
  end
end

def cancel_review_submission(submission_id)
  request(
    :patch,
    "/v1/reviewSubmissions/#{submission_id}",
    body: {
      data: {
        type: "reviewSubmissions",
        id: submission_id,
        attributes: {
          canceled: true
        }
      }
    }
  )
  puts "Canceled review submission #{submission_id}."
  wait_for_review_submission_to_unblock(submission_id)
rescue AscError => e
  puts "Warning: could not cancel review submission #{submission_id}: #{e.message}"
  raise
end

def list_submission_items(submission_id)
  request(:get, "/v1/reviewSubmissions/#{submission_id}/items").fetch("data", [])
end

def submission_has_app_store_version?(submission_id)
  items = list_submission_items(submission_id)
  items.any? do |item|
    item.dig("relationships", "appStoreVersion", "data", "id") == app_store_version_id
  end
rescue AscError => e
  puts "Warning: could not list items for review submission #{submission_id}: #{e.message}"
  false
end

def add_version_to_submission(submission_id)
  request(
    :post,
    "/v1/reviewSubmissionItems",
    body: {
      data: {
        type: "reviewSubmissionItems",
        relationships: {
          reviewSubmission: {
            data: {
              type: "reviewSubmissions",
              id: submission_id
            }
          },
          appStoreVersion: {
            data: {
              type: "appStoreVersions",
              id: app_store_version_id
            }
          }
        }
      }
    }
  )
  puts "Added App Store version #{app_store_version_id} to review submission #{submission_id}."
rescue AscError => e
  if [409, "409"].include?(e.status)
    puts "Review submission item already exists or cannot be duplicated; continuing."
  else
    raise
  end
end

def create_review_submission(app_id, platform)
  # App Store Connect rejects appStoreVersionForReview on create (409
  # RELATIONSHIP.NOT_ALLOWED); the version is added as a submission item next.
  response = request(
    :post,
    "/v1/reviewSubmissions",
    body: {
      data: {
        type: "reviewSubmissions",
        attributes: {
          platform: platform
        },
        relationships: {
          app: {
            data: {
              type: "apps",
              id: app_id
            }
          }
        }
      }
    }
  )
  id = response.fetch("data").fetch("id")
  puts "Created review submission #{id}."
  id
end

def submit_review_submission(submission_id)
  SUBMISSION_READY_RETRY_COUNT.times do |attempt|
    response = request(
      :patch,
      "/v1/reviewSubmissions/#{submission_id}",
      body: {
        data: {
          type: "reviewSubmissions",
          id: submission_id,
          attributes: {
            submitted: true
          }
        }
      }
    )
    attrs = response.fetch("data").fetch("attributes", {})
    state = attrs["state"]
    puts "Submitted review submission #{submission_id}: state=#{state} submittedDate=#{attrs["submittedDate"] || "-"}."
    return state
  rescue AscError => e
    raise unless retryable_version_not_ready?(e) && attempt < SUBMISSION_READY_RETRY_COUNT - 1

    app_store_version_context("Submission is not ready yet")
    puts "App Store Connect says version is not ready yet; retrying in 30 seconds."
    sleep(30)
  end
end

def prepare_and_submit_existing_submission(submission_id)
  add_version_to_submission(submission_id) unless submission_has_app_store_version?(submission_id)
  submit_review_submission(submission_id)
rescue AscError => e
  if asc_error_code?(e, "ENTITY_ERROR.RELATIONSHIP.REQUIRED")
    puts "Review submission #{submission_id} lacks the required App Store version relationship; canceling it."
    begin
      cancel_review_submission(submission_id)
    rescue AscError
      puts "Review submission #{submission_id} cannot be canceled; skipping it."
    end
    return nil
  end

  raise
end

def create_and_submit_review_submission(app_id, platform)
  6.times do |attempt|
    begin
      submission_id = create_review_submission(app_id, platform)
      add_version_to_submission(submission_id)
      return submit_review_submission(submission_id)
    rescue AscError => e
      if [409, "409"].include?(e.status)
        open_review_submissions(app_id, platform).each do |existing|
          state = prepare_and_submit_existing_submission(existing.fetch("id"))
          return state if state
        end
      end

      raise unless [409, "409"].include?(e.status) && attempt < 5

      puts "Review submission is still blocked by App Store Connect state; retrying."
      sleep(10)
    end
  end
end

def ensure_review_submission_pending!(state)
  return if PENDING_REVIEW_SUBMISSION_STATES.include?(state)

  raise "Review submission did not enter Apple's review queue; final state was #{state || "unknown"}."
end

def submit_app_store_version
  context = app_store_version_context("Before submission")
  # Re-read both metadata and all modern placements immediately before review.
  # Gate failures must never enter the review-submission fallback.
  verify_store_assets!
  dump_readiness(context)
  begin
    state = create_and_submit_review_submission(context.fetch(:app_id), context.fetch(:platform))
  rescue AscError => e
    puts "Fresh review submission path failed; falling back to existing open submissions: #{e.message}"
    state = nil
    open_review_submissions(context.fetch(:app_id), context.fetch(:platform)).each do |existing|
      state = prepare_and_submit_existing_submission(existing.fetch("id"))
      break if state
    end
  end
  ensure_review_submission_pending!(state)
  app_store_version_context("After submission")
end

def configure_and_verify_release_type
  raise "Unsupported release type #{RELEASE_TYPE}" unless RELEASE_TYPE == "AFTER_APPROVAL"

  request(
    :patch,
    "/v1/appStoreVersions/#{app_store_version_id}",
    body: {
      data: {
        type: "appStoreVersions",
        id: app_store_version_id,
        attributes: { releaseType: RELEASE_TYPE }
      }
    }
  )
  version = request(
    :get,
    "/v1/appStoreVersions/#{app_store_version_id}",
    query: { "fields[appStoreVersions]" => "versionString,releaseType" }
  ).fetch("data")
  actual = version.fetch("attributes").fetch("releaseType")
  raise "Release type mismatch: expected #{RELEASE_TYPE}, got #{actual}" unless actual == RELEASE_TYPE

  puts "Verified App Store version #{APP_STORE_VERSION_STRING} releaseType=#{actual}."
end

def verify_previous_version_approved
  previous = ENV["APP_STORE_CONNECT_PREVIOUS_VERSION_STRING"]
  return if previous.to_s.empty?

  versions = request(
    :get,
    "/v1/apps/#{APP_ID}/appStoreVersions",
    query: {
      "filter[versionString]" => previous,
      "filter[platform]" => PLATFORM,
      "fields[appStoreVersions]" => "versionString,platform,appStoreState",
      "limit" => "200"
    }
  ).fetch("data")
  version = versions.find do |item|
    attrs = item.fetch("attributes")
    attrs["versionString"] == previous && attrs["platform"] == PLATFORM
  end
  raise "Previous version #{previous} was not found; release gate remains closed." unless version

  state = version.fetch("attributes").fetch("appStoreState")
  approved_states = %w[READY_FOR_DISTRIBUTION READY_FOR_SALE PENDING_DEVELOPER_RELEASE PENDING_APPLE_RELEASE]
  unless approved_states.include?(state)
    raise "Previous version #{previous} is #{state}; wait for approval before uploading or changing store materials."
  end
  puts "Previous version #{previous} is #{state}; next-release preparation gate passed."
end

def run
  if CLEAN_SCREENSHOT_DUPLICATES
    raise "Legacy screenshot cleanup is disabled. Use the separately approved Asset Library plan; no screenshot deletion is permitted here."
  end
  verify_previous_version_approved
  return if ENV["APP_STORE_CONNECT_CHECK_RELEASE_GATE_ONLY"] == "true"

  verify_store_assets!
  return if ENV["APP_STORE_CONNECT_CHECK_STORE_ASSETS_ONLY"] == "true"

  build = wait_for_valid_build
  build_id = build.fetch("id")
  patch_build_encryption(build_id)
  attach_build_to_version(build_id)
  if SUBMIT_FOR_REVIEW
    configure_and_verify_release_type
    submit_app_store_version
  else
    context = app_store_version_context("After build attachment")
    dump_readiness(context)
    puts "Build #{BUILD_NUMBER} is VALID and attached. Review submission was intentionally skipped."
  end
end

run if $PROGRAM_NAME == __FILE__
