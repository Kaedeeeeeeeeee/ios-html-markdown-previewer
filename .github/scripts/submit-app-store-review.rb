#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
APP_ID = ENV.fetch("APP_STORE_CONNECT_APP_ID")
CONFIGURED_APP_STORE_VERSION_ID = ENV["APP_STORE_CONNECT_VERSION_ID"]
APP_STORE_VERSION_STRING = ENV.fetch("APP_STORE_CONNECT_VERSION_STRING")
BUILD_NUMBER = ENV.fetch("APP_STORE_CONNECT_BUILD_NUMBER")
PLATFORM = ENV.fetch("APP_STORE_CONNECT_PLATFORM", "IOS")
KEY_ID = ENV.fetch("ASC_API_KEY_ID")
ISSUER_ID = ENV.fetch("ASC_API_ISSUER_ID")
KEY_PATH = ENV.fetch("ASC_API_KEY_PATH")
SUBMISSION_READY_RETRY_COUNT = Integer(ENV.fetch("APP_STORE_CONNECT_SUBMIT_RETRIES", "4"))
CLEAN_SCREENSHOT_DUPLICATES = ENV.fetch("APP_STORE_CONNECT_CLEAN_SCREENSHOT_DUPLICATES", "false") == "true"
SUBMIT_FOR_REVIEW = ENV.fetch("APP_STORE_CONNECT_SUBMIT_FOR_REVIEW", "false") == "true"
EXPECTED_SCREENSHOTS = {
  "APP_IPHONE_67" => %w[
    iphone-01-home.png
    iphone-02-html-safe-preview.png
    iphone-03-markdown-preview.png
    iphone-04-zip-report-preview.png
    iphone-05-settings.png
  ],
  "APP_IPAD_PRO_3GEN_129" => %w[
    ipad-01-home.png
    ipad-02-html-safe-preview.png
    ipad-03-markdown-preview.png
    ipad-04-zip-report-preview.png
    ipad-05-settings.png
  ]
}.freeze
EXPECTED_SCREENSHOT_LOCALES = %w[en-US zh-Hans ja].freeze
DEFAULT_WHATS_NEW = ENV.fetch(
  "APP_STORE_CONNECT_WHATS_NEW",
  "Adds richer built-in HTML and ZIP samples with refreshed App Store visuals."
)

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
  key = OpenSSL::PKey.read(File.read(KEY_PATH))
  now = Time.now.to_i
  header = { alg: "ES256", kid: KEY_ID, typ: "JWT" }
  payload = { iss: ISSUER_ID, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" }
  signing_input = [base64url(JSON.generate(header)), base64url(JSON.generate(payload))].join(".")
  signature = raw_ecdsa_signature(key.sign(OpenSSL::Digest.new("SHA256"), signing_input))
  [signing_input, base64url(signature)].join(".")
end

def request(method, path, query: nil, body: nil)
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

def screenshot_sets(localization_id)
  request(
    :get,
    "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets",
    query: {
      "limit" => "50",
      "fields[appScreenshotSets]" => "screenshotDisplayType"
    }
  ).fetch("data", [])
end

def screenshots_in_set(set_id)
  request(
    :get,
    "/v1/appScreenshotSets/#{set_id}/appScreenshots",
    query: {
      "limit" => "50",
      "fields[appScreenshots]" => "fileName,sourceFileChecksum,assetDeliveryState"
    }
  ).fetch("data", [])
end

def screenshot_identity(screenshot)
  attributes = screenshot.fetch("attributes", {})
  [attributes["fileName"].to_s, attributes["sourceFileChecksum"].to_s]
end

def duplicate_screenshots(screenshots)
  screenshots.group_by { |screenshot| screenshot_identity(screenshot) }
             .values
             .flat_map { |matching| matching.drop(1) }
end

def expected_screenshot_sets
  localizations = app_store_version_localizations
  by_locale = localizations.to_h do |localization|
    [localization.fetch("attributes", {}).fetch("locale"), localization]
  end

  EXPECTED_SCREENSHOT_LOCALES.to_h do |locale|
    localization = by_locale[locale]
    raise "Missing App Store version localization #{locale}." unless localization

    sets = screenshot_sets(localization.fetch("id"))
    by_display_type = sets.group_by do |set|
      set.fetch("attributes", {}).fetch("screenshotDisplayType")
    end
    selected = EXPECTED_SCREENSHOTS.to_h do |display_type, expected_files|
      matches = by_display_type.fetch(display_type, [])
      raise "Expected one #{locale} #{display_type} screenshot set, found #{matches.length}." unless matches.length == 1

      [display_type, { set: matches.first, expected_files: expected_files }]
    end
    [locale, selected]
  end
end

def verify_expected_screenshot_inventory!
  expected_screenshot_sets.each do |locale, sets|
    sets.each do |display_type, details|
      screenshots = screenshots_in_set(details.fetch(:set).fetch("id"))
      actual_files = screenshots.map { |screenshot| screenshot.fetch("attributes", {})["fileName"].to_s }
      expected_files = details.fetch(:expected_files)
      unless actual_files == expected_files
        raise "Unexpected #{locale} #{display_type} screenshots: expected #{expected_files.inspect}, found #{actual_files.inspect}."
      end

      puts "Screenshot inventory verified: locale=#{locale} displayType=#{display_type} count=#{actual_files.length} files=#{actual_files.join(",")}."
    end
  end
end

def clean_duplicate_screenshots!
  context = app_store_version_context("Before screenshot cleanup")
  unless context.fetch(:app_store_state) == "PREPARE_FOR_SUBMISSION"
    raise "Cannot clean screenshots while App Store version state is #{context.fetch(:app_store_state)}."
  end

  deleted = 0
  expected_screenshot_sets.each do |locale, sets|
    sets.each do |display_type, details|
      set_id = details.fetch(:set).fetch("id")
      screenshots = screenshots_in_set(set_id)
      duplicates = duplicate_screenshots(screenshots)
      duplicates.each do |screenshot|
        attributes = screenshot.fetch("attributes", {})
        request(:delete, "/v1/appScreenshots/#{screenshot.fetch("id")}")
        deleted += 1
        puts "Deleted duplicate screenshot: locale=#{locale} displayType=#{display_type} file=#{attributes["fileName"]} id=#{screenshot.fetch("id")}."
      end
    end
  end

  10.times do |attempt|
    begin
      verify_expected_screenshot_inventory!
      puts "Screenshot cleanup completed: deleted=#{deleted}."
      return
    rescue RuntimeError => e
      raise if attempt == 9

      puts "Screenshot inventory has not converged yet: #{e.message} Retrying in 3 seconds."
      sleep(3)
    end
  end
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
    sets = screenshot_sets(localization.fetch("id"))
    screenshot_inventory = sets.map do |set|
      display_type = set.fetch("attributes", {})["screenshotDisplayType"]
      count = screenshots_in_set(set.fetch("id")).length
      "#{display_type}=#{count}"
    end
    puts "Readiness: localization #{attrs["locale"]} primary=#{attrs["locale"] == primary_locale} description=#{!attrs["description"].to_s.empty?} keywords=#{!attrs["keywords"].to_s.empty?} supportUrl=#{!attrs["supportUrl"].to_s.empty?} whatsNew=#{!attrs["whatsNew"].to_s.empty?} screenshotInventory=#{screenshot_inventory.join(",")}."
  end
rescue AscError => e
  puts "Readiness: could not complete readiness dump: #{e.message}"
end

def ensure_whats_new
  localizations = request(
    :get,
    "/v1/appStoreVersions/#{app_store_version_id}/appStoreVersionLocalizations",
    query: {
      "limit" => "50",
      "fields[appStoreVersionLocalizations]" => "locale,whatsNew"
    }
  ).fetch("data", [])

  localizations.each do |localization|
    attrs = localization.fetch("attributes", {})
    next unless attrs["whatsNew"].to_s.empty?

    request(
      :patch,
      "/v1/appStoreVersionLocalizations/#{localization.fetch("id")}",
      body: {
        data: {
          type: "appStoreVersionLocalizations",
          id: localization.fetch("id"),
          attributes: {
            whatsNew: DEFAULT_WHATS_NEW
          }
        }
      }
    )
    puts "Updated missing What's New for #{attrs["locale"]}."
  end
rescue AscError => e
  puts "Warning: could not update missing What's New text: #{e.message}"
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
          },
          appStoreVersionForReview: {
            data: {
              type: "appStoreVersions",
              id: app_store_version_id
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
  ensure_whats_new
  context = app_store_version_context("After metadata normalization")
  dump_readiness(context)
  verify_expected_screenshot_inventory!
  state = create_and_submit_review_submission(context.fetch(:app_id), context.fetch(:platform))
  ensure_review_submission_pending!(state)
  app_store_version_context("After submission")
rescue AscError => e
  puts "Fresh review submission path failed; falling back to existing open submissions: #{e.message}"
  state = nil
  open_review_submissions(context.fetch(:app_id), context.fetch(:platform)).each do |existing|
    state = prepare_and_submit_existing_submission(existing.fetch("id"))
    break if state
  end
  ensure_review_submission_pending!(state)
  app_store_version_context("After submission")
end

def run
  build = wait_for_valid_build
  build_id = build.fetch("id")
  patch_build_encryption(build_id)
  attach_build_to_version(build_id)
  if CLEAN_SCREENSHOT_DUPLICATES
    clean_duplicate_screenshots!
  end
  if SUBMIT_FOR_REVIEW
    submit_app_store_version
  else
    context = app_store_version_context("After build attachment")
    dump_readiness(context)
    puts "Build #{BUILD_NUMBER} is VALID and attached. Review submission was intentionally skipped."
  end
end

run if $PROGRAM_NAME == __FILE__
