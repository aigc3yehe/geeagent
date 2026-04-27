# Bookmark Vault

Bookmark Vault is a first-party Gee Gear for saving arbitrary content as local
bookmarks.

## Data

Mutable data is stored outside the package:

```text
~/Library/Application Support/GeeAgent/gear-data/bookmark.vault/bookmarks/<id>/bookmark.json
```

Each record keeps fixed fields for:

- `raw_content`
- `page_title`
- `url`

Additional metadata can include description, site name, thumbnail URL, canonical
URL, media title, platform, uploader, duration, extension hint, format count,
and source-specific `extras`.

## Metadata Strategy

When content contains a URL, Bookmark Vault enriches it in this order:

- Twitter/X tweet URLs use the public oEmbed endpoint first.
- Other URLs use `yt-dlp --dump-single-json --skip-download` first to match the
  SmartYT media metadata range.
- Remaining URLs use a small HTTP fetch and parse OpenGraph, Twitter Card,
  canonical URL, title, and description fields.

If enrichment fails, the bookmark is still saved with the original content and
URL.

## Agent Capability

The Gear exposes one capability:

```json
{
  "gear_id": "bookmark.vault",
  "capability_id": "bookmark.save",
  "args": {
    "content": "https://example.com/watch?v=demo"
  }
}
```

The capability returns structured bookmark data. The final user-facing reply
must be composed by the active agent/LLM from that structured result, not
hardcoded by the gear.
