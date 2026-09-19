# frozen_string_literal: true

require "tempfile"

RSpec.describe Mirzam do
  it "parses front matter and normalizes optional values" do
    source = Mirzam::FrontMatter.parse("---\ntitle: Hello\ntags: [ruby, ui]\n---\nbody")
    expect(source.title).to eq("Hello")
    expect(source.tags).to eq(%w[ruby ui])
  end

  it "rejects missing titles" do
    expect { Mirzam::Source.from(author: "x") }.to raise_error(Mirzam::Error)
  end

  it "selects a size when a typesetter measures paragraphs" do
    typesetter = instance_double("Typesetter")
    allow(typesetter).to receive(:layout_paragraph).and_return(instance_double("Paragraph", height: 100))
    expect(Mirzam::Sizing.fit_size("title", max_width: 100, max_height: 100, typesetter: typesetter)).to eq(64)
  end

  it "reads JSON metadata and rejects non-object input" do
    json = Tempfile.new(["mirzam", ".json"])
    json.write('{"title":"JSON title","tags":["ruby"]}')
    json.close
    expect(Mirzam::Input.read(json.path).title).to eq("JSON title")
    File.write(json.path, '[]')
    expect { Mirzam::Input.read(json.path) }.to raise_error(Mirzam::Error, /mapping/)
  ensure
    json&.unlink
  end

  it "keeps image branding metadata and uses a bundled font" do
    source = Mirzam::Source.from(title: "Title", logo: "logo.png", avatar: "avatar.png")
    expect(source.logo).to eq("logo.png")
    expect(source.avatar).to eq("avatar.png")
    expect(Mirzam::Renderer::FONTS).not_to be_empty
  end
end
