# WeSpy Reader

WeSpy Reader wraps the MIT-licensed [`wespy`](https://github.com/tianchangNorth/WeSpy) Python package as an optional Gee gear.

It keeps the third-party scraper outside GeeAgent's core runtime. The gear invokes `python3` and imports the user's installed `wespy` package, then writes Markdown-first capture tasks under:

```text
~/Library/Application Support/GeeAgent/gear-data/wespy.reader/tasks
```

Install the Python package before using this gear:

```sh
python3 -m pip install --user wespy
```

Capabilities:

- `wespy.fetch_article`: fetch one article URL.
- `wespy.list_album`: list article URLs from a WeChat album.
- `wespy.fetch_album`: batch-fetch WeChat album articles.

WeSpy handles wx public-account pages, WeChat album URLs, Juejin, and many standard article pages. It may fail when source sites require authentication, block automation, or change page structure.
