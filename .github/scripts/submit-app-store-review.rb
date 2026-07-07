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
APP_STORE_VERSION_ID = ENV.fetch("APP_STORE_CONNECT_VERSION_ID")
BUILD_NUMBER = ENV.fetch("APP_STORE_CONNECT_BUILD_NUMBER")
PLATFORM = ENV.fetch("APP_STORE_CONNECT_PLATFORM", "IOS")
KEY_ID = ENV.fetch("ASC_API_KEY_ID")
ISSUER_ID = ENV.fetch("ASC_API_ISSUER_ID")
KEY_PATH = ENV.fetch("ASC_API_KEY_PATH")

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
    "/v1/appStoreVersions/#{APP_STORE_VERSION_ID}/relationships/build",
    body: {
      data: {
        type: "builds",
        id: build_id
      }
    }
  )
  puts "Attached build #{build_id} to App Store version #{APP_STORE_VERSION_ID}."
end

SUBMITTED_APP_STORE_STATES = %w[
  WAITING_FOR_REVIEW
  IN_REVIEW
  WAITING_FOR_EXPORT_COMPLIANCE
  PENDING_DEVELOPER_RELEASE
  PENDING_APPLE_RELEASE
  PROCESSING_FOR_APP_STORE
  READY_FOR_SALE
  READY_FOR_DISTRIBUTION
].freeze

def fetch_app_store_version
  request(
    :get,
    "/v1/appStoreVersions/#{APP_STORE_VERSION_ID}",
    query: {
      "fields[appStoreVersions]" => "versionString,appStoreState,platform"
    }
  ).fetch("data")
end

def app_store_version_state(label)
  version = fetch_app_store_version
  attrs = version.fetch("attributes", {})
  state = attrs.fetch("appStoreState")
  puts "#{label}: App Store version #{attrs["versionString"]} platform=#{attrs["platform"]} appStoreState=#{state}."
  state
end

def submitted_app_store_state?(state)
  SUBMITTED_APP_STORE_STATES.include?(state)
end

def create_app_store_version_submission
  response = request(
    :post,
    "/v1/appStoreVersionSubmissions",
    body: {
      data: {
        type: "appStoreVersionSubmissions",
        relationships: {
          appStoreVersion: {
            data: {
              type: "appStoreVersions",
              id: APP_STORE_VERSION_ID
            }
          }
        }
      }
    }
  )
  id = response.fetch("data").fetch("id")
  puts "Created App Store version submission #{id}."
end

def wait_for_submitted_app_store_state
  12.times do |attempt|
    state = app_store_version_state(attempt.zero? ? "After submission" : "Rechecking submission state")
    return state if submitted_app_store_state?(state)

    sleep(10)
  end

  raise "App Store version #{APP_STORE_VERSION_ID} did not enter the review queue."
end

def submit_app_store_version
  state = app_store_version_state("Before submission")
  if submitted_app_store_state?(state)
    puts "App Store version #{APP_STORE_VERSION_ID} is already submitted; continuing."
    return
  end

  create_app_store_version_submission
  wait_for_submitted_app_store_state
rescue AscError => e
  state = app_store_version_state("After submission error")
  if submitted_app_store_state?(state)
    puts "App Store version #{APP_STORE_VERSION_ID} is already submitted after API status #{e.status}; continuing."
  else
    raise
  end
end

build = wait_for_valid_build
build_id = build.fetch("id")
patch_build_encryption(build_id)
attach_build_to_version(build_id)
submit_app_store_version
