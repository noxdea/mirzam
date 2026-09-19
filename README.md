<h1 align="center">Mirzam</h1>

<p align="center">
  <strong>Deterministic 1200×630 OGP image generator for Markdown and JSON metadata.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/mirzam"><img src="https://img.shields.io/gem/v/mirzam?style=flat-square" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/mirzam"><img src="https://img.shields.io/gem/dt/mirzam?style=flat-square" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/mirzam/actions/workflows/main.yml"><img src="https://github.com/noxdea/mirzam/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.2-CC342D?style=flat-square" alt="Ruby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#metadata">Metadata</a> ·
  <a href="#batch-builds">Batch builds</a> ·
  <a href="#github-action">GitHub Action</a>
</p>

---

Mirzam is a deterministic 1200×630 OGP image generator for Markdown and JSON
metadata. It renders through [Zaniah](https://github.com/noxdea/zaniah) and
supports one-off images, cached batch builds, and GitHub Actions.

## Features

- **Markdown and JSON input** — use front matter or the same metadata as JSON.
- **Deterministic PNG output** — stable rendering for repeatable builds.
- **Responsive titles** — fit long headings into the available image area.
- **Built-in templates** — choose `default`, `minimal`, or `feature`.
- **Brand assets** — resolve logos and avatars relative to the source document.
- **Cached batches** — SHA-256 sidecars skip unchanged inputs.
- **Theme support** — named Zaniah themes and Auva token files when Auva is installed.

## Installation

```bash
gem install mirzam
```

Mirzam requires Ruby 3.2 or newer.

## Quick start

Add front matter to a Markdown document:

```yaml
---
title: Build native Ruby interfaces
author: noxdea
date: 2026-09-20
tags: [ruby, ui]
ogp:
  template: feature
  accent: "#e3b45b"
---
```

Render it:

```bash
mirzam render \
  --input content/posts/native-ruby.md \
  --out public/ogp/native-ruby.png
```

Metadata can also come from JSON:

```bash
mirzam render --input article.json --out article.png
```

## Metadata

| Key | Required | Description |
|---|---|---|
| `title` | yes | Main image heading |
| `author` | no | Author or publication name |
| `date` | no | Display date |
| `tags` | no | Labels rendered below the title |
| `description` | no | Supporting copy used by the `feature` template |
| `accent` | no | Accent color |
| `template` | no | `default`, `minimal`, `feature`, or a Ruby template file |
| `logo` / `avatar` | no | Image paths resolved from the input directory |

`accent`, `template`, `logo`, and `avatar` may also live under `ogp`.

## Batch builds

```bash
mirzam batch "content/posts/**/*.md" --out-dir public/ogp
```

Mirzam writes a JSON sidecar beside each PNG and skips unchanged files. Use
`--force` to rebuild everything:

```bash
mirzam batch "content/posts/**/*.md" --out-dir public/ogp --force
```

Useful options include `--template`, `--theme`, `--size WIDTHxHEIGHT`, and
`--font-dir`.

## GitHub Action

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@v4
  - uses: noxdea/mirzam@v0.1.0
    with:
      pattern: "content/posts/**/*.md"
      out-dir: public/ogp
      template: feature
```

Set `force: true` to ignore sidecar hashes. The action also accepts `theme`.

## Ruby API

```ruby
require "mirzam"

png = Mirzam.render(
  title: "Build native Ruby interfaces",
  author: "noxdea",
  tags: %w[ruby ui],
  template: :feature
)

File.binwrite("ogp.png", png)
```

## Development

```bash
bundle install
bundle exec rake
bundle exec rbs -I sig validate
gem build --strict mirzam.gemspec
```

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/noxdea/mirzam).

## License

Mirzam is available under the [MIT License](LICENSE.txt).
