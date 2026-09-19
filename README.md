# Mirzam

Deterministic 1200×630 OGP image generation from Markdown front matter. It
provides default, minimal, and feature templates, title fitting, and a SHA256
sidecar cache for batch builds.

## Installation

```sh
gem install mirzam
```

## Usage

```sh
mirzam render --input content/posts/hello.md --out public/ogp/hello.png
mirzam render --input content/posts/hello.json --out public/ogp/hello.png
mirzam render --title "Hello" --author noxdea --size 1200x630 --out hello.png
mirzam batch "content/posts/**/*.md" --out-dir public/ogp
mirzam templates
```

Front matter requires `title`; JSON input uses the same metadata keys.
`author`, `date`, `tags`, `accent`, and `ogp.template` are optional. The Ruby
API is `Mirzam.render(title: "Hello")`.
The same batch command is available through [`action.yml`](action.yml).

## Development

Run `rake spec` and `gem build --strict mirzam.gemspec`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/mirzam.

## License

MIT.
