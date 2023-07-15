require 'test_helper'

module CLI
  module UI
    class TruncaterTest < Minitest::Test
      MAN     = "\u{1f468}" # width=2
      COOKING = "\u{1f373}" # width=2
      ZWJ     = "\u{200d}"  # width=complicated

      MAN_COOKING = MAN + ZWJ + COOKING # width=2

      HYPERLINK = ANSI.hyperlink('https://example.com', 'link')

      def test_truncate
        assert_example(3, 'foobar', "fo\x1b[0m…")
        assert_example(5, 'foobar', "foob\x1b[0m…")
        assert_example(6, 'foobar', 'foobar')
        assert_example(6, "foo\x1b[31mbar\x1b[0m", "foo\x1b[31mbar\x1b[0m")
        assert_example(6, "\x1b[31mfoobar", "\x1b[31mfoobar")
        assert_example(3, MAN_COOKING * 2, MAN_COOKING + Truncater::TRUNCATED)
        assert_example(3, 'A' + MAN_COOKING, 'A' + MAN_COOKING)
        assert_example(3, 'AB' + MAN_COOKING, 'AB' + Truncater::TRUNCATED)
        assert_example(14, "#{HYPERLINK} is a link", "#{HYPERLINK} is a link")
        assert_example(13, "#{HYPERLINK} is a link", "#{HYPERLINK} is a li#{Truncater::TRUNCATED}")
      end

      def test_hyperlinks_length
        [
          ['foo', 0],
          [HYPERLINK, 19],
          ["My #{HYPERLINK} is here", 19],
          ["My #{HYPERLINK} #{HYPERLINK} #{HYPERLINK} are here", 3 * 19],
        ].each do |text, expected|
          assert_equal(Truncater.send(:hyperlinks_length, text), expected)
        end
      end

      private

      def assert_example(width, from, to)
        truncated = CLI::UI::Truncater.call(from, width)
        assert_equal(to.codepoints.map { |c| c.to_s(16) }, truncated.codepoints.map { |c| c.to_s(16) })
      end
    end
  end
end
