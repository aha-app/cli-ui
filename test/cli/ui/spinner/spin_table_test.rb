require 'test_helper'

module CLI
  module UI
    module Spinner
      class SpinTableTest < Minitest::Test
        COLUMNS = [
          { title: 'Service', width: 15 },
          { title: 'Progress', width: 20 },
        ]

        def test_spin_table
          out, err = capture_io do
            CLI::UI::StdoutRouter.ensure_activated

            st = create_spin_table do
              true
            end

            assert(st.wait)
          end

          [
            'Service         Progress            ',
            '─────────────── ────────────────────',
            'Service A',
            'Starting...    ',
          ].each do |line|
            assert(out.include?(line), "Unable to find '#{line}' in output")
          end

          assert_equal('', err)
        end

        def test_spin_table_auto_debrief_false
          _out, err = capture_io do
            CLI::UI::StdoutRouter.ensure_activated

            st = create_spin_table({ auto_debrief: false }) do
              true
            end

            assert(st.wait)
          end

          assert_equal('', err)
        end

        def test_spin_table_success_debrief
          capture_io do
            CLI::UI::StdoutRouter.ensure_activated

            debriefer = ->(title, out, err) {}
            st = SpinTable.new(columns: COLUMNS)
            st.success_debrief(&debriefer)
            debriefer.expects(:call).with('Service A - Progress', "Task output\n", '').once
            row = st.add('Service A')
            row.add('Starting...') do
              puts('Task output')
              true
            end

            assert(st.wait)
          end
        end

        def create_spin_table(options = {}, &block)
          SpinTable.new(columns: COLUMNS, **options) do |st|
            st.add('Service A') do |row|
              row.add('Starting...') do
                yield block
              end
            end
          end
        end
      end
    end
  end
end
