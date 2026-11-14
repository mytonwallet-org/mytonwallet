require 'json'
require 'net/http'
require 'openssl'
require 'uri'

module AppStoreBuildUpload
  API_BASE = 'https://api.appstoreconnect.apple.com'.freeze
  PUT_ATTEMPTS = 3
  NETWORK_ERRORS = [IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError].freeze

  class Error < StandardError; end

  class NetHttpTransport
    def call(method, url, headers, body)
      uri = URI(url)
      request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri.request_uri, headers)
      if body
        request['Content-Type'] ||= 'application/octet-stream'
        request.body = body
      end
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                          open_timeout: 30, read_timeout: 120, write_timeout: 120) do |http|
        response = http.request(request)
        [response.code.to_i, response.body.to_s]
      end
    end
  end

  class Api
    def initialize(transport, token)
      @transport = transport
      @token = token
    end

    def request(method, path, payload = nil)
      token = @token.respond_to?(:call) ? @token.call : @token
      headers = { 'Authorization' => "Bearer #{token}" }
      headers['Content-Type'] = 'application/json' if payload
      status, body = @transport.call(method, "#{API_BASE}#{path}", headers, payload && JSON.generate(payload))
      raise Error, "#{method} #{path.split('?').first}: HTTP #{status} #{body}" unless status.between?(200, 299)

      body.to_s.empty? ? {} : JSON.parse(body)
    end
  end

  def self.upload(ipa_path:, app_id:, version:, build_number:, token:, transport: NetHttpTransport.new,
                  sleeper: ->(seconds) { sleep(seconds) }, poll_interval: 10, timeout: 900)
    api = Api.new(transport, token)
    existing = existing_uploads(api, app_id, version, build_number).group_by { |record| record.dig('attributes', 'state', 'state') }
    return 'SKIPPED' if existing.key?('PROCESSING') || existing.key?('COMPLETE')
    raise Error, rejection_message(existing['FAILED'].first.dig('attributes', 'state')) if existing.key?('FAILED')
    raise Error, "No ipa at #{ipa_path}, and App Store Connect has no upload of #{version} (#{build_number})" unless File.file?(ipa_path)

    existing.fetch('AWAITING_UPLOAD', []).each { |stale| api.request('DELETE', "/v1/buildUploads/#{stale['id']}") }

    upload_id = api.request('POST', '/v1/buildUploads', { data: {
      type: 'buildUploads',
      attributes: { cfBundleShortVersionString: version, cfBundleVersion: build_number, platform: 'IOS' },
      relationships: { app: { data: { type: 'apps', id: app_id } } },
    } }).dig('data', 'id')
    file = api.request('POST', '/v1/buildUploadFiles', { data: {
      type: 'buildUploadFiles',
      attributes: { fileName: File.basename(ipa_path), fileSize: File.size(ipa_path), uti: 'com.apple.ipa', assetType: 'ASSET' },
      relationships: { buildUpload: { data: { type: 'buildUploads', id: upload_id } } },
    } })['data']
    file.dig('attributes', 'uploadOperations').each_with_index do |operation, index|
      put_part(transport, ipa_path, operation, operation['partNumber'] || index + 1, sleeper)
    end
    api.request('PATCH', "/v1/buildUploadFiles/#{file['id']}",
                { data: { type: 'buildUploadFiles', id: file['id'], attributes: { uploaded: true } } })
    wait_for_state(api, upload_id, sleeper, poll_interval, timeout)
  end

  def self.existing_uploads(api, app_id, version, build_number)
    query = URI.encode_www_form(
      'filter[cfBundleShortVersionString]' => version, 'filter[cfBundleVersion]' => build_number,
      'filter[state]' => 'AWAITING_UPLOAD,PROCESSING,COMPLETE,FAILED', 'limit' => 10
    )
    api.request('GET', "/v1/apps/#{app_id}/buildUploads?#{query}").fetch('data')
  end

  def self.put_part(transport, ipa_path, operation, part, sleeper)
    body = File.open(ipa_path, 'rb') { |file| file.seek(operation['offset']); file.read(operation['length']) }
    headers = operation.fetch('requestHeaders', []).to_h { |header| [header['name'], header['value']] }
    last_failure = nil
    PUT_ATTEMPTS.times do |attempt|
      sleeper.call(2**attempt) if attempt.positive?
      begin
        status, = transport.call(operation['method'], operation['url'], headers, body)
      rescue *NETWORK_ERRORS => e
        last_failure = "#{e.class}: #{e.message}"
        next
      end
      return if status.between?(200, 299)
      raise Error, "upload part #{part}: presigned URL expired (HTTP 403)" if status == 403
      raise Error, "upload part #{part}: HTTP #{status}" unless status >= 500 || status == 429

      last_failure = "HTTP #{status}"
    end
    raise Error, "upload part #{part} failed after #{PUT_ATTEMPTS} attempts: #{last_failure}"
  end

  def self.rejection_message(state)
    details = state.fetch('errors', []).map { |error| "#{error['code']}: #{error['description']}" }
    "App Store Connect rejected the upload: #{details.join('; ')}"
  end

  def self.wait_for_state(api, upload_id, sleeper, poll_interval, timeout)
    waited = 0
    loop do
      state = api.request('GET', "/v1/buildUploads/#{upload_id}").dig('data', 'attributes', 'state') || {}
      case state['state']
      when 'COMPLETE'
        return 'COMPLETE'
      when 'FAILED'
        raise Error, rejection_message(state)
      end
      if waited >= timeout
        # Apple already holds the binary; the distribute lane keeps waiting for processing itself.
        return 'PROCESSING' if state['state'] == 'PROCESSING'

        raise Error, "upload stayed #{state['state']} for #{timeout} s"
      end

      sleeper.call(poll_interval)
      waited += poll_interval
    end
  end
end
