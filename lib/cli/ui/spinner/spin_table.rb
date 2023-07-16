# typed: true

module CLI
  module UI
    module Spinner
      class SpinTable < CLI::UI::Spinner::SpinGroup
        DEFAULT_FINAL_GLYPH = ->(success) { success ? CLI::UI::Glyph::CHECK.to_s : CLI::UI::Glyph::X.to_s }

        class << self
          extend T::Sig

          sig { returns(Mutex) }
          attr_reader :pause_mutex

          sig { returns(T::Boolean) }
          def paused?
            @paused
          end

          sig do
            type_parameters(:T)
              .params(block: T.proc.returns(T.type_parameter(:T)))
              .returns(T.type_parameter(:T))
          end
          def pause_spinners(&block)
            previous_paused = T.let(nil, T.nilable(T::Boolean))
            @pause_mutex.synchronize do
              previous_paused = @paused
              @paused = true
            end
            block.call
          ensure
            @pause_mutex.synchronize do
              @paused = previous_paused
            end
          end
        end

        @pause_mutex = Mutex.new
        @paused = false

        # Initializes a new spin table
        # This lets you add +Task+ objects to the group to multi-thread work formatted as a table
        #
        # ==== Options
        #
        # * +:columns+ - Array of column titles and widths. Widths exclude the glyph and padding. Required.
        # * +:auto_debrief+ - Automatically debrief exceptions or through success_debrief? Default to true
        #
        # ==== Example Usage
        #
        # # typed: true
        #
        # require 'cli/ui'
        # require 'cli/ui/spinner/spin_table'
        #
        # COLUMNS = [
        #   { title: 'Row Title', width: 10 },
        #   { title: 'Column 1', width: 14 },
        #   { title: 'Column 2', width: 14 },
        # ]
        #
        # CLI::UI::StdoutRouter.enable
        #
        # CLI::UI::Spinner::SpinTable.new(columns: COLUMNS) do |spin_table|
        #   5.times do |r|
        #     spin_table.add("Row #{r + 1}") do |row|
        #       2.times do |c|
        #         row.add("Cell #{r + 1}/#{c + 1}") { |_spinner| sleep rand(5..10) }
        #       end
        #     end
        #   end
        #
        #   spin_table.add('Totals') do |row|
        #     2.times do |c|
        #       row.add("Total (#{c + 1})") do |spinner|
        #         sleep rand(5..10)
        #         spinner.update_title("End (#{c + 1})")
        #         sleep 3.0
        #       end
        #     end
        #   end
        # end
        #
        # Output:
        # TODO: update this gif
        # https://user-images.githubusercontent.com/3074765/33798558-c452fa26-dce8-11e7-9e90-b4b34df21a46.gif

        extend T::Sig

        sig { returns(T::Hash) }
        attr_accessor :columns

        sig { returns(T::Array[Row]) }
        attr_accessor :rows

        sig { params(columns: T::Array(Hash), auto_debrief: T::Boolean).void }
        def initialize(columns:, auto_debrief: true)
          @columns = columns
          @rows = []
          @m = Mutex.new
          super(auto_debrief: auto_debrief)
        end

        class Row
          extend T::Sig

          sig { returns(Integer) }
          attr_accessor :index

          sig { returns(String) }
          attr_accessor :title

          sig { returns(T::SpinTable) }
          attr_accessor :table

          sig { returns(T::Array[Task]) }
          attr_accessor :cells

          sig do
            params(
              index: Integer,
              title: String,
              table: T::SpinTable,
              block: T.proc.params(row: Row).void,
            )
          end
          def initialize(index, title, table, &block)
            @index = index
            @title = title
            @table = table
            @cells = []
            @m = Mutex.new
            block&.call(self)
          end

          # Add a cell/task to the row
          sig do
            params(
              title: String,
              final_glyph: T.proc.params(success: T::Boolean).returns(String),
              merged_output: T::Boolean,
              duplicate_output_to: IO,
              block: T.proc.params(task: Task).void,
            ).void
          end
          def add(
            title,
            final_glyph: DEFAULT_FINAL_GLYPH,
            merged_output: false,
            duplicate_output_to: File.new(File::NULL, 'w'),
            &block
          )
            @m.synchronize do
              column_index = cells.size + 1
              raise ArgumentError, "Too many columns for row #{index}" if column_index > table.columns.size

              cells << Task.new(
                title,
                index,
                column_index,
                table.columns[column_index][:width],
                table,
                final_glyph: final_glyph,
                merged_output: merged_output,
                duplicate_output_to: duplicate_output_to,
                &block
              )
            end
          end
        end

        class Task < CLI::UI::Spinner::SpinGroup::Task
          extend T::Sig

          sig { returns(Integer) }
          attr_accessor :row, :column, :width

          sig { returns(T::SpinTable) }
          attr_accessor :table

          sig do
            params(
              title: String,
              row: Integer,
              column: Integer,
              width: Integer,
              table: T::SpinTable,
              final_glyph: T.proc.params(success: T::Boolean).returns(String),
              merged_output: T::Boolean,
              duplicate_output_to: IO,
              block: T.proc.params(task: Task).returns(T.untyped),
            ).void
          end
          def initialize(title, row, column, width, table, final_glyph:, merged_output:, duplicate_output_to:, &block)
            @row = row
            @column = column
            @width = width
            @table = table
            super(
              title,
              final_glyph: final_glyph,
              merged_output: merged_output,
              duplicate_output_to: duplicate_output_to,
              &block
            )
          end

          # Re-renders the task if required:
          #
          # We try to be as lazy as possible in re-rendering the full cell. The
          # spinner rune will change on each render for the most part, but the
          # body text will rarely have changed. If the body text *has* changed,
          # we set @force_full_render.
          #
          # Further, if the title string includes any CLI::UI::Widgets, we
          # assume that it may change from render to render, since those
          # evaluate more dynamically than the rest of our format codes, which
          # are just text formatters. This is controlled by @always_full_render.
          #
          # ==== Attributes
          #
          # * +index+ - index of the glyph to render
          # * +force+ - force rerender of the task
          #
          sig { params(index: Integer, force: Boolean).void }
          def render(index, force = true)
            @m.synchronize do
              if force || @always_full_render || @force_full_render
                full_render(index)
              else
                partial_render(index)
              end
            ensure
              @force_full_render = false
            end
          end

          private

          sig { params(index: Integer).returns(String) }
          def full_render(index)
            prefix = cell_start_column + glyph(index) + CLI::UI::Color::RESET.code + ' '

            truncation_width = width - CLI::UI::ANSI.printing_width(prefix)

            render = prefix + CLI::UI.resolve_text(title, truncate_to: truncation_width)

            # Pad the string to the full width of the cell in case the new text is shorter than the old
            padding = width - CLI::UI::ANSI.printing_width(render)
            render.ljust(render.size + padding, ' ')
          end

          sig { params(index: Integer).returns(String) }
          def partial_render(index)
            cell_start_column + glyph(index) + CLI::UI::Color::RESET.code
          end

          sig { returns(String) }
          def cell_start_column
            start_column = table.columns.slice(0, column).sum { |c| c[:width] + 1 } + 1
            CLI::UI::ANSI.cursor_horizontal_absolute(start_column)
          end

          sig { params(index: Integer).returns(String) }
          def glyph(index)
            if @done
              @final_glyph.call(@success)
            else
              GLYPHS[index]
            end
          end
        end

        sig { params(title: String, block: T.proc.params(row: Row).void).void }
        def add(title, &block)
          @m.synchronize { rows << Row.new(rows.size, title, self, &block) }
        end

        # Tells the table you're done adding rows and cells, and to wait for everything to finish
        #
        # ==== Example Usage:
        #   spin_group = CLI::UI::SpinGroup.new
        #   spin_group.add('Title') { |spinner| sleep 1.0 }
        #   spin_group.wait
        #
        sig { returns(T::Boolean) }
        def wait
          draw_empty_table
          idx = 0

          force_full_render = true
          loop do
            done = true
            self.class.pause_mutex.synchronize do
              next if self.class.paused?

              @m.synchronize do
                CLI::UI.raw do
                  # Cursor up to first row of the table
                  print(CLI::UI::ANSI.cursor_up(rows.size))
                  rows_up = rows.size

                  rows.each do |row|
                    row.cells.each do |cell|
                      done = false unless cell.check
                      print(cell.render(idx, force_full_render))
                    end

                    # Move to the next row of the table
                    print(CLI::UI::ANSI.next_line)
                    rows_up -= 1
                  end
                ensure
                  # Cursor back to the bottom left. Useful to ensure clean error output.
                  print(CLI::UI::ANSI.cursor_down(rows_up)) if rows_up.positive?
                  print(CLI::UI::ANSI.cursor_horizontal_absolute)
                end
              end

              force_full_render = false
            end

            break if done

            idx = (idx + 1) % GLYPHS.size
            Spinner.index = idx
            sleep(PERIOD)
          end

          if @auto_debrief
            debrief
          else
            all_succeeded?
          end
        rescue Interrupt
          @tasks.each(&:interrupt)
          raise
        end

        sig { void }
        def draw_empty_table
          CLI::UI.raw do
            # Print column titles with underlines
            print(
              columns.map do |c|
                c[:title].ljust(c[:width])
              end.join(' '),
              "\n",
              columns.map { |c| '-' * c[:width] }.join(' '),
              "\n",
            )

            # Print row titles
            rows.each do |r|
              print("#{r.title}\n")
            end
          end
        end

        # Provide an alternative debriefing for failed tasks
        sig do
          params(
            block: T.proc.params(title: String, exception: T.nilable(Exception), out: String, err: String).void,
          ).void
        end
        def failure_debrief(&block)
          @failure_debrief = block
        end

        # Provide a debriefing for successful tasks
        sig do
          params(
            block: T.proc.params(title: String, out: String, err: String).void,
          ).void
        end
        def success_debrief(&block)
          @success_debrief = block
        end

        sig { returns(T::Boolean) }
        def all_succeeded?
          @m.synchronize do
            @tasks.all?(&:success)
          end
        end

        # Debriefs failed tasks if +auto_debrief+ is true
        #
        sig { returns(T::Boolean) }
        def debrief
          @m.synchronize do
            @tasks.each do |task|
              title = task.title
              out = task.stdout
              err = task.stderr

              if task.success
                next @success_debrief&.call(title, out, err)
              end

              e = task.exception
              next @failure_debrief.call(title, e, out, err) if @failure_debrief

              CLI::UI::Frame.open('Task Failed: ' + title, color: :red, timing: Time.new - @start) do
                if e
                  puts "#{e.class}: #{e.message}"
                  puts "\tfrom #{e.backtrace.join("\n\tfrom ")}"
                end

                CLI::UI::Frame.divider('STDOUT')
                out = '(empty)' if out.nil? || out.strip.empty?
                puts out

                CLI::UI::Frame.divider('STDERR')
                err = '(empty)' if err.nil? || err.strip.empty?
                puts err
              end
            end
            @tasks.all?(&:success)
          end
        end
      end
    end
  end
end
