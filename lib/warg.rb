require "optparse"
require "pathname"
require "digest/sha1"

module Warg
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
        end
      when String
        new(**Parser.(host_data))
      else
        $stderr.puts "InvalidHostError: cannot translate `#{host_data}' into a host"
        exit 1
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

    def inspect
      %{#<#{self.class.name} uri=#{@uri.to_s}>}
    end

    def to_s
      @uri.to_s
    end

    private

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
  end

  class HostCollection
    include Enumerable

    def self.from(value)
      case value
      when String
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
        raise ArgumentError, "cannot build host collection from `#{value.inspect}'"
      end
    end

    def initialize
      @hosts = []
    end

    def add(host_data)
      @hosts << Host.from(host_data)

      self
    end

    def with(**filters)
      HostCollection.from(select { |host| host.matches?(**filters) })
    end

    def length
      @hosts.length
    end

    def each
      if block_given?
        @hosts.each { |host| yield host }
      else
        enum_for(:each)
      end

      self
    end

    def to_a
      @hosts.dup
    end
  end

  class Config
    attr_accessor :default_user
    attr_reader :hosts

    def initialize
      @hosts = HostCollection.new
    end

    def hosts=(value)
      @hosts = HostCollection.from(value)
    end
  end

  class Context < Config
    attr_reader :argv

    def initialize(argv)
      @argv = argv

      super()
    end

    def copy(config)
      config.hosts.each do |host|
        hosts.add(host)
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

      parse_options!
      load_commands!

      @command = Command.find(@argv)
    end

    def run
      if @command.nil?
        raise "could not find command from #{@argv.inspect}"
      end

      @command.(@context)
    end

    private

    def parse_options!
      parser = OptionParser.new do |parser|
        parser.on("-h", "--hosts HOSTS", Array, "hosts to use") do |hosts_data|
          hosts_data.each { |host_data| @context.hosts.add(host_data) }
        end

        parser.on("-f", "--filter FILTERS", Array, "filters for filtering hosts") do |filters|
          @context.hosts.filtered(filters)
        end
      end

      parser.parse(@argv)
    end

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

    def self.command_name
      if defined?(@command_name)
        @command_name
      else
        @command_name = Name.new(name)
      end
    end

    def self.registry_name
      command_name.registry
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

    def self.call(context)
      command = new(context)
      command.run
      command
    end

    class Name
      attr_reader :object
      attr_reader :script
      attr_reader :cli

      def initialize(class_name)
        @object = class_name

        @script = class_name.gsub("::", "/")
        @script.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1-\2')
        @script.gsub!(/([a-z\d])([A-Z])/, '\1-\2')
        @script.downcase!

        @cli = @script.tr("/", ":")
      end

      def registry
        @cli
      end

      def to_s
        @cli.dup
      end
    end

    def initialize(context)
      @context = context
      @argv = @context.argv.dup
      @parser = OptionParser.new

      configure_parser!
    end

    def name
      command_name.cli
    end

    def run
      $stderr.puts "[WARN] `#{name}' did not define `#run' and does nothing"
    end

    def command_name
      self.class.command_name
    end

    private

    def configure_parser!
    end
  end

  class << self
    attr_reader :config
    attr_reader :search_paths
  end

  @config = Config.new
  @search_paths = []

  def self.configure
    yield config
  end

  def self.default_user
    config.default_user
  end
end
