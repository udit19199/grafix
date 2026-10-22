#!/usr/bin/env python3
"""Run after swift build --product grafix-mcp, from the repository root."""
import json
import subprocess
import select
import tempfile

with tempfile.TemporaryDirectory(prefix="grafix-mcp-") as directory:
    process = subprocess.Popen(
        [".build/debug/grafix-mcp", "--directory", directory],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    )
    counter = 0

    def request(method, params=None):
        global counter
        counter += 1
        process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": counter, "method": method, "params": params or {}}) + "\n")
        process.stdin.flush()
        assert select.select([process.stdout], [], [], 5)[0], "MCP response timed out"
        response = json.loads(process.stdout.readline())
        assert response["id"] == counter, response
        return response

    def tool(name, arguments):
        result = request("tools/call", {"name": name, "arguments": arguments})["result"]
        if result.get("isError"):
            return result
        return json.loads(result["content"][0]["text"])

    assert request("initialize", {"protocolVersion": "2025-06-18"})["result"]["protocolVersion"] == "2025-06-18"
    process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
    process.stdin.flush()
    assert len(request("tools/list")["result"]["tools"]) == 4
    created = tool("create_scene", {"name": "smoke.excalidraw"})
    assert "revision" in created, created
    assert tool("create_scene", {"name": "smoke.excalidraw"})["isError"]
    patched = tool("patch_elements", {"name": "smoke.excalidraw", "expectedRevision": created["revision"], "patches": [{"id": "box", "type": "rectangle", "x": 0, "y": 0, "width": 100, "height": 80, "customData": {"preserve": True}}]})
    assert patched["scene"]["elements"][0]["customData"]["preserve"]
    assert tool("patch_elements", {"name": "smoke.excalidraw", "expectedRevision": created["revision"], "patches": []})["isError"]
    updated = tool("patch_elements", {"name": "smoke.excalidraw", "expectedRevision": patched["revision"], "patches": [{"id": "box", "x": 50}]})
    assert updated["scene"]["elements"][0]["customData"]["preserve"]
    assert tool("read_scene", {"name": "../outside.excalidraw"})["isError"]
    copied = tool("create_scene", {"name": "copy.excalidraw", "scene": updated["scene"]})
    assert copied["scene"]["elements"][0]["customData"]["preserve"]
    assert tool("list_drawings", {}) == ["copy.excalidraw", "smoke.excalidraw"]
    assert request("missing")["error"]["code"] == -32601
    process.stdin.write('not-json\n')
    process.stdin.flush()
    assert select.select([process.stdout], [], [], 5)[0], "Parse-error response timed out"
    assert json.loads(process.stdout.readline())["error"]["code"] == -32700
    process.stdin.close()
    assert process.wait(timeout=5) == 0
print("MCP smoke passed: initialize, notification, tools, revision conflict, preservation, path rejection, errors")
