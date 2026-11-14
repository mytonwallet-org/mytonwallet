require 'json'
require 'minitest/autorun'
require 'socket'
require 'tmpdir'
require 'uri'
require_relative '../build_upload'

class BuildUploadTest < Minitest::Test
  Call = Struct.new(:method, :url, :headers, :body)

  class FakeTransport
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def call(method, url, headers, body)
      @calls << Call.new(method, url, headers, body)
      response = @responses.shift or raise "unexpected #{method} #{url}"
      raise response if response.is_a?(Exception)

      status, payload = response
      [status, payload.is_a?(String) ? payload : JSON.generate(payload)]
    end
  end

  NO_UPLOADS = [200, { data: [], links: { self: 'x' }, meta: { paging: { total: 0, limit: 1 } } }].freeze
  UPLOAD_CREATED = [201, {
    data: { type: 'buildUploads', id: 'u1', attributes: {
      cfBundleShortVersionString: '1.2.3', cfBundleVersion: '456', platform: 'IOS',
      state: { state: 'AWAITING_UPLOAD', errors: [], warnings: [], infos: [] },
    } },
  }].freeze
  COMMITTED = [200, { data: { type: 'buildUploadFiles', id: 'f1', attributes: { assetDeliveryState: { state: 'UPLOAD_COMPLETE' } } } }].freeze
  PUT_OK = [200, ''].freeze

  def setup
    @dir = Dir.mktmpdir
    @ipa = File.join(@dir, 'App.ipa')
    File.binwrite(@ipa, 'abcdefghij')
    @slept = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def operation(offset, length, url: "https://presigned.example/part-#{offset}", headers: { 'Content-Type' => 'application/octet-stream' })
    {
      method: 'PUT', url: url, offset: offset, length: length, partNumber: offset.zero? ? 1 : 2,
      expiration: '2026-11-13T12:00:00Z', requestHeaders: headers.map { |name, value| { name: name, value: value } },
    }
  end

  def file_created(operations)
    [201, { data: { type: 'buildUploadFiles', id: 'f1', attributes: {
      fileName: 'App.ipa', fileSize: 10, uti: 'com.apple.ipa', assetType: 'ASSET', uploadOperations: operations,
    } } }]
  end

  def state(name, errors: [])
    [200, { data: { type: 'buildUploads', id: 'u1', attributes: {
      cfBundleShortVersionString: '1.2.3', cfBundleVersion: '456', platform: 'IOS',
      state: { state: name, errors: errors, warnings: [], infos: [] },
    } } }]
  end

  def upload(responses, **overrides)
    @fake = FakeTransport.new(responses)
    AppStoreBuildUpload.upload(
      ipa_path: @ipa, app_id: '123', version: '1.2.3', build_number: '456', token: 'tok',
      transport: @fake, sleeper: ->(seconds) { @slept << seconds }, poll_interval: 10, timeout: 30, **overrides
    )
  end

  def puts_sent
    @fake.calls.select { |call| call.method == 'PUT' }
  end

  def test_happy_path_calls_in_order
    result = upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, state('COMPLETE')])

    assert_equal 'COMPLETE', result
    expected = [
      ['GET', %r{\Ahttps://api\.appstoreconnect\.apple\.com/v1/apps/123/buildUploads\?}],
      ['POST', %r{\Ahttps://api\.appstoreconnect\.apple\.com/v1/buildUploads\z}],
      ['POST', %r{\Ahttps://api\.appstoreconnect\.apple\.com/v1/buildUploadFiles\z}],
      ['PUT', %r{\Ahttps://presigned\.example/part-0\z}],
      ['PATCH', %r{\Ahttps://api\.appstoreconnect\.apple\.com/v1/buildUploadFiles/f1\z}],
      ['GET', %r{\Ahttps://api\.appstoreconnect\.apple\.com/v1/buildUploads/u1\z}],
    ]
    assert_equal expected.size, @fake.calls.size
    expected.zip(@fake.calls).each do |(method, url), call|
      assert_equal method, call.method
      assert_match url, call.url
    end
    @fake.calls.reject { |call| call.method == 'PUT' }.each do |call|
      assert_equal 'Bearer tok', call.headers['Authorization'], call.url
    end
    refute puts_sent.first.headers.key?('Authorization')
  end

  def test_api_requests_ask_for_a_fresh_token_each_time
    issued = 0
    upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, state('COMPLETE')],
           token: -> { "t#{issued += 1}" })

    assert_equal ['Bearer t1', 'Bearer t2', 'Bearer t3', nil, 'Bearer t4', 'Bearer t5'],
                 @fake.calls.map { |call| call.headers['Authorization'] }
  end

  def test_requests_carry_build_identity
    upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, state('COMPLETE')])

    query = URI.decode_www_form(URI(@fake.calls[0].url).query).to_h
    assert_equal({ 'filter[cfBundleShortVersionString]' => '1.2.3', 'filter[cfBundleVersion]' => '456',
                   'filter[state]' => 'AWAITING_UPLOAD,PROCESSING,COMPLETE,FAILED', 'limit' => '10' }, query)
    assert_equal({ 'data' => { 'type' => 'buildUploads',
                               'attributes' => { 'cfBundleShortVersionString' => '1.2.3', 'cfBundleVersion' => '456', 'platform' => 'IOS' },
                               'relationships' => { 'app' => { 'data' => { 'type' => 'apps', 'id' => '123' } } } } },
                 JSON.parse(@fake.calls[1].body))
    assert_equal({ 'data' => { 'type' => 'buildUploadFiles',
                               'attributes' => { 'fileName' => 'App.ipa', 'fileSize' => 10, 'uti' => 'com.apple.ipa', 'assetType' => 'ASSET' },
                               'relationships' => { 'buildUpload' => { 'data' => { 'type' => 'buildUploads', 'id' => 'u1' } } } } },
                 JSON.parse(@fake.calls[2].body))
    assert_equal({ 'data' => { 'type' => 'buildUploadFiles', 'id' => 'f1', 'attributes' => { 'uploaded' => true } } },
                 JSON.parse(@fake.calls[4].body))
  end

  def test_skips_when_upload_already_exists
    existing = [200, { data: [{ type: 'buildUploads', id: 'u0', attributes: {
      cfBundleShortVersionString: '1.2.3', cfBundleVersion: '456', platform: 'IOS',
      state: { state: 'COMPLETE', errors: [], warnings: [], infos: [] },
    } }] }]

    assert_equal 'SKIPPED', upload([existing])
    assert_equal ['GET'], @fake.calls.map(&:method)
  end

  def test_skips_without_the_ipa_when_upload_already_exists
    existing = [200, { data: [{ type: 'buildUploads', id: 'u0', attributes: { state: { state: 'PROCESSING', errors: [] } } }] }]
    File.delete(@ipa)

    assert_equal 'SKIPPED', upload([existing])
  end

  def test_refuses_a_missing_ipa_before_creating_an_upload
    File.delete(@ipa)

    error = assert_raises(AppStoreBuildUpload::Error) { upload([NO_UPLOADS, UPLOAD_CREATED]) }
    assert_includes error.message, @ipa
    assert_equal ['GET'], @fake.calls.map(&:method)
  end

  def test_puts_exact_byte_ranges
    operations = [operation(0, 6, headers: { 'Content-Type' => 'application/octet-stream', 'x-part' => 'one' }),
                  operation(6, 4, headers: { 'Content-Type' => 'application/octet-stream', 'x-part' => 'two' })]
    upload([NO_UPLOADS, UPLOAD_CREATED, file_created(operations), PUT_OK, PUT_OK, COMMITTED, state('COMPLETE')])

    assert_equal %w[abcdef ghij], puts_sent.map(&:body)
    assert_equal %w[https://presigned.example/part-0 https://presigned.example/part-6], puts_sent.map(&:url)
    assert_equal [{ 'Content-Type' => 'application/octet-stream', 'x-part' => 'one' },
                  { 'Content-Type' => 'application/octet-stream', 'x-part' => 'two' }], puts_sent.map(&:headers)
  end

  def test_raises_with_apple_errors_on_failed
    failed = state('FAILED', errors: [{ code: 'X', description: 'bad' }])

    error = assert_raises(AppStoreBuildUpload::Error) do
      upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, failed])
    end
    assert_includes error.message, 'bad'
    assert_includes error.message, 'X'
  end

  def test_raises_on_api_error_status
    conflict = [409, { errors: [{ status: '409', code: 'ENTITY_ERROR', detail: 'duplicate build' }] }]

    error = assert_raises(AppStoreBuildUpload::Error) { upload([NO_UPLOADS, conflict]) }
    assert_includes error.message, '409'
    assert_includes error.message, 'duplicate build'
  end

  def test_retries_transient_put_failures
    result = upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]),
                     [429, ''], Errno::ECONNRESET.new, PUT_OK, COMMITTED, state('COMPLETE')])

    assert_equal 'COMPLETE', result
    assert_equal 3, puts_sent.size
    assert_equal [2, 4], @slept
  end

  def test_gives_up_after_three_put_failures
    error = assert_raises(AppStoreBuildUpload::Error) do
      upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), [503, ''], [503, ''], [503, ''], COMMITTED])
    end
    assert_equal 3, puts_sent.size
    assert_includes error.message, 'part 1'
    assert_includes error.message, '503'
  end

  def test_does_not_retry_expired_url
    error = assert_raises(AppStoreBuildUpload::Error) do
      upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), [403, ''], PUT_OK, COMMITTED])
    end
    assert_equal 1, puts_sent.size
    assert_includes error.message, 'expired'
  end

  def test_refuses_to_reupload_a_build_apple_rejected
    rejected = [200, { data: [{ type: 'buildUploads', id: 'u0', attributes: {
      cfBundleShortVersionString: '1.2.3', cfBundleVersion: '456', platform: 'IOS',
      state: { state: 'FAILED', errors: [{ code: 'ITMS-90000', description: 'invalid binary' }], warnings: [], infos: [] },
    } }] }]

    error = assert_raises(AppStoreBuildUpload::Error) { upload([rejected]) }
    assert_includes error.message, 'invalid binary'
    assert_equal ['GET'], @fake.calls.map(&:method)
  end

  def test_deletes_a_stale_awaiting_upload_before_creating_one
    stale = [200, { data: [{ type: 'buildUploads', id: 'u0', attributes: {
      cfBundleShortVersionString: '1.2.3', cfBundleVersion: '456', platform: 'IOS',
      state: { state: 'AWAITING_UPLOAD', errors: [], warnings: [], infos: [] },
    } }] }]

    result = upload([stale, [204, ''], UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, state('COMPLETE')])

    assert_equal 'COMPLETE', result
    assert_equal %w[GET DELETE POST], @fake.calls.first(3).map(&:method)
    assert_match %r{/v1/buildUploads/u0\z}, @fake.calls[1].url
  end

  def test_waits_through_processing_until_complete
    result = upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED,
                     state('PROCESSING'), state('PROCESSING'), state('COMPLETE')])

    assert_equal 'COMPLETE', result
    assert_equal [10, 10], @slept
  end

  def test_raises_when_processing_turns_failed
    error = assert_raises(AppStoreBuildUpload::Error) do
      upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED,
              state('PROCESSING'), state('FAILED', errors: [{ code: 'ITMS-90000', description: 'invalid binary' }])])
    end
    assert_includes error.message, 'invalid binary'
  end

  def test_hands_over_while_apple_is_still_processing_at_timeout
    processing = Array.new(10) { state('PROCESSING') }

    assert_equal 'PROCESSING', upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, *processing])
    assert_equal 30, @slept.sum
  end

  def test_times_out_when_state_stays_awaiting
    awaiting = Array.new(10) { state('AWAITING_UPLOAD') }

    error = assert_raises(AppStoreBuildUpload::Error) do
      upload([NO_UPLOADS, UPLOAD_CREATED, file_created([operation(0, 10)]), PUT_OK, COMMITTED, *awaiting])
    end
    assert_includes error.message, 'AWAITING_UPLOAD'
    assert_equal 30, @slept.sum
  end

  def test_net_http_transport_sends_method_headers_and_body_and_does_not_follow_redirects
    server = TCPServer.new('127.0.0.1', 0)
    received = Thread.new do
      client = server.accept
      head = +''
      head << client.gets until head.end_with?("\r\n\r\n")
      length = head[/^content-length: (\d+)/i, 1].to_i
      body = client.read(length)
      client.write("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/elsewhere\r\nContent-Length: 2\r\nConnection: close\r\n\r\nno")
      client.close
      [head, body]
    end

    status, body = AppStoreBuildUpload::NetHttpTransport.new.call(
      'PUT', "http://127.0.0.1:#{server.addr[1]}/part?sig=1", { 'x-amz-meta' => 'v' }, 'abcdef'
    )
    head, sent = received.value

    assert_equal [302, 'no'], [status, body]
    assert_match %r{\APUT /part\?sig=1 HTTP/1\.1\r\n}, head
    assert_match(/^x-amz-meta: v\r$/i, head)
    refute_match(/^authorization:/i, head)
    assert_equal 'abcdef', sent
  ensure
    server&.close
  end
end
