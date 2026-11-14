require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

# Load the real lane helpers without Fastlane credentials or network calls.
module CredentialsManager
  module AppfileConfig
    def self.try_fetch_value(_key); 'TESTTEAM'; end
  end
end
module UI
  def self.user_error!(message); raise message; end
  def self.message(_message); end
  def self.success(_message); end
end
def default_platform(_name); end
def platform(_name); yield; end
def desc(_description); end
def before_all(&block); $before_all = block; end
def lane(_name, &block); end
def after_all(&block); end
def error(&block); end
load File.expand_path('../Fastfile', __dir__)

class PreviewDistributionTest < Minitest::Test
  ROOT = File.expand_path('../../../../..', __dir__)

  def select_app(variant: 'mytonwallet', publish: '', rc: '', **overrides)
    env = {
      'APP_VARIANT' => variant, 'PUBLISH_REPO' => publish, 'IS_RELEASE_CANDIDATE' => rc,
      'IOS_TESTFLIGHT_GROUP' => '', 'IOS_PREVIEW_TESTFLIGHT_GROUP' => '', 'IOS_GRAM_TESTFLIGHT_GROUP' => '',
    }.merge(overrides.transform_keys(&:to_s))
    output, error, status = Open3.capture3(env, 'bash', File.join(ROOT, 'deploy/configure_ios_variant.sh'))
    assert status.success?, error
    output.lines.to_h { |line| line.strip.split('=', 2) }
  end

  def test_development_builds_use_preview_and_its_extensions
    config = select_app
    assert_equal 'preview', config['IOS_BUILD_CHANNEL']
    assert_equal 'MyTonWallet_Preview', config['IOS_SCHEME']
    assert_equal 'org.mytonwallet.app.preview', config['IOS_APP_IDENTIFIER']
    assert_equal 'org.mytonwallet.app.preview.AirWidget', config['IOS_APP_IDENTIFIER_WIDGET']
    assert_equal 'org.mytonwallet.app.preview.notification-service', config['IOS_APP_IDENTIFIER_NOTIFICATION']
    assert_equal 'AirWidgetExtension_Preview', config['IOS_WIDGET_SCHEME']
    assert_equal 'MyTonWalletNotificationServiceExtension_Preview', config['IOS_NOTIFICATION_SCHEME']
  end

  def test_rc_and_publishing_repository_keep_main_app
    [{ rc: '1' }, { publish: 'mytonwallet-org/mytonwallet' }, { publish: 'mytonwallet-org/mytonwallet', rc: '1' }].each do |options|
      config = select_app(**options)
      assert_equal 'main', config['IOS_BUILD_CHANNEL']
      assert_equal 'MyTonWallet', config['IOS_SCHEME']
      assert_equal 'org.mytonwallet.app', config['IOS_APP_IDENTIFIER']
      assert_equal 'org.mytonwallet.app.AirWidget', config['IOS_APP_IDENTIFIER_WIDGET']
      assert_equal 'org.mytonwallet.app.notification-service', config['IOS_APP_IDENTIFIER_NOTIFICATION']
    end
  end

  def test_gram_keeps_its_identity_in_every_channel
    ['', 'mytonwallet-org/mytonwallet'].product(['', '1']).each do |publish, rc|
      config = select_app(variant: 'gram', publish: publish, rc: rc)
      assert_equal 'gram', config['IOS_BUILD_CHANNEL']
      assert_equal 'GramWallet', config['IOS_SCHEME']
      assert_equal 'io.gramwallet.app', config['IOS_APP_IDENTIFIER']
    end
  end

  def test_preview_does_not_inherit_the_main_apps_tester_group
    config = select_app(IOS_TESTFLIGHT_GROUP: 'Main testers')
    assert_equal 'My Wallet Beta external group', config['IOS_TESTFLIGHT_GROUP']
    config = select_app(IOS_TESTFLIGHT_GROUP: 'Main testers', IOS_PREVIEW_TESTFLIGHT_GROUP: 'Beta testers')
    assert_equal 'Beta testers', config['IOS_TESTFLIGHT_GROUP']
    assert_equal 'Main testers', select_app(rc: '1', IOS_TESTFLIGHT_GROUP: 'Main testers')['IOS_TESTFLIGHT_GROUP']
  end

  def test_unknown_variant_fails_instead_of_uploading_another_app
    _, _, status = Open3.capture3({ 'APP_VARIANT' => 'unknown' }, 'bash', File.join(ROOT, 'deploy/configure_ios_variant.sh'))
    refute status.success?
  end

  def test_preview_cannot_enter_the_app_store_release_lane
    $app_identifier = 'org.mytonwallet.app.preview'
    assert_match(/Preview is distributed through TestFlight/, assert_raises(RuntimeError) { $before_all.call(:release) }.message)
  end

  def test_handoff_keeps_uploaded_app_build_and_group_and_rejects_wrong_destination
    Dir.mktmpdir do |dir|
      $handoff_path = File.join(dir, 'handoff.json')
      $app_identifier = 'org.mytonwallet.app.preview'
      $testflight_group = 'Beta testers'
      write_distribution_handoff('26.10.1', 5001, 'Build notes')
      $testflight_group = 'Changed after upload'
      assert_equal ['26.10.1', '5001', 'Build notes'], read_distribution_handoff
      assert_equal 'Beta testers', $testflight_group
      $app_identifier = 'org.mytonwallet.app'
      assert_match(/does not match the uploaded app/, assert_raises(RuntimeError) { read_distribution_handoff }.message)
    end
  end

  def test_preview_widget_api_is_required_and_shell_escaped
    saved = ENV.to_h
    ENV['IOS_BUILD_CHANNEL'] = 'preview'
    ENV.delete('BRILLIANT_API_BASE_URL')
    assert_raises(RuntimeError) { archive_xcargs }
    ENV['BRILLIANT_API_BASE_URL'] = 'https://api-beta.example/path?one=1&two=2'
    assert_equal ['-skipMacroValidation', 'WIDGET_API_BASE_URL=https://api-beta.example/path?one=1&two=2'], Shellwords.split(archive_xcargs)
    ENV['IOS_BUILD_CHANNEL'] = 'main'
    assert_equal '-skipMacroValidation', archive_xcargs
  ensure
    ENV.replace(saved)
  end

  def test_upload_from_linux_only_when_flag_is_true
    { nil => false, '' => false, 'false' => false, 'TRUE' => false, 'true' => true }.each do |value, expected|
      ENV['IOS_UPLOAD_ON_LINUX'] = value
      assert_equal expected, upload_from_linux?, value.inspect
    end
  ensure
    ENV.delete('IOS_UPLOAD_ON_LINUX')
  end

  def test_linux_lanes_skip_the_signing_setup
    assert builds_an_archive?(:beta)
    assert builds_an_archive?(:release)
    refute builds_an_archive?(:distribute)
    refute builds_an_archive?(:upload_ipa)
  end
end
