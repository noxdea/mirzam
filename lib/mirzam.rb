# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "yaml"
require "zlib"
require "zaniah"
begin
  require "auva"
rescue LoadError
end
require_relative "mirzam/version"

module Mirzam
  class Error < StandardError; end
  Source = Data.define(:title, :author, :date, :tags, :description, :accent, :template, :logo, :avatar) do
    def self.from(hash)
      raise Error, "metadata must be a mapping" unless hash.is_a?(Hash)
      values = hash.transform_keys(&:to_sym)
      ogp = values[:ogp].is_a?(Hash) ? values[:ogp].transform_keys(&:to_sym) : {}
      new(title: values.fetch(:title).to_s, author: values[:author]&.to_s,
        date: values[:date]&.to_s, tags: Array(values[:tags]).map(&:to_s),
        description: values[:description]&.to_s, accent: values[:accent] || ogp[:accent],
        template: (values[:template] || ogp[:template])&.to_sym,
        logo: (values[:logo] || ogp[:logo])&.to_s, avatar: (values[:avatar] || ogp[:avatar])&.to_s)
    rescue KeyError
      raise Error, "front matter requires title"
    end
  end

  module FrontMatter
    module_function

    def parse(text)
      text = text.to_s.delete_prefix("\uFEFF")
      return Source.from(title: text.to_s) unless text.start_with?("---")
      closing = text.match(/^---\s*$\n?/, 3)
      raise Error, "front matter is not closed" unless closing
      header = text[4...closing.begin(0)]
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

  module Input
    module_function

    def read(path)
      source = File.read(path, encoding: "UTF-8").delete_prefix("\uFEFF")
      metadata = File.extname(path).downcase == ".json" ? Source.from(JSON.parse(source)) : FrontMatter.parse(source)
      base = File.dirname(File.expand_path(path))
      metadata.with(logo: resolve_asset(metadata.logo, base), avatar: resolve_asset(metadata.avatar, base))
    rescue Errno::ENOENT
      raise Error, "input file not found: #{path}"
    rescue JSON::ParserError => error
      raise Error, "invalid JSON: #{error.message}"
    end

    def resolve_asset(value, base)
      return value unless value && !value.empty? && !Pathname.new(value).absolute?
      File.expand_path(value, base)
    rescue ArgumentError
      value
    end
    private_class_method :resolve_asset
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
        root = Zaniah::Div.new.flex_col.p(PADDING).gap(20).bg(@theme.colors.background)
          .child(brand(source))
          .child(Zaniah::Text.new(source.author ? "#{source.author} · #{source.date}" : "",
            size: 20, color: @accent))
          .child(Zaniah::Text.new(source.title, size: size, color: @theme.colors.text))
          .child(Zaniah::Text.new(source.tags.empty? ? "" : source.tags.map { |tag| "##{tag}" }.join("  "),
            size: 18, color: @theme.colors.text_muted))
        root
      end

      private

      def brand(source)
        path = source.avatar || source.logo
        return Zaniah::Div.new.h(1) unless path && File.file?(path)
        Zaniah::Image.new(path).style(width: 64, height: 64)
      rescue StandardError
        Zaniah::Div.new.h(1)
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
          .child(Zaniah::Text.new(source.description.to_s, size: 16, color: @theme.colors.text_muted))
      end
    end

    module_function

    def resolve(name, theme: Zaniah::Theme.dark)
      if name.to_s.end_with?(".rb") && File.file?(name.to_s)
        path = File.expand_path(name.to_s)
        value = eval(File.read(path, encoding: "UTF-8"), TOPLEVEL_BINDING, path, 1)
        return value if value.respond_to?(:call)
        raise Error, "template file must return a callable"
      end
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
    FONTS = Dir[File.expand_path("../assets/fonts/*.{ttf,otf}", __dir__)].freeze

    attr_reader :typesetter

    def initialize(theme: Zaniah::Theme.dark, width: SIZE[0], height: SIZE[1], font_dir: nil)
      @theme, @width, @height, @font_dir = theme, width, height, font_dir
      @font_db = Zaniah::TextSystem::FontDB.new(paths: font_dir ? Array(font_dir) : FONTS)
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

    def cache_key
      [@width, @height, @font_dir, @theme.inspect].join("\0")
    end

    def render(source, template: Templates::Default.new(theme: @theme))
      app = Zaniah::App.new
      window = app.open_window(backend: :headless, width: @width, height: @height)
      app.global(:theme, @theme)
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
      FileUtils.mkdir_p(out_dir)
      paths.sort.filter_map do |path|
        source = Input.read(path)
        destination = File.join(out_dir, "#{File.basename(path, ".*")}.png")
        template_path = @template.to_s
        template_signature = File.file?(template_path) ? File.binread(template_path) : @template.to_s
        signature = Digest::SHA256.hexdigest(File.binread(path) + template_signature + @renderer.cache_key)
        state_path = "#{destination}.json"
        next if !force && File.file?(destination) && File.file?(state_path) && File.read(state_path).include?(signature)
        png = @renderer.render(source, template: Templates.resolve(source.template || @template))
        File.binwrite(destination, png)
        File.write(state_path, "{\"sha256\":\"#{signature}\"}\n")
        destination
      end
    end
  end

  module_function

  def theme(value)
    return value if value.respond_to?(:colors)
    return Auva.load(value) if defined?(Auva) && File.file?(value.to_s)
    return Auva.builtin(value) if defined?(Auva)
    Zaniah::Theme.public_send(value.to_s)
  rescue NoMethodError
    raise Error, "unknown theme: #{value}"
  end

  def render(title:, author: nil, date: nil, tags: [], description: nil, accent: nil, logo: nil, avatar: nil,
    template: :default, theme: :dark, width: 1200, height: 630, font_dir: nil)
    source = Source.new(title: title.to_s, author: author&.to_s, date: date&.to_s,
      tags: Array(tags).map(&:to_s), description: description&.to_s, accent: accent, template: template.to_sym,
      logo: logo&.to_s, avatar: avatar&.to_s)
    selected_theme = theme(theme)
    Renderer.new(theme: selected_theme, width: width, height: height, font_dir: font_dir)
      .render(source, template: Templates.resolve(template, theme: selected_theme))
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr)
      command = %w[render batch templates preview].include?(argv.first) ? argv.shift : "render"
      case command
      when "templates"
        out.puts %w[default minimal feature]
        return 0
      when "render", "preview" then render(argv)
      when "batch" then batch(argv)
      end
    rescue OptionParser::ParseError, KeyError, Error => error
      err.puts "mirzam: #{error.message}"
      1
    end

    def self.render(argv)
      options = {title: nil, author: nil, logo: nil, avatar: nil, out: nil, input: nil, template: :default, theme: :dark, width: 1200, height: 630, font_dir: nil}
      OptionParser.new do |opts|
        opts.on("--input PATH") { |v| options[:input] = v }
        opts.on("--title TITLE") { |v| options[:title] = v }
        opts.on("--author NAME") { |v| options[:author] = v }
        opts.on("--logo PATH") { |v| options[:logo] = v }
        opts.on("--avatar PATH") { |v| options[:avatar] = v }
        opts.on("--out PATH") { |v| options[:out] = v }
        opts.on("--template NAME") { |v| options[:template] = v.end_with?(".rb") ? v : v.to_sym }
        opts.on("--theme NAME") { |v| options[:theme] = v }
        opts.on("--size SIZE") { |v| options[:width], options[:height] = v.split("x", 2).map { |part| Integer(part, 10) } }
        opts.on("--font-dir PATH") { |v| options[:font_dir] = v }
      end.parse!(argv)
      source = options[:input] ? Input.read(options[:input]) : Source.from(title: options[:title] || argv.fetch(0),
        author: options[:author], logo: options[:logo], avatar: options[:avatar])
      selected_theme = Mirzam.theme(options[:theme])
      selected_template = source.template || options[:template]
      png = Renderer.new(theme: selected_theme, width: options[:width], height: options[:height], font_dir: options[:font_dir])
        .render(source, template: Templates.resolve(selected_template, theme: selected_theme))
      File.binwrite(options[:out] || "mirzam.png", png)
      0
    end
    private_class_method :render

    def self.batch(argv)
      options = {out_dir: "public/ogp", template: :default, force: false, theme: :dark, width: 1200, height: 630, font_dir: nil}
      OptionParser.new do |opts|
        opts.on("--out-dir DIR") { |v| options[:out_dir] = v }
        opts.on("--template NAME") { |v| options[:template] = v.end_with?(".rb") ? v : v.to_sym }
        opts.on("--theme NAME") { |v| options[:theme] = v }
        opts.on("--size SIZE") { |v| options[:width], options[:height] = v.split("x", 2).map { |part| Integer(part, 10) } }
        opts.on("--font-dir PATH") { |v| options[:font_dir] = v }
        opts.on("--force") { options[:force] = true }
      end.parse!(argv)
      paths = argv.flat_map { |pattern| Dir[pattern] }
      renderer = Renderer.new(theme: Mirzam.theme(options[:theme]), width: options[:width], height: options[:height], font_dir: options[:font_dir])
      Batch.new(renderer: renderer, template: options[:template]).render(paths, out_dir: options[:out_dir], force: options[:force])
      0
    end
    private_class_method :batch
  end
end
