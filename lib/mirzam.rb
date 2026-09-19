# frozen_string_literal: true

require "date"
require "digest"
require "optparse"
require "yaml"
require "zlib"
require "zaniah"
require_relative "mirzam/version"

module Mirzam
  class Error < StandardError; end
  Source = Data.define(:title, :author, :date, :tags, :description, :accent, :template) do
    def self.from(hash)
      values = hash.transform_keys(&:to_sym)
      new(title: values.fetch(:title).to_s, author: values[:author]&.to_s,
        date: values[:date]&.to_s, tags: Array(values[:tags]).map(&:to_s),
        description: values[:description]&.to_s, accent: values[:accent],
        template: values[:template]&.to_sym)
    rescue KeyError
      raise Error, "front matter requires title"
    end
  end

  module FrontMatter
    module_function

    def parse(text)
      return Source.from(title: text.to_s) unless text.start_with?("---")
      closing = text.match(/^---\s*$\n?/, 3)
      raise Error, "front matter is not closed" unless closing
      header = text.byteslice(4...closing.begin(0))
      values = YAML.safe_load(header, permitted_classes: [Date, Time], aliases: false) || {}
      raise Error, "front matter must be a mapping" unless values.is_a?(Hash)
      Source.from(values)
    rescue Psych::Exception => error
      line = error.respond_to?(:line) ? error.line : nil
      raise Error, "invalid front matter#{line ? " at line #{line}" : ""}: #{error.message}"
    end

    def read(path)
      parse(File.read(path, encoding: "UTF-8"))
    rescue Errno::ENOENT
      raise Error, "input file not found: #{path}"
    end
  end

  module Sizing
    SIZES = [64, 56, 48, 42, 36].freeze
    module_function

    def fit_size(text, max_width:, max_height:, typesetter: nil)
      return SIZES.last unless typesetter
      SIZES.find do |size|
        paragraph = typesetter.layout_paragraph(text.to_s, width: max_width, size: size,
          wrap: :word, kinsoku: :hanging)
        paragraph.height <= max_height
      end || SIZES.last
    end
  end

  module Templates
    class Default
      SIZE = [1200, 630].freeze
      PADDING = 72

      def initialize(theme: Zaniah::Theme.dark, accent: nil)
        @theme = theme
        @accent = accent ? Zaniah::Color.parse(accent) : theme.colors.accent
      end

      def call(source, renderer)
        size = renderer.fit_size(source.title, max_width: SIZE[0] - PADDING * 2, max_height: 300)
        Zaniah::Div.new.flex_col.p(PADDING).gap(20).bg(@theme.colors.background)
          .child(Zaniah::Text.new(source.author ? "#{source.author} · #{source.date}" : "",
            size: 20, color: @accent))
          .child(Zaniah::Text.new(source.title, size: size, color: @theme.colors.text))
          .child(Zaniah::Text.new(source.tags.empty? ? "" : source.tags.map { |tag| "##{tag}" }.join("  "),
            size: 18, color: @theme.colors.text_muted))
      end
    end

    class Minimal < Default
      def call(source, renderer)
        size = renderer.fit_size(source.title, max_width: 1056, max_height: 420)
        Zaniah::Div.new.flex_col.justify_center.p(72).bg(@theme.colors.background)
          .child(Zaniah::Text.new(source.title, size: size, color: @theme.colors.text))
      end
    end

    class Feature < Default
      def call(source, renderer)
        Default.new(theme: @theme, accent: source.accent || @accent).call(source, renderer)
      end
    end

    module_function

    def resolve(name, theme: Zaniah::Theme.dark)
      case name.to_s
      when "default" then Default.new(theme: theme)
      when "minimal" then Minimal.new(theme: theme)
      when "feature" then Feature.new(theme: theme)
      else raise Error, "unknown template: #{name}"
      end
    end
  end

  class Renderer
    SIZE = [1200, 630].freeze

    attr_reader :typesetter

    def initialize(theme: Zaniah::Theme.dark, width: SIZE[0], height: SIZE[1])
      @theme, @width, @height = theme, width, height
      @font_db = Zaniah::TextSystem::FontDB.new(paths: [])
      @font = @font_db.find(family: theme.typography.font_sans)
      @text_system = Zaniah::TextSystem::Renderer.new(font: @font, font_db: @font_db)
      @typesetter = Zaniah::TextSystem::Typesetter.new(font: @font, font_db: @font_db)
    rescue StandardError
      @font_db = @font = @text_system = @typesetter = nil
    end

    def fit_size(text, max_width:, max_height:)
      return Sizing.fit_size(text, max_width: max_width, max_height: max_height, typesetter: @typesetter) if @typesetter
      Sizing::SIZES.last
    end

    def render(source, template: Templates::Default.new(theme: @theme))
      window = Zaniah::Platform.open_window(backend: :headless, width: @width, height: @height)
      window.text_system = @text_system if @text_system
      window.draw { template.call(source, self) }
      window.tick
      device = window.device
      Zaniah::PNG.encode(device.width.to_i, device.height.to_i, device.pixels)
    ensure
      window&.close
    end
  end

  class Batch
    def initialize(renderer: Renderer.new, template: :default)
      @renderer, @template = renderer, template
    end

    def render(paths, out_dir:, force: false)
      Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
      paths.sort.filter_map do |path|
        source = FrontMatter.read(path)
        destination = File.join(out_dir, "#{File.basename(path, ".*")}.png")
        signature = Digest::SHA256.hexdigest(File.binread(path) + @template.to_s)
        state_path = "#{destination}.json"
        next if !force && File.file?(destination) && File.file?(state_path) && File.read(state_path).include?(signature)
        png = @renderer.render(source, template: Templates.resolve(source.template || @template))
        File.binwrite(destination, png)
        File.write(state_path, "{\"sha256\":\"#{signature}\"}\n")
        destination
      end
    end
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr)
      command = %w[render batch templates].include?(argv.first) ? argv.shift : "render"
      case command
      when "templates"
        out.puts %w[default minimal feature]
        return 0
      when "render" then render(argv)
      when "batch" then batch(argv)
      end
    rescue OptionParser::ParseError, Error => error
      err.puts "mirzam: #{error.message}"
      1
    end

    def self.render(argv)
      options = {title: nil, author: nil, out: nil, input: nil, template: :default}
      OptionParser.new do |opts|
        opts.on("--input PATH") { |v| options[:input] = v }
        opts.on("--title TITLE") { |v| options[:title] = v }
        opts.on("--author NAME") { |v| options[:author] = v }
        opts.on("--out PATH") { |v| options[:out] = v }
        opts.on("--template NAME") { |v| options[:template] = v.to_sym }
      end.parse!(argv)
      source = options[:input] ? FrontMatter.read(options[:input]) : Source.from(title: options[:title] || argv.fetch(0))
      png = Renderer.new.render(source, template: Templates.resolve(source.template || options[:template]))
      File.binwrite(options[:out] || "mirzam.png", png)
      0
    end
    private_class_method :render

    def self.batch(argv)
      options = {out_dir: "public/ogp", template: :default, force: false}
      OptionParser.new do |opts|
        opts.on("--out-dir DIR") { |v| options[:out_dir] = v }
        opts.on("--template NAME") { |v| options[:template] = v.to_sym }
        opts.on("--force") { options[:force] = true }
      end.parse!(argv)
      paths = argv.flat_map { |pattern| Dir[pattern] }
      Batch.new(template: options[:template]).render(paths, out_dir: options[:out_dir], force: options[:force])
      0
    end
    private_class_method :batch
  end
end
