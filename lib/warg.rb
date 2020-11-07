require "uri"
require "optparse"
require "pathname"
require "digest/sha1"

require "net/ssh"
require "net/scp"

unless Hash.method_defined?(:transform_keys)
  class Hash
    def transform_keys
      if block_given?
        map { |key, value| [yield(key), value] }.to_h
      else
        enum_for(:transform_keys)
      end
    end
  end
end

module Warg
  class InvalidHostDataError < StandardError
    def initialize(host_data)
      @host_data = host_data
    end

    def message
      "could not instantiate a host from `#{@host_data.inspect}'"
    end
  end

  class Console
    class << self
      attr_accessor :hostname_width
    end

    def initialize
      @io = $stdout
      @history = History.new
      @cursor_position = CursorPosition.new
      @mutex = Mutex.new

      $stdout = IOProxy.new($stdout, self)
      $stderr = IOProxy.new($stderr, self)
    end

    def print(string)
      print_content Content.new(string, self)
      nil
    end

    def puts(string)
      print_content Content.new("#{string}\n", self)
      nil
    end

    def print_content(content)
      @mutex.synchronize do
        @io.print content.to_s

        @history.append(content, row_number: @cursor_position.row)
        @cursor_position.advance(content.row_count)

        content
      end
    end

    def reprint_content(content)
      @mutex.lock

      history_entry = @history.find_entry_for(content)

      rows_from_cursor_row_to_content_start = @cursor_position.row - history_entry.row_number
      rows_from_cursor_row_to_content_end = rows_from_cursor_row_to_content_start - history_entry.row_count

      # move to line below the end of the content
      # skip if the nu
      unless rows_from_cursor_row_to_content_end.zero?
        @io.print "\e[#{rows_from_cursor_row_to_content_end}A"
      end

      # move ot first column of that line
      @io.print "\e[1G"

      # erase each line of the ouptut one by one moving up a line each time
      history_entry.row_count.times do
        # move up one line
        @io.print "\e[1A"
        # erase that line
        @io.print "\e[2K"
      end

      content.to_s.each_line do |line|
        # erase the line (again if on the first line)
        @io.print "\e[2K"

        # print the line
        @io.print line
      end

      if history_entry.row_count_changed?
        # go through all subsequent entries and...
        next_entry = history_entry.next_entry

        until next_entry.nil?
          # increment it's row number for if we reprint that content
          next_entry.row_number += history_entry.row_count_diff

          # print the content
          next_entry.to_s.each_line do |line|
            @io.print "\e[2K"
            @io.print line
          end

          # get the next entry to repeat
          next_entry = next_entry.next_entry
        end

        @cursor_position.advance(history_entry.row_count_diff)
      elsif rows_from_cursor_row_to_content_end > 0
        # Back to previous position
        @io.print "\e[#{rows_from_cursor_row_to_content_end}B"
        @io.print "\e[1G"
      end

      @mutex.unlock
    end

    class IOProxy < SimpleDelegator
      def initialize(io, console)
        @io = io
        @console = console
        __setobj__ @io
      end

      def print(content = nil)
        @console.print(content)
      end

      def puts(content = nil)
        @console.puts(content)
      end
    end

    class CursorPosition
      attr_reader :column
      attr_reader :row

      def initialize
        @column = 0
        @row = 0
      end

      def advance(row_count)
        @row += row_count
      end
    end

    class History
      def initialize
        @head = FirstEntry.new
      end

      def append(content, row_number:)
        entry = Entry.new(content, row_number)

        entry.previous_entry = @head
        @head.next_entry     = entry

        @head = entry
      end

      def find_entry_for(content)
        current_entry = @head

        until current_entry.previous_entry.nil? || current_entry.content == content
          current_entry = current_entry.previous_entry
        end

        current_entry
      end

      class FirstEntry
        attr_reader :content
        attr_accessor :next_entry
        attr_reader :previous_entry

        def row_number
          0
        end

        def row_count
          0
        end

        def row_count_changed?
          false
        end

        def to_s
          ""
        end
      end

      class Entry
        attr_reader :content
        attr_accessor :next_entry
        attr_accessor :previous_entry
        attr_reader :row_count
        attr_accessor :row_number

        def initialize(content, row_number)
          @content = content
          @row_number = row_number
          @row_count = @content.row_count
        end

        def row_count_changed?
          @row_count != @content.row_count
        end

        def row_count_diff
          @content.row_count - @row_count
        end

        def to_s
          @content.to_s
        end
      end
    end

    module TextRendering
      def SGR(text)
        Renderer.new(text)
      end

      class Renderer
        def initialize(text)
          @text = text
          @select_graphic_rendition = SelectGraphicRendition.new
        end

        def with(**options)
          @select_graphic_rendition = @select_graphic_rendition.modify(options)
          self
        end

        def to_s
          @select_graphic_rendition.(@text)
        end

        def to_str
          to_s
        end
      end
    end

    include TextRendering

    class Content
      include TextRendering

      def initialize(content, console)
        @content = content.freeze
        @console = console
      end

      def content=(value)
        @content = value.freeze
        @console.reprint_content(self)
        value
      end

      def row_count
        @content.each_line.count
      end

      def to_s
        @content
      end
    end

    class HostStatus
      include TextRendering

      attr_accessor :row_number

      def initialize(host, console)
        @host = host
        @console = console

        @hostname = host.address
        @state = SGR("STARTING").with(text_color: :cyan)
        @failure_message = ""

        @console.print_content self
      end

      def row_count
        1 + @failure_message.each_line.count
      end

      def started!
        @state = SGR("RUNNING").with(text_color: :magenta)

        @console.reprint_content(self)
      end

      def failed!(failure_message = "")
        @state = SGR("FAILED").with(text_color: :red, effect: :bold)
        @failure_message = failure_message.to_s

        @console.reprint_content(self)
      end

      def success!
        @state = SGR("DONE").with(text_color: :green)

        @console.reprint_content(self)
      end

      def to_s
        content = "  %-#{Console.hostname_width}s\t[ %s ]\n" % [@hostname, @state]

        unless @failure_message.empty?
          indented_failure_message = @failure_message.each_line.
            map { |line| line.prepend("    ") }.
            join

          content << SGR(indented_failure_message).with(text_color: :yellow)
        end

        content
      end
    end

    class SelectGraphicRendition
      TEXT_COLORS = {
        "red"     => "31",
        "green"   => "32",
        "yellow"  => "33",
        "blue"    => "34",
        "magenta" => "35",
        "cyan"    => "36",
        "white"   => "37",
      }

      BACKGROUND_COLORS = TEXT_COLORS.map { |name, value| [name, (value.to_i + 10).to_s] }.to_h

      EFFECTS = {
        "bold"          => "1",
        "faint"         => "2",
        "italic"        => "3",
        "underline"     => "4",
        "blink_slow"    => "5",
        "blink_fast"    => "6",
        "invert_colors" => "7",
        "hide"          => "8",
        "strikethrough" => "9"
      }

      def initialize(text_color: "0", background_color: "0", effect: "0")
        @text_color = TEXT_COLORS.fetch(text_color.to_s, text_color)
        @background_color = BACKGROUND_COLORS.fetch(background_color.to_s, background_color)
        @effect = EFFECTS.fetch(effect.to_s, effect)
      end

      def call(text)
        "#{self}#{text}#{RESET}"
      end

      def wrap(text)
        call(text)
      end

      def modify(**attrs)
        self.class.new(to_h.merge(attrs))
      end

      def |(other)
        self.class.new(to_h.merge(other.to_h))
      end

      def to_str
        "\e[#{@background_color};#{@effect};#{@text_color}m"
      end

      def to_s
        to_str
      end

      def to_h
        {
          text_color: @text_color,
          background_color: @background_color,
          effect: @effect
        }
      end

      RESET = new
    end

    SGR = SelectGraphicRendition
  end

  class Localhost
    def address
      "localhost"
    end

    def run
      outcome = CommandOutcome.new

      begin
        outcome.command_started!

        yield
      rescue => error
        outcome.error = error
      end

      outcome.command_finished!
      outcome
    end

    class CommandOutcome
      attr_accessor :error

      def initialize
        @console_status = Console::HostStatus.new(LOCALHOST, Warg.console)
        @started_at = nil
        @finished_at = nil
      end

      def command_started!
        @started_at = Time.now
        @started_at.freeze

        @console_status.started!
      end

      def command_finished!
        @finished_at = Time.now
        @finished_at.freeze

        if successful?
          @console_status.success!
        else
          @console_status.failed!(failure_summary)
        end
      end

      def successful?
        error.nil?
      end

      def failed?
        !successful?
      end

      def started?
        not @started_at.nil?
      end

      def finished?
        not @finished_at.nil?
      end

      def duration
        if @started_at && @finished_at
          @finished_at - @started_at
        end
      end

      def failure_summary
        error && error.full_message
      end
    end
  end

  LOCALHOST = Localhost.new

  class Host
    module Parser
      module_function

      REGEXP = URI.regexp("ssh")

      def call(host_string)
        match_data = REGEXP.match("ssh://#{host_string}")

        query_string = match_data[8] || ""
        query_fragments = query_string.split("&")

        properties = query_fragments.inject({}) do |all, fragment|
          name, value = fragment.split("=", 2)
          all.merge!(name.to_sym => value)
        end

        {
          user: match_data[3],
          address: match_data[4],
          port: match_data[5],
          properties: properties
        }
      end
    end

    def self.from(host_data)
      case host_data
      when Host
        host_data
      when Hash
        attributes = host_data.transform_keys(&:to_sym)

        new(**attributes)
      when Array
        if host_data.length == 1 && Hash === host_data[0]
          from(host_data[0])
        elsif String === host_data[0]
          last_item_index = -1
          attributes = Parser.(host_data[0])

          if Hash === host_data[-1]
            last_item_index = -2

            more_properties = host_data[-1].transform_keys(&:to_sym)
            attributes[:properties].merge!(more_properties)
          end

          host_data[1..last_item_index].each do |property|
            name, value = property.to_s.split("=", 2)
            attributes[:properties][name.to_sym] = value
          end

          new(**attributes)
        else
          raise InvalidHostDataError.new(host_data)
        end
      when String
        new(**Parser.(host_data))
      else
        raise InvalidHostDataError.new(host_data)
      end
    end

    attr_reader :address
    attr_reader :id
    attr_reader :port
    attr_reader :uri
    attr_reader :user

    def initialize(user: nil, address:, port: nil, properties: {})
      @user = user
      @address = address
      @port = port
      @properties = properties.transform_keys(&:to_s)

      build_uri!
    end

    def matches?(filters)
      filters.all? do |name, value|
        if respond_to?(name)
          send(name) == value
        else
          @properties[name.to_s] == value
        end
      end
    end

    def [](name)
      @properties[name.to_s]
    end

    def []=(name, value)
      @properties[name.to_s] = value

      build_uri!

      value
    end

    def ==(other)
      self.class == other.class && uri == other.uri
    end

    alias eql? ==

    def hash
      inspect.hash
    end

    def run_command(command, &callback)
      outcome = CommandOutcome.new(self, command)

      connection.open_channel do |channel|
        channel.exec(command) do |_, success|
          outcome.command_started!

          channel.on_data do |_, data|
            outcome.collect_stdout(data)
          end

          channel.on_extended_data do |_, __, data|
            outcome.collect_stderr(data)
          end

          channel.on_request("exit-status") do |_, data|
            outcome.exit_status = data.read_long
          end

          channel.on_request("exit-signal") do |_, data|
            outcome.exit_signal = data.read_string
          end

          channel.on_open_failed do |_, code, reason|
            outcome.connection_failed(code, reason)
          end

          channel.on_close do |_|
            outcome.command_finished!
          end
        end

        channel.wait
      end

      connection.loop

      if callback
        callback.(self, outcome)
      end

      outcome
    rescue SocketError, Errno::ECONNREFUSED, Net::SSH::AuthenticationFailed => error
      outcome.connection_failed(-1, "#{error.class}: #{error.message}")
      outcome
    end

    def run_script(script, &callback)
      create_directory script.install_directory

      create_file_from script.content, path: script.install_path, mode: 0755

      run_command(script.remote_path, &callback)
    end

    def create_directory(directory)
      command = "mkdir -p #{directory}"

      connection.open_channel do |channel|
        channel.exec(command)
        channel.wait
      end

      connection.loop
    end

    def create_file_from(content, path:, mode: 0644)
      filename = "#{id}-#{File.basename(path)}"

      tempfile = Tempfile.new(filename)
      tempfile.chmod(mode)
      tempfile.write(content)
      tempfile.rewind

      upload tempfile, to: path

      tempfile.unlink
    end

    def upload(file, to:)
      connection.scp.upload!(file, to)
    end

    def download(path, to: nil)
      content = connection.scp.download!(path)

      if to
        file = File.new(to, "w+b")
      else
        file = Tempfile.new(path)
      end

      file.write(content)
      file.rewind

      file
    end

    def inspect
      %{#<#{self.class.name} uri=#{@uri.to_s}>}
    end

    def to_s
      @uri.to_s
    end

    private

    def connection
      if defined?(@connection)
        @connection
      else
        options = { non_interactive: true }

        if port
          options[:port] = port
        end

        @connection = Net::SSH.start(address, user || Warg.default_user, options)
      end
    end

    def build_uri!
      @uri = URI.parse("ssh://")

      @uri.user = @user
      @uri.host = @address
      @uri.port = @port

      unless @properties.empty?
        @uri.query = @properties.map { |name, value| "#{name}=#{value}" }.join("&")
      end

      @id = Digest::SHA1.hexdigest(@uri.to_s)
    end

    class CommandOutcome
      attr_reader :command
      attr_reader :connection_error_code
      attr_reader :connection_error_reason
      attr_reader :console_state
      attr_reader :exit_signal
      attr_reader :exit_status
      attr_reader :failure_reason
      attr_reader :finished_at
      attr_reader :host
      attr_reader :started_at
      attr_reader :stderr
      attr_reader :stdout

      include Console::TextRendering

      def initialize(host, command)
        @host = host
        @command = command

        @console_status = Console::HostStatus.new(host, Warg.console)

        @stdout = ""
        @stderr = ""

        @started_at = nil
        @finished_at = nil
      end

      def collect_stdout(data)
        @stdout << data
      end

      def collect_stderr(data)
        @stderr << data
      end

      def successful?
        exit_status && exit_status.zero?
      end

      def failed?
        !successful?
      end

      def started?
        not @started_at.nil?
      end

      def finished?
        not @finished_at.nil?
      end

      def exit_status=(value)
        if finished?
          $stderr.puts "[WARN] cannot change `#exit_status` after command has finished"
        else
          @exit_status = value

          if failed?
            @failure_reason = :nonzero_exit_status
          end
        end

        value
      end

      def exit_signal=(value)
        if finished?
          $stderr.puts "[WARN] cannot change `#exit_signal` after command has finished"
        else
          @exit_signal = value
          @exit_signal.freeze

          @failure_reason = :exit_signal
        end

        value
      end

      def duration
        if @finished_at && @started_at
          @finished_at - @started_at
        end
      end

      def command_started!
        if @started_at
          $stderr.puts "[WARN] command already started"
        else
          @started_at = Time.now
          @started_at.freeze

          @console_status.started!
        end
      end

      def command_finished!
        if finished?
          $stderr.puts "[WARN] command already finished"
        else
          @stdout.freeze
          @stderr.freeze

          @finished_at = Time.now
          @finished_at.freeze

          if successful?
            @console_status.success!
          else
            @console_status.failed!(failure_summary)
          end
        end
      end

      def connection_failed(code, reason)
        @connection_error_code = code.freeze
        @connection_error_reason = reason.freeze

        @failure_reason = :connection_error

        unless started?
          @console_status.failed!(failure_summary)
        end
      end

      def failure_summary
        case failure_reason
        when :exit_signal, :nonzero_exit_status
          adjusted_stdout, adjusted_stderr = [stdout, stderr].map do |output|
            adjusted = output.each_line.map { |line| line.prepend("  ") }.join.chomp

            if adjusted.empty?
              adjusted = "(empty)"
            end

            adjusted
          end

          <<~OUTPUT
            STDOUT: #{adjusted_stdout}
            STDERR: #{adjusted_stderr}
          OUTPUT
        when :connection_error
          <<~OUTPUT
            Connection failed:
              Code: #{connection_error_code}
              Reason: #{connection_error_reason}
          OUTPUT
        end
      end
    end
  end

  class HostCollection
    include Enumerable

    def self.from(value)
      case value
      when String, Host
        new.add(value)
      when HostCollection
        value
      when Array
        is_array_host_specification = value.any? do |item|
          # Check key=value items by looking for `=` missing `?`.  If it has `?`, then we
          # assume it is in the form `host?key=value`
          String === item and item.index("=") and not item.index("?")
        end

        if is_array_host_specification
          new.add(value)
        else
          value.inject(new) { |collection, host_data| collection.add(host_data) }
        end
      when Hash
        value.inject(new) do |collection, (property, hosts_data)|
          name, value = property.to_s.split(":", 2)

          if value.nil?
            value = name
            name = "stage"
          end

          from(hosts_data).each do |host|
            host[name] = value
            collection.add(host)
          end

          collection
        end
      when nil
        new
      else
        raise InvalidHostDataError.new(value)
      end
    end

    def initialize
      @hosts = []
    end

    def one
      if @hosts.empty?
        raise "cannot pick a host from `#{inspect}'; collection is empty"
      end

      HostCollection.from @hosts.sample
    end

    def add(host_data)
      @hosts << Host.from(host_data)

      self
    end

    def with(**filters)
      HostCollection.from(select { |host| host.matches?(**filters) })
    end

    def ==(other)
      self.class == other.class &&
        length == other.length &&
        # both are the same length and their intersection is the same length (all the same
        # elements in common)
        length == @hosts.&(other.hosts).length
    end

    alias eql? ==

    def length
      @hosts.length
    end

    def create_file_from(content, path:, mode: 0644)
      each do |host|
        host.create_file_from(content, path: path, mode: mode)
      end
    end

    def upload(file, to:)
      each do |host|
        host.upload(file, to: to)
      end
    end

    def download(path)
      map do |host|
        host.download(path)
      end
    end

    def each
      if block_given?
        @hosts.each { |host| yield host }
      else
        enum_for(:each)
      end

      self
    end

    def run_script(script, order: :parallel, &callback)
      run(order: order) do |host, result|
        result.update host.run_script(script, &callback)
      end
    end

    def run_command(command, order: :parallel, &callback)
      run(order: order) do |host, result|
        result.update host.run_command(command, &callback)
      end
    end

    def run(order:, &block)
      strategy = Executor.for(order)
      executor = strategy.new(self)
      executor.run(&block)
    end

    def to_a
      @hosts.dup
    end

    protected

    attr_reader :hosts
  end

  class Config
    attr_accessor :default_user
    attr_reader :hosts
    attr_reader :variables_sets

    def initialize
      @hosts = HostCollection.new
      @variables_sets = Set.new
    end

    def hosts=(value)
      @hosts = HostCollection.from(value)
    end

    def variables_set_defined?(name)
      @variables_sets.include?(name.to_s)
    end

    def [](name)
      if variables_set_defined?(name.to_s)
        instance_variable_get("@#{name}")
      end
    end

    def variables(name, &block)
      variables_name = name.to_s
      ivar_name = "@#{variables_name}"

      if @variables_sets.include?(variables_name)
        variables_object = instance_variable_get(ivar_name)
      else
        @variables_sets << variables_name

        singleton_class.send(:attr_reader, variables_name)
        variables_object = instance_variable_set(ivar_name, VariableSet.new(variables_name, self))
      end

      block.call(variables_object)
    end

    class VariableSet
      attr_reader :context

      def initialize(name, context)
        @_name = name
        @context = context
        # FIXME: make this "private" by adding an underscore
        @properties = Set.new
      end

      def context=(*)
        raise NotImplementedError
      end

      def defined?(property_name)
        @properties.include?(property_name.to_s)
      end

      def define!(property_name)
        @properties << property_name.to_s
      end

      def copy(other)
        other.properties.each do |property_name|
          value = other.instance_variable_get("@#{property_name}")

          extend Property.new(property_name, value)
        end
      end

      def to_h
        @properties.each_with_object({}) do |property_name, variables|
          variables["#{@_name}_#{property_name}"] = send(property_name)
        end
      end

      protected

      attr_reader :properties

      def method_missing(name, *args, &block)
        writer_name = name.to_s
        reader_name = writer_name.chomp("=")

        if reader_name !~ Property::REGEXP
          super
        elsif reader_name == writer_name && block.nil?
          $stderr.puts "`#{@_name}.#{reader_name}' was accessed before it was defined"
          nil
        elsif writer_name.end_with?("=") or not block.nil?
          value = block || args

          extend Property.new(reader_name, *value)
        end
      end

      private

      class Property < Module
        REGEXP = /^[A-Za-z_]+$/

        def initialize(name, initial_value = nil)
          @name = name
          @initial_value = initial_value
        end

        def extended(variables_set)
          variables_set.define! @name

          variables_set.singleton_class.class_eval <<-PROPERTY_METHODS
            attr_writer :#{@name}

            def #{@name}(&block)
              if block.nil?
                value = instance_variable_get(:@#{@name})

                if value.respond_to?(:call)
                  instance_eval(&value)
                else
                  value
                end
              else
                instance_variable_set(:@#{@name}, block)
              end
            end
          PROPERTY_METHODS

          variables_set.instance_variable_set("@#{@name}", @initial_value)
        end
      end
    end
  end

  class Context < Config
    attr_reader :argv
    attr_reader :parser

    def initialize(argv)
      @argv = argv
      @parser = OptionParser.new

      @parser.on("-h", "--hosts HOSTS", Array, "hosts to use") do |hosts_data|
        hosts_data.each { |host_data| hosts.add(host_data) }
      end

      super()
    end

    def copy(config)
      config.hosts.each do |host|
        hosts.add(host)
      end

      config.variables_sets.each do |variables_name|
        variables(variables_name) do |variables_object|
          variables_object.copy config.instance_variable_get("@#{variables_name}")
        end
      end
    end
  end

  class Runner
    def initialize(argv)
      @argv = argv.dup
      @path = nil

      find_warg_directory!
      load_config!

      @context = Context.new(@argv)
      @context.copy(Warg.config)

      load_scripts!
      load_commands!

      @command = Command.find(@argv)
    end

    def run
      if @command.nil?
        $stderr.puts "Could not find command from #{@argv.inspect}"
        exit 1
      end

      @command.(@context)
    end

    private

    def find_warg_directory!
      previous_directory = nil
      current_directory = Pathname.new(Dir.pwd)

      while @path.nil? && current_directory.directory? && current_directory != previous_directory
        target = current_directory.join("warg")

        if target.directory?
          @path = target

          Warg.search_paths.unshift(@path)
          Warg.search_paths.uniq!
        else
          previous_directory = current_directory
          current_directory = current_directory.parent
        end
      end

      if @path.nil?
        $stderr.puts "`warg' directory not found in current directory or ancestors"
        exit 1
      end
    end

    def load_config!
      config_path = @path.join("config.rb")

      if config_path.exist?
        load config_path
      end

      Dir.glob(@path.join("config", "**", "*.rb")).each do |config_file|
        load config_file
      end
    end

    def load_commands!
      Warg.search_paths.each do |warg_path|
        Dir.glob(warg_path.join("commands", "**", "*.rb")).each do |command_path|
          load command_path
        end
      end
    end

    def load_scripts!
      Warg.search_paths.each do |warg_path|
        warg_scripts_path = warg_path.join("scripts")

        Dir.glob(warg_scripts_path.join("**", "*")).each do |path|
          script_path = Pathname.new(path)

          if script_path.directory? || script_path.basename.to_s.index("_defaults") == 0
            next
          end

          relative_script_path = script_path.relative_path_from(warg_scripts_path)

          command_name = Command::Name.from_relative_script_path(relative_script_path)

          object_names = command_name.object.split("::")
          object_names.inject(Object) do |namespace, object_name|
            if namespace.const_defined?(object_name)
              object = namespace.const_get(object_name)
            else
              if object_name == object_names[-1]
                object = Class.new do
                  include Command::Behavior

                  def run
                    run_script
                  end
                end
              else
                object = Module.new
              end

              namespace.const_set(object_name, object)

              if object < Command::Behavior
                Warg::Command.register(object)
              end
            end

            object
          end
        end
      end
    end
  end

  class Executor
    class << self
      attr_reader :strategies
    end

    @strategies = {}

    def self.for(name)
      @strategies.fetch(name)
    end

    def self.register(name, &block)
      strategy = Class.new(self)
      strategy.send(:define_method, :in_order, &block)

      @strategies[name] = strategy
    end

    attr_reader :hosts
    attr_reader :result

    def initialize(hosts)
      @hosts = hosts
      @result = Result.new
    end

    # FIXME: error handling?
    def run(&block)
      in_order(&block)
      result
    end

    def in_order(&block)
      raise NotImplementedError
    end

    register :parallel do |&procedure|
      host_threads = hosts.map do |host|
        Thread.new do
          procedure.call(host, result)
        end
      end

      host_threads.each(&:join)
    end

    register :serial do |&procedure|
      hosts.each do |host|
        procedure.call(host, result)
      end
    end

    class Result
      include Enumerable
      extend Forwardable

      def_delegator :value, :each

      attr_reader :value

      def initialize
        @mutex = Mutex.new
        @successful = true
        @value = []
      end

      def update(command_outcome)
        @mutex.synchronize do
          @value << command_outcome
          @successful &&= command_outcome.successful?
        end
      end

      def successful?
        @mutex.synchronize do
          @successful
        end
      end

      def failed?
        @mutex.synchronize do
          not @successful
        end
      end
    end
  end

  class Command
    class << self
      attr_reader :registry
    end

    @registry = {}

    def self.register(klass)
      if Warg::Command.registry.key?(klass.registry_name)
        # TODO: include debug information in the warning
        $stderr.puts "[WARN] command with the name `#{klass.command_name}' already exists " \
          "and is being replaced"
      end

      Warg::Command.registry[klass.registry_name] = klass
    end

    def self.inherited(klass)
      register(klass)
    end

    def self.find(argv)
      klass = nil

      argv.each do |arg|
        if @registry.key?(arg)
          klass = @registry.fetch(arg)
        end
      end

      klass
    end

    class Name
      def self.from_relative_script_path(path)
        script_name = path.to_s.chomp File.extname(path)

        new(script_name: script_name.tr("_", "-"))
      end

      attr_reader :cli
      attr_reader :object
      attr_reader :script

      def initialize(class_name: nil, script_name: nil)
        if class_name.nil? && script_name.nil?
          raise ArgumentError, "`script_name' or `class_name' must be specified"
        end

        if class_name
          @object = class_name

          @script = class_name.gsub("::", "/")
          @script.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1-\2')
          @script.gsub!(/([a-z\d])([A-Z])/, '\1-\2')
          @script.downcase!
        elsif script_name
          @script = script_name

          @object = script_name.gsub(/[a-z\d]*/) { |match| match.capitalize }
          @object.gsub!(/(?:_|-|(\/))([a-z\d]*)/i) { "#{$1}#{$2.capitalize}" }
          @object.gsub!("/", "::")
        end

        @cli = @script.tr("/", ":")
      end

      def registry
        @cli
      end

      def to_s
        @cli.dup
      end
    end

    module Naming
      def self.extended(klass)
        Warg::Command.register(klass)
      end

      def command_name
        if defined?(@command_name)
          @command_name
        else
          @command_name = Name.new(class_name: name)
        end
      end

      def registry_name
        command_name.registry
      end
    end

    module Behavior
      include Console::TextRendering

      def self.included(klass)
        klass.extend(ClassMethods)
      end

      module ClassMethods
        include Naming

        def call(context)
          command = new(context)
          command.call
          command
        end

        def |(other)
          ChainCommand.new(self, other)
        end
      end

      attr_reader :argv
      attr_reader :context
      attr_reader :hosts
      attr_reader :parser

      def initialize(context)
        @context = context

        @parser = @context.parser
        @hosts = @context.hosts
        @argv = @context.argv.dup

        configure_parser!
        parse_options!
      end

      def name
        command_name.cli
      end

      def call
        Warg.console.puts SGR("[#{name}]").with(text_color: :blue, effect: :bold)

        run

        self
      end

      def run
        $stderr.puts "[WARN] `#{name}' did not define `#run' and does nothing"
      end

      def command_name
        self.class.command_name
      end

      def |(other)
        other.(context)
      end

      def chain(*others)
        others.inject(self) do |execution, other|
          execution | other
        end
      end

      private

      def configure_parser!
      end

      def parse_options!
        parser.parse(argv)
      end

      def run_script(script_name = nil, on: hosts, order: :parallel, &callback)
        script_name ||= command_name.script
        script = Script.new(script_name, context)

        execute(:script, script, on: on, order: order, &callback)
      end

      def run_command(command, on: hosts, order: :parallel, &callback)
        execute(:command, command, on: on, order: order, &callback)
      end

      def execute(run_type, command_or_script, on: hosts, order:, &callback)
        Console.hostname_width = on.map { |host| host.address.length }.max

        Warg.console.puts SGR(" -> #{command_or_script}").with(text_color: :magenta)

        execution_result = on.run(order: order) do |host, result|
          result.update host.public_send("run_#{run_type}", command_or_script, &callback)
        end

        if execution_result.failed?
          on_failure(execution_result)
        end

        execution_result
      end

      def on_localhost(banner)
        Warg.console.puts SGR(" -> #{banner}").with(text_color: :magenta)

        execution_result = Executor::Result.new
        execution_result.update LOCALHOST.run { yield }

        if execution_result.failed?
          on_failure(execution_result)
        end

        execution_result
      end
      alias locally on_localhost

      def on_failure(execution_result)
        exit 1
      end
    end

    include Behavior
  end

  class ChainCommand
    def initialize(left, right)
      @left = left
      @right = right
    end

    def call(context)
      @left.(context) | @right
    end

    def |(other)
      ChainCommand.new(self, other)
    end
  end

  class Script
    class Template
      INTERPOLATION_REGEXP = /%{([\w:]+)}/

      def self.find(relative_script_path, fail_if_missing: true)
        extension = File.extname(relative_script_path)
        relative_paths = [relative_script_path]

        if extension.empty?
          relative_paths << "#{relative_script_path}.sh"
        else
          relative_paths << relative_script_path.chomp(extension)
        end

        paths_checked = []

        script_path = Warg.search_paths.inject(nil) do |path, directory|
          relative_paths.each do |relative_path|
            target_path = directory.join("scripts", relative_path)
            paths_checked << target_path

            if target_path.exist?
              path = target_path
            end
          end

          if path
            break path
          end
        end

        if script_path
          new(script_path)
        elsif fail_if_missing
          raise <<~ERROR
            ScriptNotFoundError: Could not find `#{relative_script_path}'
              Looked in:
                #{paths_checked.join("\n")}
          ERROR
        else
          MISSING
        end
      end

      class Missing
        def compile(*)
          "".freeze
        end
      end

      MISSING = Missing.new

      attr_reader :content

      def initialize(file_path)
        @path = file_path
        @content = @path.read
      end

      def compile(interpolations)
        @content.gsub(INTERPOLATION_REGEXP) do |match|
          if interpolations.key?($1)
            interpolations[$1]
          else
            $stderr.puts "[WARN] `#{$1}' is not defined in interpolations or context variables"
            $stderr.puts "[WARN]   leaving interpolation `#{match}' as is"
            match
          end
        end
      end
    end

    REMOTE_DIRECTORY = Pathname.new("$HOME").join("warg", "scripts")

    class Interpolations
      CONTEXT_REGEXP = /variables:(\w+)/

      def initialize(context)
        @context = context
        @values = {}
      end

      def key?(key)
        if key =~ CONTEXT_REGEXP
          @context.variables_set_defined?($1)
        else
          @values.key?(key)
        end
      end

      def [](key)
        if @values.key?(key)
          @values[key]
        elsif key =~ CONTEXT_REGEXP && @context.variables_set_defined?($1)
          variables = @context[$1]
          content = variables.to_h.sort.map { |key, value| %{#{key}="#{value}"} }.join("\n")

          @values[key] = content
        end
      end

      def []=(key, value)
        @values[key] = value
      end
    end

    attr_reader :content
    attr_reader :name
    attr_reader :remote_path

    def initialize(script_name, context, defaults_path: nil)
      command_name = Command::Name.from_relative_script_path(script_name)
      @name = command_name.script

      local_path = Pathname.new(@name)

      # FIXME: search parent directories for a defaults script
      defaults_path ||= File.join(local_path.dirname, "_defaults")
      defaults = Template.find(defaults_path, fail_if_missing: false)

      interpolations = Interpolations.new(context)
      interpolations["script_name"] = @name
      interpolations["script_defaults"] = defaults.compile(interpolations).chomp

      template = Template.find(local_path.to_s)
      @content = template.compile(interpolations)

      @remote_path = REMOTE_DIRECTORY.join(local_path)
    end

    def name
      @remote_path.relative_path_from(REMOTE_DIRECTORY).to_s
    end

    def install_directory
      @remote_path.dirname
    end

    def install_path
      @remote_path.relative_path_from Pathname.new("$HOME")
    end

    def to_s
      name.dup
    end
  end

  class << self
    attr_reader :config
    attr_reader :console
    attr_reader :search_paths
  end

  @config = Config.new
  @console = Console.new
  @search_paths = []

  def self.configure
    yield config
  end

  def self.default_user
    config.default_user
  end
end
