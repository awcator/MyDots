"""Local model order for the claudeload chooser. No network access."""

import json
import re
from pathlib import Path


_DATA_FILE = Path(__file__).with_name("model_ranking.json")
_EFFORT_SUFFIXES = (
    "-contributor-free", "-priority", "-lightning", "-fast", "-thinking", "-1m",
    "-minimal", "-medium", "-xhigh", "-tiered", "-high",
    "-none", "-low", "-max", "-ultra", "-500k", "-free",
    "-nvfp4", "-fp8", "-q4-k-m", "-q5-k-m", "-q8-0",
    "-iq4-xs", "-iq3-s-imat", "-preview",
)
_DATE_SUFFIX = re.compile(
    r"-(?:20\d{2}(?:-\d{2}-\d{2}|\d{4})|"
    r"(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01]))$"
)
_TOKEN = re.compile(r"(?<![a-z0-9])(?:%s)(?![a-z0-9])")
_GROUPS = {
    "unknown": "Unknown / new models · unranked",
    "coding": "Coding models · strongest first",
    "known": "Known coding models · strength not rated",
    "route": "🔀 Automatic routes · model varies",
    "vision": "👁️ Vision models",
    "image": "🎨 Image models",
    "video": "🎬 Video models",
    "audio": "🎧 Audio models",
    "no_tools": "🧩 Models without tool calling",
    "other": "🧩 Other non-coding models",
}
_GROUP_ORDER = {name: index for index, name in enumerate(_GROUPS)}


def _natural_key(value):
    return tuple((0, int(part)) if part.isdigit() else (1, part.casefold())
                 for part in re.split(r"(\d+)", value))


def _normalize(value):
    value = value.casefold().rsplit("/", 1)[-1]
    value = re.sub(r"\s*\([^)]*\)", "", value)
    value = re.sub(r"[\s_:]+", "-", value)
    value = re.sub(r"(?<=\d)\.(?=\d)", "-", value)
    value = re.sub(r"^(gpt|gemma|haiku|opus|sonnet)(?=\d)", r"\1-", value)
    value = re.sub(r"^claude-(\d+(?:-\d+)?)-(opus|sonnet|haiku)(?=$|-)",
                   r"claude-\2-\1", value)
    value = re.sub(r"^(opus|sonnet|haiku)-", r"claude-\1-", value)
    value = re.sub(r"^gpt-4-o(?=$|-)", "gpt-4o", value)
    return value.strip("-")


def _model_candidates(value):
    value = _normalize(value)
    for prefix in ("openrouter-", "together-"):
        if value.startswith(prefix):
            value = _normalize(value[len(prefix):])
            break
    while value:
        yield value
        without_date = _DATE_SUFFIX.sub("", value)
        if without_date != value:
            value = without_date
            continue
        suffix = next((part for part in _EFFORT_SUFFIXES if value.endswith(part)), None)
        if suffix is None:
            return
        value = value[:-len(suffix)]


def _contains(value, words):
    return bool(re.search(_TOKEN.pattern % words, value))


def _kind(model_id, status):
    value = _normalize(model_id)
    if value == "codex-auto-review":
        return "other", "🧩"
    if model_id.casefold().startswith("aihorde/"):
        return "image", "🎨"
    if _contains(value, "video|veo|sora|seedance|runway"):
        return "video", "🎬"
    if _contains(value, "image|images|imagen|flux|sdxl|diffusion|dall-e|"
                        "nano-banana|midjourney|ideogram|recraft|seedream|inpainting"):
        return "image", "🎨"
    if _contains(value, "audio|speech|tts|voice|music|whisper|transcribe|sound"):
        return "audio", "🎧"
    if (_contains(value, "vision|vl") or
            re.search(r"(?:^|-)glm-\d+-\d+v(?:$|-)", value)):
        return "vision", "👁️"
    if "no tool calling" in status.casefold():
        return "no_tools", "🧩"
    if (_contains(value, "embedding|embeddings|embed|rerank|moderation|"
                        "search|sonar|document|scholar|social") or
            "non-text" in status.casefold()):
        return "other", "🧩"
    return "coding", ""


def order_models(items):
    """Sort picker rows; preserve each provider's original selectable model ID."""
    try:
        data = json.loads(_DATA_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {"coding_order": [], "aliases": {}}
    ranks = {_normalize(model): index for index, model in enumerate(data.get("coding_order", []))}
    aliases = {_normalize(key): _normalize(value)
               for key, value in data.get("aliases", {}).items()}
    known = {_normalize(model) for model in data.get("known_unranked", [])}

    def decorated(row):
        model_id, title, status = row
        kind, icon = _kind(model_id, status)
        if kind != "coding":
            group = kind
            rank = len(ranks)
        elif (model_id.startswith("auto/") or
              model_id.rsplit("/", 1)[-1] == "auto" or
              model_id.startswith("aug/prism-")):
            group, rank = "route", len(ranks)
        else:
            rank = len(ranks)
            group = "unknown"
            matches = []
            for source in (model_id, title):
                for candidate in _model_candidates(source):
                    canonical = aliases.get(candidate, candidate)
                    if canonical in ranks:
                        matches.append((canonical.count("-"), ranks[canonical]))
                        break
                    if canonical in known and group == "unknown":
                        group = "known"
            if matches:
                rank = min(matches, key=lambda match: (-match[0], match[1]))[1]
                group = "coding"
        item = (model_id, title, status, icon, _GROUPS[group])
        return (_GROUP_ORDER[group], rank, _natural_key(model_id)), item

    return [item for _, item in sorted(map(decorated, items), key=lambda entry: entry[0])]
