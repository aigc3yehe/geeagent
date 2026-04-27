#!/usr/bin/env python3
"""
Twitter Capture Twikit sidecar.

JSON stdin/stdout protocol:
  {"action":"fetch_tweet","params":{"cookie_file":"...","tweet_id":"..."}}
  {"action":"fetch_list","params":{"cookie_file":"...","list_id":"...","max_tweets":30}}
  {"action":"fetch_user","params":{"cookie_file":"...","handle":"@openai","max_tweets":30}}
"""

import asyncio
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

try:
    from twikit import Client
    from twikit.tweet import tweet_from_data
    from twikit.utils import find_dict
    import twikit.user
    try:
        import twikit.guest.user as twikit_guest_user
    except ImportError:
        twikit_guest_user = None
    import twikit.x_client_transaction.transaction
    import twikit.client.client
    import json as twikit_json
    from twikit.client.client import DOMAIN
except ImportError as exc:
    print(json.dumps({"error": f"twikit is not installed: {exc}"}), flush=True)
    sys.exit(1)


original_get_indices = twikit.x_client_transaction.transaction.ClientTransaction.get_indices


async def patched_get_indices(self, home_page_response, session, headers):
    try:
        return await original_get_indices(self, home_page_response, session, headers)
    except Exception as exc:
        if "KEY_BYTE" in str(exc):
            return 0, [0] * 16
        raise


twikit.x_client_transaction.transaction.ClientTransaction.get_indices = patched_get_indices

original_request = twikit.client.client.Client.request


async def patched_request(self, method, url, auto_unlock=True, raise_exception=True, **kwargs):
    headers = kwargs.pop("headers", {})

    if not self.client_transaction.home_page_response:
        cookies_backup = self.get_cookies().copy()
        ct_headers = {
            "Accept-Language": f'{self.language},{self.language.split("-")[0]};q=0.9',
            "Cache-Control": "no-cache",
            "Referer": f"https://{DOMAIN}",
            "User-Agent": self._user_agent,
        }
        await self.client_transaction.init(self.http, ct_headers)
        self.set_cookies(cookies_backup, clear_cookies=True)

    tid = self.client_transaction.generate_transaction_id(method=method, path=urlparse(url).path)
    headers["X-Client-Transaction-Id"] = tid
    response = await self.http.request(method, url, headers=headers, **kwargs)
    self._remove_duplicate_ct0_cookie()

    try:
        response_data = response.json()
    except twikit_json.decoder.JSONDecodeError:
        response_data = response.text

    if response.status_code >= 400 and raise_exception:
        message = f'status: {response.status_code}, message: "{response.text}"'
        if response.status_code == 400:
            raise twikit.client.client.BadRequest(message, headers=response.headers)
        if response.status_code == 401:
            raise twikit.client.client.Unauthorized(message, headers=response.headers)
        if response.status_code == 403:
            raise twikit.client.client.Forbidden(message, headers=response.headers)
        if response.status_code == 404:
            raise twikit.client.client.NotFound(message, headers=response.headers)
        if response.status_code == 429:
            raise twikit.client.client.TooManyRequests(message, headers=response.headers)
        if 500 <= response.status_code < 600:
            raise twikit.client.client.ServerError(message, headers=response.headers)
        raise twikit.client.client.TwitterException(message, headers=response.headers)

    return response_data, response


twikit.client.client.Client.request = patched_request


def normalize_user_payload(data):
    if not isinstance(data, dict):
        return data
    legacy = data.get("legacy")
    if not isinstance(legacy, dict):
        return data

    normalized = dict(data)
    normalized.setdefault("is_blue_verified", False)
    normalized_legacy = dict(legacy)
    entities = normalized_legacy.get("entities")
    entities = dict(entities) if isinstance(entities, dict) else {}
    description = entities.get("description")
    description = dict(description) if isinstance(description, dict) else {}
    description.setdefault("urls", [])
    url_entity = entities.get("url")
    url_entity = dict(url_entity) if isinstance(url_entity, dict) else {}
    url_entity.setdefault("urls", [])
    entities["description"] = description
    entities["url"] = url_entity
    normalized_legacy["entities"] = entities

    for key, default in {
        "created_at": "",
        "name": "",
        "screen_name": "",
        "profile_image_url_https": "",
        "location": "",
        "description": "",
        "pinned_tweet_ids_str": [],
        "verified": False,
        "possibly_sensitive": False,
        "can_dm": False,
        "can_media_tag": False,
        "want_retweets": True,
        "default_profile": False,
        "default_profile_image": False,
        "has_custom_timelines": False,
        "followers_count": 0,
        "fast_followers_count": 0,
        "normal_followers_count": normalized_legacy.get("followers_count", 0),
        "friends_count": 0,
        "favourites_count": 0,
        "listed_count": 0,
        "media_count": 0,
        "statuses_count": 0,
        "is_translator": False,
        "translator_type": "none",
        "withheld_in_countries": [],
    }.items():
        normalized_legacy.setdefault(key, default)

    normalized["legacy"] = normalized_legacy
    return normalized


def patch_user_init(user_module):
    original_init = user_module.User.__init__
    if getattr(original_init, "_gee_urls_patch", False):
        return

    def patched_user_init(self, client, data):
        return original_init(self, client, normalize_user_payload(data))

    patched_user_init._gee_urls_patch = True
    user_module.User.__init__ = patched_user_init


patch_user_init(twikit.user)
if twikit_guest_user is not None:
    patch_user_init(twikit_guest_user)


def load_cookie_map(cookie_file):
    raw = Path(cookie_file).expanduser().read_text(encoding="utf-8")
    data = json.loads(raw)
    if isinstance(data, dict):
        return {str(key): str(value) for key, value in data.items() if value is not None}
    if isinstance(data, list):
        cookies = {}
        for item in data:
            if isinstance(item, dict) and item.get("name") and item.get("value") is not None:
                cookies[str(item["name"])] = str(item["value"])
        if cookies:
            return cookies
    raise ValueError("Unsupported cookie file format. Expected an object or an array of {name, value} cookies.")


def build_client(cookie_file):
    client = Client(language="en-US")
    client.set_cookies(load_cookie_map(cookie_file))
    return client


async def close_client(client):
    http_client = getattr(client, "http", None)
    if http_client is not None:
        await http_client.aclose()


def safe_int(value):
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def has_substantive_text(text):
    if not text:
        return False
    without_urls = re.sub(r"https?://\\S+", " ", text)
    return bool(re.search(r"[A-Za-z0-9\\u3040-\\u30ff\\u3400-\\u9fff\\uf900-\\ufaff\\uac00-\\ud7af]", without_urls))


def extract_article_text(raw_payload):
    article = raw_payload.get("article") if isinstance(raw_payload.get("article"), dict) else None
    article_results = article.get("article_results") if isinstance(article, dict) and isinstance(article.get("article_results"), dict) else None
    result = article_results.get("result") if isinstance(article_results, dict) and isinstance(article_results.get("result"), dict) else None
    if not isinstance(result, dict):
        return ""
    title = str(result.get("title") or "").strip()
    preview_text = str(result.get("preview_text") or "").strip()
    return "\\n\\n".join(part for part in (title, preview_text) if part).strip()


def extract_media_items(raw_payload):
    legacy = raw_payload.get("legacy") if isinstance(raw_payload.get("legacy"), dict) else None
    entities = legacy.get("extended_entities") if isinstance(legacy, dict) and isinstance(legacy.get("extended_entities"), dict) else None
    if not entities:
        entities = legacy.get("entities") if isinstance(legacy, dict) and isinstance(legacy.get("entities"), dict) else None
    media_items = entities.get("media") if isinstance(entities, dict) and isinstance(entities.get("media"), list) else []
    normalized = []
    for item in media_items:
        if not isinstance(item, dict):
            continue
        media_type = str(item.get("type") or "unknown").strip().lower() or "unknown"
        preview_url = str(item.get("media_url_https") or item.get("media_url") or "").strip()
        video_info = item.get("video_info") if isinstance(item.get("video_info"), dict) else None
        variants = video_info.get("variants") if isinstance(video_info, dict) and isinstance(video_info.get("variants"), list) else []
        best_variant_url = ""
        best_bitrate = -1
        for variant in variants:
            if not isinstance(variant, dict):
                continue
            variant_url = str(variant.get("url") or "").strip()
            if not variant_url:
                continue
            bitrate = int(variant.get("bitrate") or 0)
            if bitrate >= best_bitrate:
                best_bitrate = bitrate
                best_variant_url = variant_url
        original_info = item.get("original_info") if isinstance(item.get("original_info"), dict) else None
        normalized.append({
            "id": str(item.get("id_str") or item.get("id") or ""),
            "type": "image" if media_type == "photo" else "gif" if media_type == "animated_gif" else "video" if media_type == "video" else "unknown",
            "url": best_variant_url or preview_url,
            "preview_url": preview_url or best_variant_url or None,
            "width": original_info.get("width") if isinstance(original_info, dict) and isinstance(original_info.get("width"), int) else None,
            "height": original_info.get("height") if isinstance(original_info, dict) and isinstance(original_info.get("height"), int) else None,
        })
    return normalized


def normalize_tweet(tweet):
    user = getattr(tweet, "user", None)
    screen_name = getattr(user, "screen_name", None)
    raw_payload = getattr(tweet, "_data", None)
    legacy = raw_payload.get("legacy") if isinstance(raw_payload, dict) else None
    tweet_id = str(getattr(tweet, "id", "") or "").strip()
    text = str(getattr(tweet, "full_text", None) or getattr(tweet, "text", "") or "").strip()
    if isinstance(raw_payload, dict):
        article_text = extract_article_text(raw_payload)
        if article_text and not has_substantive_text(text):
            text = article_text
    tweet_url = ""
    if tweet_id:
        tweet_url = f"https://x.com/{screen_name}/status/{tweet_id}" if screen_name else f"https://x.com/i/status/{tweet_id}"
    return {
        "tweet_id": tweet_id,
        "tweet_url": tweet_url,
        "author_handle": f"@{screen_name}" if screen_name else None,
        "text": text,
        "lang": getattr(tweet, "lang", None),
        "like_count": safe_int(getattr(tweet, "favorite_count", None)) or safe_int(getattr(tweet, "like_count", None)) or safe_int(legacy.get("favorite_count") if isinstance(legacy, dict) else None),
        "retweet_count": safe_int(getattr(tweet, "retweet_count", None)) or safe_int(legacy.get("retweet_count") if isinstance(legacy, dict) else None),
        "reply_count": safe_int(getattr(tweet, "reply_count", None)) or safe_int(legacy.get("reply_count") if isinstance(legacy, dict) else None),
        "view_count": safe_int(getattr(tweet, "view_count", None)) or safe_int(getattr(tweet, "views", None)) or safe_int(legacy.get("view_count") if isinstance(legacy, dict) else None),
        "created_at": str(getattr(tweet, "created_at_datetime", "") or ""),
        "is_reply": bool(getattr(tweet, "in_reply_to_status_id", None)),
        "is_retweet": bool(getattr(tweet, "retweeted_tweet", None)),
        "media": extract_media_items(raw_payload) if isinstance(raw_payload, dict) else [],
    }


def visit_tweet_nodes(client, node, tweet_id, seen):
    if not isinstance(node, dict):
        return None
    tweet = tweet_from_data(client, node)
    if tweet is not None:
        current_id = str(getattr(tweet, "id", ""))
        if current_id and current_id not in seen:
            seen.add(current_id)
            if current_id == tweet_id:
                return normalize_tweet(tweet)
    for key in ("content", "item", "itemContent"):
        value = node.get(key)
        if isinstance(value, dict):
            found = visit_tweet_nodes(client, value, tweet_id, seen)
            if found:
                return found
    for key in ("items", "moduleItems"):
        value = node.get(key)
        if isinstance(value, list):
            for item in value:
                found = visit_tweet_nodes(client, item, tweet_id, seen)
                if found:
                    return found
    return None


async def fetch_tweet(params):
    client = build_client(params["cookie_file"])
    try:
        tweet_id = str(params.get("tweet_id") or "").strip()
        if not tweet_id:
            raise ValueError("tweet_id is required")
        response, _ = await client.gql.tweet_detail(tweet_id, None)
        entry_groups = find_dict(response, "entries", find_one=True)
        entries = entry_groups[0] if entry_groups else []
        seen = set()
        for entry in entries:
            found = visit_tweet_nodes(client, entry, tweet_id, seen)
            if found:
                return {"items": [found], "next_cursor": None}
        raise ValueError(f"tweet {tweet_id} was not found or is not visible to this session")
    finally:
        await close_client(client)


async def fetch_user(params):
    client = build_client(params["cookie_file"])
    try:
        handle = str(params["handle"]).strip().lstrip("@")
        if not handle:
            raise ValueError("handle is required")
        user = await client.get_user_by_screen_name(handle)
        requested = max(1, min(int(params.get("max_tweets", 30)), 200))
        cursor = params.get("cursor")
        result = await client.get_user_tweets(user.id, "Tweets", count=requested, cursor=cursor)
        items = []
        seen_ids = set()
        current = result
        while current and len(items) < requested:
            for tweet in list(current):
                tweet_id = str(getattr(tweet, "id", ""))
                if tweet_id and tweet_id in seen_ids:
                    continue
                if tweet_id:
                    seen_ids.add(tweet_id)
                items.append(normalize_tweet(tweet))
                if len(items) >= requested:
                    break
            next_cursor = getattr(current, "next_cursor", None)
            if len(items) >= requested or not next_cursor:
                break
            current = await current.next()
        return {"items": items[:requested], "next_cursor": getattr(current, "next_cursor", None)}
    finally:
        await close_client(client)


async def fetch_list(params):
    client = build_client(params["cookie_file"])
    try:
        list_id = str(params.get("list_id") or "").strip()
        if not list_id:
            raise ValueError("list_id is required")
        requested = max(1, min(int(params.get("max_tweets", 30)), 200))
        cursor = params.get("cursor")
        result = await client.get_list_tweets(list_id, count=min(requested, 100), cursor=cursor)
        items = []
        seen_ids = set()
        current = result
        while current and len(items) < requested:
            for tweet in list(current):
                tweet_id = str(getattr(tweet, "id", ""))
                if tweet_id and tweet_id in seen_ids:
                    continue
                if tweet_id:
                    seen_ids.add(tweet_id)
                items.append(normalize_tweet(tweet))
                if len(items) >= requested:
                    break
            next_cursor = getattr(current, "next_cursor", None)
            if len(items) >= requested or not next_cursor:
                break
            current = await current.next()
        return {"items": items[:requested], "next_cursor": getattr(current, "next_cursor", None)}
    finally:
        await close_client(client)


ACTIONS = {
    "fetch_tweet": fetch_tweet,
    "fetch_list": fetch_list,
    "fetch_user": fetch_user,
}


async def main():
    if len(sys.argv) > 1:
        raw = Path(sys.argv[1]).expanduser().read_text(encoding="utf-8")
    else:
        raw = sys.stdin.read()
    try:
        command = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(json.dumps({"error": f"Invalid JSON input: {exc}"}), flush=True)
        sys.exit(1)

    action = command.get("action")
    params = command.get("params", {})
    if action not in ACTIONS:
        print(json.dumps({"error": f"Unknown action: {action}"}), flush=True)
        sys.exit(1)

    try:
        result = await ACTIONS[action](params)
        print(json.dumps(result, ensure_ascii=False, default=str), flush=True)
    except Exception as exc:
        print(json.dumps({"error": str(exc)}), flush=True)
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
