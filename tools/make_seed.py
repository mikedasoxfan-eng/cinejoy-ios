"""Export selected public title metadata from the retained REA capture.

Only descriptive fields go into the app; no request URLs, API keys, user data,
media files or resolver responses are copied.
"""
import base64
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
capture = root.parent / "cinejoy-analysis" / "initial-capture.json"
evidence = json.loads(capture.read_text(encoding="utf-8"))
events = evidence["normalized_result"]["events"]["items"]
requests = {e["transaction_id"]: e for e in events if e["kind"] == "request"}
groups = {}
individuals = []

def title(item, kind=None):
    kind = item.get("media_type", kind or ("tv" if "name" in item else "movie"))
    if kind not in ("movie", "tv") or item.get("adult") or not item.get("poster_path"):
        return None
    name = item.get("title") or item.get("name")
    if not name or not item.get("id"):
        return None
    year = (item.get("release_date") or item.get("first_air_date") or "")[:4]
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return dict(tmdbID=item["id"], kind=kind, name=name, year=year,
                poster="https://image.tmdb.org/t/p/w500" + item["poster_path"],
                backdrop="https://image.tmdb.org/t/p/w1280" + (item.get("backdrop_path") or item["poster_path"]),
                overview=item.get("overview", ""),
                rating=f'{item["vote_average"]:.1f}' if item.get("vote_average") else "",
                path=f'/{"series" if kind == "tv" else "movie"}/{item["id"]}-{slug}-{year}'.rstrip("-"))

for event in events:
    if event["kind"] != "network-content" or event["phase"] != "response" or event["body"]["state"] != "captured":
        continue
    request = requests.get(event["transaction_id"], {})
    url = request.get("url", {}).get("url", "")
    if not url.startswith("https://api.themoviedb.org/3/"):
        continue
    try:
        data = json.loads(base64.b64decode(event["body"]["content"]))
    except (ValueError, KeyError):
        continue
    if "results" in data:
        kind = "tv" if "/tv" in url else "movie"
        values = [t for item in data["results"] if (t := title(item, kind))]
        if "/trending/movie/" in url: groups["Movie night"] = values
        elif "/trending/tv/" in url: groups["Shows to get into"] = values
        elif "/movie/top_rated" in url: groups["Great movies"] = values
        elif "/tv/top_rated" in url: groups["Great television"] = values
    elif "id" in data:
        if value := title(data): individuals.append(value)

seen = {t["kind"] + str(t["tmdbID"]) for titles in groups.values() for t in titles}
curated = [t for t in individuals if t["kind"] + str(t["tmdbID"]) not in seen]
if curated: groups["Worth another look"] = curated
payload = dict(titles=[], shelves=[dict(name=name, titles=titles) for name, titles in groups.items() if titles], episodes=[], seasons=[])
destination = root / "Resources" / "CatalogSeed.json"
destination.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Saved {sum(len(s['titles']) for s in payload['shelves'])} titles across {len(payload['shelves'])} shelves")
