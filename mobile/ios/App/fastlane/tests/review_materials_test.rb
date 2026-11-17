require 'minitest/autorun'
require 'tmpdir'

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
def before_all(&block); end
def lane(_name, &block); end
def after_all(&block); end
def error(&block); end
load File.expand_path('../Fastfile', __dir__)

class ReviewMaterialsTest < Minitest::Test
  TEST_WALLET = "Test seed phrase on balance:\n\nalpha beta gamma\n\n----\n\nExplore section catalog index\n"
  APPENDIX = "SWAP AND BUY FEATURES\n\nThe user signs each swap on their device.\n"

  def test_appends_the_text_after_what_the_notes_already_hold
    notes = review_notes_with_appendix(TEST_WALLET, APPENDIX)

    assert notes.start_with?(TEST_WALLET.rstrip)
    assert notes.end_with?("----\n\n#{APPENDIX.strip}")
  end

  def test_leaves_notes_alone_once_they_hold_the_text
    notes = review_notes_with_appendix(TEST_WALLET, APPENDIX)

    assert_nil review_notes_with_appendix(notes, APPENDIX)
  end

  def test_recognises_the_text_after_app_store_connect_rewraps_it
    stored = "#{TEST_WALLET}\r\n\r\nSWAP AND BUY FEATURES\r\n\r\nThe user signs each swap  on their device."

    assert_nil review_notes_with_appendix(stored, APPENDIX)
  end

  def test_writes_only_the_text_into_empty_notes
    assert_equal APPENDIX.strip, review_notes_with_appendix(nil, APPENDIX)
  end

  def test_hands_deliver_the_attachment_only_when_it_exists
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'supplementary-3.1.5.pdf')
      File.write(path, '%PDF-1.4')
      with_env('IOS_REVIEW_ATTACHMENT_PATH' => path) { assert_equal path, review_attachment_path }
      with_env('IOS_REVIEW_ATTACHMENT_PATH' => File.join(dir, 'missing.pdf')) do
        assert_raises(RuntimeError) { review_attachment_path }
      end
    end
    with_env('IOS_REVIEW_ATTACHMENT_PATH' => nil) { assert_nil review_attachment_path }
  end

  private

  def with_env(values)
    saved = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
