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
class FakeApp
  class << self
    attr_accessor :app

    def find(_identifier)
      app
    end
  end
end
module Spaceship
  module ConnectAPI
    App = FakeApp
    module Platform
      IOS = 'IOS'
    end
  end
end
load File.expand_path('../Fastfile', __dir__)

class ReviewMaterialsTest < Minitest::Test
  TEST_WALLET = "Test seed phrase on balance:\n\nalpha beta gamma\n\n----\n\nExplore section catalog index\n"
  APPENDIX = "SWAP AND BUY FEATURES\n\nThe user signs each swap on their device.\n"
  INDEX_URL = 'https://gramwallet.io/~explore-catalog-index.html'
  BOTH = { 'IOS_REVIEW_NOTES_APPENDIX' => APPENDIX, 'IOS_REVIEW_CATALOG_INDEX_URL' => INDEX_URL }

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

  def test_adds_the_catalog_index_link_after_the_required_text
    with_env(BOTH) do
      notes = review_notes_with_appendices(TEST_WALLET, review_notes_appendices)

      assert notes.start_with?(TEST_WALLET.rstrip)
      assert_operator notes.index(APPENDIX.strip), :<, notes.index(INDEX_URL)
      assert notes.end_with?(INDEX_URL)
      assert_nil review_notes_with_appendices(notes, review_notes_appendices)
    end
  end

  def test_adds_only_the_part_the_notes_lack
    with_env(BOTH) do
      held = review_notes_with_appendix(TEST_WALLET, APPENDIX)
      notes = review_notes_with_appendices(held, review_notes_appendices)

      assert notes.start_with?(held)
      assert_equal 1, notes.scan('SWAP AND BUY FEATURES').length
      assert_includes notes, INDEX_URL
    end
  end

  def test_leaves_notes_alone_when_they_name_the_catalog_index_link_in_other_words
    with_env(BOTH) do
      held = "#{review_notes_with_appendix(TEST_WALLET, APPENDIX)}\n\n----\n\nExplore section catalog index\n#{INDEX_URL}"
      full = { appendices: review_notes_appendices, attachment_name: nil }

      assert_nil review_notes_with_appendices(held, review_notes_appendices)
      assert_empty find_review_materials_gaps(notes: held, attachment_names: [], **full)
    end
  end

  def test_asks_for_no_catalog_index_when_the_app_has_none
    with_env('IOS_REVIEW_NOTES_APPENDIX' => APPENDIX, 'IOS_REVIEW_CATALOG_INDEX_URL' => nil) do
      assert_equal [[APPENDIX.strip, APPENDIX.strip]], review_notes_appendices
    end
    with_env('IOS_REVIEW_NOTES_APPENDIX' => nil, 'IOS_REVIEW_CATALOG_INDEX_URL' => ' ') do
      assert_empty review_notes_appendices
    end
  end

  def test_hands_deliver_the_attachment_only_when_it_exists
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'supplementary-3.1.5.pdf')
      File.write(path, '%PDF-1.4')
      with_env('IOS_REVIEW_ATTACHMENT_PATH' => path) { assert_equal path, review_attachment_path }
      with_env('IOS_REVIEW_ATTACHMENT_PATH' => File.join(dir, 'missing.pdf')) do
        assert_raises(RuntimeError) { review_attachment_path }
      end
      empty = File.join(dir, 'empty.pdf')
      File.write(empty, '')
      with_env('IOS_REVIEW_ATTACHMENT_PATH' => empty) { assert_raises(RuntimeError) { review_attachment_path } }
    end
    with_env('IOS_REVIEW_ATTACHMENT_PATH' => nil) { assert_nil review_attachment_path }
  end

  def test_names_every_material_the_submission_lacks
    appendices = with_env(BOTH) { review_notes_appendices }
    notes = review_notes_with_appendices(TEST_WALLET, appendices)
    full = { appendices: appendices, attachment_name: 'supplementary-3.1.5.pdf' }

    assert_empty find_review_materials_gaps(notes: notes, attachment_names: ['supplementary-3.1.5.pdf'], **full)
    assert_equal 2, find_review_materials_gaps(notes: TEST_WALLET, attachment_names: [], **full).length
    without_index = review_notes_with_appendix(TEST_WALLET, APPENDIX)
    assert_equal 1, find_review_materials_gaps(notes: without_index, attachment_names: ['supplementary-3.1.5.pdf'], **full).length
    assert_empty find_review_materials_gaps(notes: nil, attachment_names: [], appendices: [], attachment_name: nil)
  end

  def test_fails_the_lane_when_the_submitted_version_lacks_the_attachment
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'supplementary-3.1.5.pdf')
      File.write(path, '%PDF-1.4')
      notes = review_notes_with_appendix(TEST_WALLET, APPENDIX)
      env = { 'IOS_REVIEW_NOTES_APPENDIX' => APPENDIX, 'IOS_REVIEW_CATALOG_INDEX_URL' => nil, 'IOS_REVIEW_ATTACHMENT_PATH' => path }

      with_submitted_version(notes, []) do
        with_env(env) do
          error = assert_raises(RuntimeError) { verify_review_materials!('26.11.5', pause: 0) }
          assert_includes error.message, 'supplementary-3.1.5.pdf'
        end
      end
      with_submitted_version(notes, ['supplementary-3.1.5.pdf']) do
        with_env(env) { verify_review_materials!('26.11.5', pause: 0) }
      end
      with_submitted_version(notes, [], ['supplementary-3.1.5.pdf']) do
        with_env(env) { verify_review_materials!('26.11.5', pause: 0) }
      end
    end
  end

  def test_fails_the_lane_when_the_submitted_version_lacks_the_catalog_index_link
    notes = review_notes_with_appendix(TEST_WALLET, APPENDIX)

    with_submitted_version(notes, []) do
      with_env(BOTH.merge('IOS_REVIEW_ATTACHMENT_PATH' => nil)) do
        error = assert_raises(RuntimeError) { verify_review_materials!('26.11.5', pause: 0) }
        assert_includes error.message, 'the notes lack the required text'
      end
    end
  end

  def test_skips_the_check_when_no_materials_are_configured
    with_env('IOS_REVIEW_NOTES_APPENDIX' => nil, 'IOS_REVIEW_CATALOG_INDEX_URL' => nil, 'IOS_REVIEW_ATTACHMENT_PATH' => nil) do
      assert_nil verify_review_materials!('26.11.5')
    end
  end

  private

  # Each list is what one readback returns, and the last one repeats
  def with_submitted_version(notes, *readbacks)
    details = readbacks.map do |names|
      attachments = names.map { |name| Struct.new(:file_name).new(name) }
      Struct.new(:notes, :app_store_review_attachments).new(notes, attachments)
    end
    version = Object.new
    version.define_singleton_method(:fetch_app_store_review_detail) { details.length > 1 ? details.shift : details.first }
    app = Object.new
    app.define_singleton_method(:get_app_store_versions) { |filter:| filter[:versionString] == '26.11.5' ? [version] : [] }
    FakeApp.app = app
    yield
  ensure
    FakeApp.app = nil
  end

  def with_env(values)
    saved = values.keys.to_h { |key| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
