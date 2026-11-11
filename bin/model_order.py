"""Local model order for the claudeload chooser. No network access."""

import json
import re
from pathlib import Path


_DATA_FILE = Path(__file__).with_name("model_ranking.json")
_EFFORT_SUFFIXES = (
    "-priority", "-lightning", "-fast", "-thinking", "-1m",
    "-minimal", "-medium", "-xhigh", "-tiered", "-high",
    "-none", "-low", "-max",
)
_DATE_SUFFIX = re.compile(r"-20\d{2}-\d{2}-\d{2}$")
_TOKEN = re.compile(r"(?<![a-z0-9])(?:%s)(?![a-z0-9])")
_GROUPS = (
    "Unknown / new models · unranked",
    "Coding models · strongest first",
    "👁️ Vision models",
    "🎨 Image models",
    "🎬 Video models",
    "🎧 Audio models",
    "🧩 Other non-coding models",
)


def _natural_key(value):
    return tuple((0, int(part)) if part.isdigit() else (1, part.casefold())
                 for part in re.split(r"(\d+)", value))


def _normalize(value):
    value = value.casefold().rsplit("/", 1)[-1].replace("_", "-")
    value = re.sub(r"(?<=\d)\.(?=\d)", "-", value)
    return value.replace(":", "-")


def _model_candidates(model_id):
    value = _normalize(model_id)
    yield value
    while True:
        without_date = _DATE_SUFFIX.sub("", value)
        if without_date != value:
            value = without_date
        else:
            suffix = next((part for part in _EFFORT_SUFFIXES if value.endswith(part)), None)
            if suffix is None:
                return
            value = value[:-len(suffix)]
        yield value


def _contains(value, words):
    return bool(re.search(_TOKEN.pattern % words, value))


def _kind(model_id, status):
    value = _normalize(model_id)
    if model_id.casefold().startswith("aihorde/"):
        return 3, "🎨", "image"
    if _contains(value, "video|veo|sora|seedance|runway"):
        return 4, "🎬", "video"
    if _contains(value, "image|images|imagen|flux|sdxl|diffusion|dall-e|"
                        "nano-banana|midjourney|ideogram|recraft|seedream|inpainting"):
        return 3, "🎨", "image"
    if _contains(value, "audio|speech|tts|voice|music|whisper|transcribe|sound"):
        return 5, "🎧", "audio"
    if (_contains(value, "vision|vl") or
            re.search(r"(?:^|-)glm-\d+-\d+v(?:$|-)", value)):
        return 2, "👁️", "vision"
    if (_contains(value, "embedding|embeddings|embed|rerank|moderation|"
                        "search|document|scholar|social") or
            "non-text" in status.casefold()):
        return 6, "🧩", "other"
    return 0, "", "coding"


def order_models(items):
    """Sort picker rows; preserve each provider's original selectable model ID."""
    try:
        data = json.loads(_DATA_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {"coding_order": [], "aliases": {}}
    ranks = {_normalize(model): index for index, model in enumerate(data.get("coding_order", []))}
    aliases = {_normalize(key): _normalize(value)
               for key, value in data.get("aliases", {}).items()}

    def decorated(row):
        model_id, title, status = row
        kind_order, icon, _ = _kind(model_id, status)
        if kind_order:
            group = kind_order
            rank = len(ranks)
        else:
            rank = len(ranks)
            for candidate in _model_candidates(model_id):
                canonical = candidate
                canonical = aliases.get(canonical, canonical)
                if canonical in ranks:
                    rank = ranks[canonical]
                    break
            group = 1 if rank < len(ranks) else 0
        item = (model_id, title, status, icon, _GROUPS[group])
        return (group, rank, _natural_key(model_id)), item

    return [item for _, item in sorted(map(decorated, items), key=lambda entry: entry[0])]
