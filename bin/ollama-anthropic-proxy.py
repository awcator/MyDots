#!/usr/bin/env python3
"""
Proxy that translates Anthropic Messages API requests to Ollama's OpenAI-compatible API.
This lets Claude Code talk to local Ollama models.
Supports tool use (WebSearch, Bash, Read, etc.)

Usage:
    python ollama-anthropic-proxy.py [--port 8082] [--ollama-url http://localhost:11434] [--model llama3:instruct]

Then:
    claude-local
"""

import json
import sys
import uuid
import argparse
import requests
from flask import Flask, request, Response, stream_with_context, jsonify

app = Flask(__name__)

OLLAMA_BASE = "http://localhost:11434"
DEFAULT_MODEL = "llama3:instruct"


def convert_anthropic_tools_to_openai(tools):
    """Convert Anthropic tool definitions to OpenAI function-calling format."""
    if not tools:
        return None
    openai_tools = []
    for tool in tools:
        openai_tools.append({
            "type": "function",
            "function": {
                "name": tool.get("name", ""),
                "description": tool.get("description", ""),
                "parameters": tool.get("input_schema", {}),
            },
        })
    return openai_tools


def convert_anthropic_to_ollama(data):
    """Convert Anthropic Messages API format to Ollama/OpenAI chat format."""
    messages = []

    # System message
    system = data.get("system")
    if system:
        if isinstance(system, list):
            system_text = "\n".join(
                b.get("text", "") for b in system if b.get("type") == "text"
            )
        else:
            system_text = str(system)
        messages.append({"role": "system", "content": system_text})

    # Convert messages
    for msg in data.get("messages", []):
        role = msg.get("role", "user")
        content = msg.get("content")

        if isinstance(content, str):
            messages.append({"role": role, "content": content})
        elif isinstance(content, list):
            # Check for tool_use in assistant messages
            if role == "assistant":
                text_parts = []
                tool_calls = []
                for block in content:
                    if isinstance(block, str):
                        text_parts.append(block)
                    elif block.get("type") == "text":
                        text_parts.append(block.get("text", ""))
                    elif block.get("type") == "thinking":
                        text_parts.append(block.get("thinking", ""))
                    elif block.get("type") == "tool_use":
                        tool_calls.append({
                            "id": block.get("id", "call_" + uuid.uuid4().hex[:8]),
                            "type": "function",
                            "function": {
                                "name": block.get("name", ""),
                                "arguments": json.dumps(block.get("input", {})),
                            },
                        })
                m = {"role": "assistant"}
                if text_parts:
                    m["content"] = "\n".join(text_parts)
                else:
                    m["content"] = ""
                if tool_calls:
                    m["tool_calls"] = tool_calls
                messages.append(m)

            elif role == "user":
                # User messages may contain tool_result blocks
                for block in content:
                    if isinstance(block, str):
                        messages.append({"role": "user", "content": block})
                    elif block.get("type") == "text":
                        messages.append({"role": "user", "content": block.get("text", "")})
                    elif block.get("type") == "tool_result":
                        tool_call_id = block.get("tool_use_id", "")
                        result_content = block.get("content", "")
                        if isinstance(result_content, list):
                            result_content = "\n".join(
                                b.get("text", str(b)) for b in result_content
                            )
                        elif not isinstance(result_content, str):
                            result_content = str(result_content)
                        messages.append({
                            "role": "tool",
                            "tool_call_id": tool_call_id,
                            "content": result_content,
                        })
        else:
            messages.append({"role": role, "content": str(content) if content else ""})

    model = data.get("model", DEFAULT_MODEL)
    if "claude" in model.lower():
        model = DEFAULT_MODEL

    result = {
        "model": model,
        "messages": messages,
        "stream": data.get("stream", False),
    }

    # Convert tools
    tools = convert_anthropic_tools_to_openai(data.get("tools"))
    if tools:
        result["tools"] = tools

    if data.get("max_tokens"):
        result["options"] = {"num_predict": data["max_tokens"]}
    if data.get("temperature") is not None:
        result.setdefault("options", {})["temperature"] = data["temperature"]

    return result


def make_anthropic_response(ollama_resp, model):
    """Convert Ollama response to Anthropic Messages API format."""
    msg = ollama_resp.get("message", {})
    content_blocks = []
    stop_reason = "end_turn"

    # Check for tool calls
    tool_calls = msg.get("tool_calls", [])
    text = msg.get("content", "")

    if text:
        content_blocks.append({"type": "text", "text": text})

    if tool_calls:
        stop_reason = "tool_use"
        for tc in tool_calls:
            func = tc.get("function", {})
            args = func.get("arguments", "{}")
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except json.JSONDecodeError:
                    args = {"raw": args}
            content_blocks.append({
                "type": "tool_use",
                "id": tc.get("id", "toolu_" + uuid.uuid4().hex[:8]),
                "name": func.get("name", ""),
                "input": args,
            })

    if not content_blocks:
        content_blocks.append({"type": "text", "text": ""})

    return {
        "id": "msg_local_" + uuid.uuid4().hex[:10],
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": content_blocks,
        "stop_reason": stop_reason,
        "stop_sequence": None,
        "usage": {
            "input_tokens": ollama_resp.get("prompt_eval_count", 0),
            "output_tokens": ollama_resp.get("eval_count", 0),
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": 0,
        },
    }


def stream_anthropic_response(ollama_url, ollama_payload, model):
    """Stream Ollama response as Anthropic SSE events."""
    # message_start
    yield f"event: message_start\ndata: {json.dumps({'type': 'message_start', 'message': {'id': 'msg_local_stream', 'type': 'message', 'role': 'assistant', 'model': model, 'content': [], 'stop_reason': None, 'stop_sequence': None, 'usage': {'input_tokens': 0, 'output_tokens': 0, 'cache_creation_input_tokens': 0, 'cache_read_input_tokens': 0}}})}\n\n"

    ollama_payload["stream"] = True
    try:
        resp = requests.post(
            f"{ollama_url}/api/chat", json=ollama_payload, stream=True, timeout=300
        )
        total_tokens = 0
        full_text = ""
        tool_calls_acc = {}  # accumulate tool call fragments by index

        # Track if we've started a text block
        text_block_started = False
        # Track tool call blocks we've emitted
        tool_block_index = 0

        for line in resp.iter_lines():
            if not line:
                continue
            chunk = json.loads(line)
            msg = chunk.get("message", {})
            token = msg.get("content", "")
            chunk_tool_calls = msg.get("tool_calls", [])

            # Handle text tokens
            if token:
                if not text_block_started:
                    yield f"event: content_block_start\ndata: {json.dumps({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}})}\n\n"
                    text_block_started = True
                total_tokens += 1
                full_text += token
                yield f"event: content_block_delta\ndata: {json.dumps({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': token}})}\n\n"

            # Accumulate tool calls
            for tc in chunk_tool_calls:
                idx = tc.get("index", 0)
                if idx not in tool_calls_acc:
                    tool_calls_acc[idx] = {
                        "id": "toolu_" + uuid.uuid4().hex[:8],
                        "name": "",
                        "arguments": "",
                    }
                func = tc.get("function", {})
                if func.get("name"):
                    tool_calls_acc[idx]["name"] = func["name"]
                if func.get("arguments"):
                    tool_calls_acc[idx]["arguments"] += func["arguments"]

            if chunk.get("done"):
                break

        # Close text block if opened
        if text_block_started:
            yield f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': 0})}\n\n"
            tool_block_index = 1

        stop_reason = "end_turn"

        # Emit tool use blocks
        if tool_calls_acc:
            stop_reason = "tool_use"
            for idx in sorted(tool_calls_acc.keys()):
                tc = tool_calls_acc[idx]
                try:
                    args = json.loads(tc["arguments"]) if tc["arguments"] else {}
                except json.JSONDecodeError:
                    args = {"raw": tc["arguments"]}

                block_idx = tool_block_index
                tool_block_index += 1

                yield f"event: content_block_start\ndata: {json.dumps({'type': 'content_block_start', 'index': block_idx, 'content_block': {'type': 'tool_use', 'id': tc['id'], 'name': tc['name'], 'input': {}}})}\n\n"
                yield f"event: content_block_delta\ndata: {json.dumps({'type': 'content_block_delta', 'index': block_idx, 'delta': {'type': 'input_json_delta', 'partial_json': json.dumps(args)}})}\n\n"
                yield f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': block_idx})}\n\n"

        # If no text and no tools, emit empty text block
        if not text_block_started and not tool_calls_acc:
            yield f"event: content_block_start\ndata: {json.dumps({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}})}\n\n"
            yield f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': 0})}\n\n"

        # message_delta
        yield f"event: message_delta\ndata: {json.dumps({'type': 'message_delta', 'delta': {'stop_reason': stop_reason, 'stop_sequence': None}, 'usage': {'output_tokens': total_tokens}})}\n\n"

        # message_stop
        yield f"event: message_stop\ndata: {json.dumps({'type': 'message_stop'})}\n\n"

    except Exception as e:
        if not text_block_started:
            yield f"event: content_block_start\ndata: {json.dumps({'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}})}\n\n"
        yield f"event: content_block_delta\ndata: {json.dumps({'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': f'[Proxy error: {e}]'}})}\n\n"
        yield f"event: content_block_stop\ndata: {json.dumps({'type': 'content_block_stop', 'index': 0})}\n\n"
        yield f"event: message_delta\ndata: {json.dumps({'type': 'message_delta', 'delta': {'stop_reason': 'end_turn', 'stop_sequence': None}, 'usage': {'output_tokens': 0}})}\n\n"
        yield f"event: message_stop\ndata: {json.dumps({'type': 'message_stop'})}\n\n"


@app.route("/v1/messages", methods=["POST"])
def messages():
    data = request.get_json()
    ollama_payload = convert_anthropic_to_ollama(data)
    model = ollama_payload["model"]

    is_stream = data.get("stream", False)

    if is_stream:
        return Response(
            stream_with_context(
                stream_anthropic_response(OLLAMA_BASE, ollama_payload, model)
            ),
            content_type="text/event-stream",
        )
    else:
        resp = requests.post(
            f"{OLLAMA_BASE}/api/chat", json=ollama_payload, timeout=300
        )
        return jsonify(make_anthropic_response(resp.json(), model))


@app.route("/v1/models", methods=["GET"])
def list_models():
    return jsonify({
        "data": [
            {"id": DEFAULT_MODEL, "object": "model", "created": 0, "owned_by": "ollama"},
        ]
    })


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "ollama": OLLAMA_BASE, "model": DEFAULT_MODEL})


# Catch-all for unknown endpoints Claude Code might hit
@app.route("/", defaults={"path": ""}, methods=["GET", "POST", "PUT", "DELETE"])
@app.route("/<path:path>", methods=["GET", "POST", "PUT", "DELETE"])
def catch_all(path):
    # Log unknown requests for debugging
    app.logger.info(f"Unknown request: {request.method} /{path}")
    return jsonify({"error": f"Unknown endpoint: /{path}"}), 404


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Anthropic-to-Ollama proxy")
    parser.add_argument("--port", type=int, default=8082)
    parser.add_argument("--ollama-url", default="http://localhost:11434")
    parser.add_argument("--model", default="llama3:instruct")
    args = parser.parse_args()

    OLLAMA_BASE = args.ollama_url
    DEFAULT_MODEL = args.model

    print(f"Ollama Anthropic Proxy (with tool support)")
    print(f"  Ollama:  {OLLAMA_BASE}")
    print(f"  Model:   {DEFAULT_MODEL}")
    print(f"  Listen:  http://localhost:{args.port}")
    print(f"")
    print(f"Usage: claude-local")

    app.run(host="0.0.0.0", port=args.port, debug=False)
