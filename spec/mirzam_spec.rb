# frozen_string_literal: true

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
end
