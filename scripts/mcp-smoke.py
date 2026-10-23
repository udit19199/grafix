#!/usr/bin/env python3
"""Smoke test for grafix-mcp. Run from the repo root after:
  swift build --product grafix-mcp --scratch-path .build-mcp
Usage: python3 scripts/mcp-smoke.py [path/to/grafix-mcp]
Uses a temporary GRAFIX_ROOT; never touches ~/Documents/Grafix.
"""
import base64
import json
import os
import select
import subprocess
import sys
import tempfile

BINARY = sys.argv[1] if len(sys.argv) > 1 else ".build-mcp/debug/grafix-mcp"


def main():
    with tempfile.TemporaryDirectory(prefix="grafix-mcp-") as root:
        env = dict(os.environ, GRAFIX_ROOT=root)
        proc = subprocess.Popen(
            [BINARY, "--root", root], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, env=env)
        counter = [0]

        def rpc(method, params=None):
            counter[0] += 1
            proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": counter[0], "method": method, "params": params or {}}) + "\n")
            proc.stdin.flush()
            assert select.select([proc.stdout], [], [], 20)[0], f"timeout on {method}"
            response = json.loads(proc.stdout.readline())
            assert response["id"] == counter[0], response
            return response

        def call(name, arguments=None, expect_error=False):
            result = rpc("tools/call", {"name": name, "arguments": arguments or {}})["result"]
            assert bool(result.get("isError")) == expect_error, (name, result)
            block = result["content"][0]
            if block["type"] == "image":
                return block
            return block["text"] if expect_error else json.loads(block["text"]) if block["text"].lstrip().startswith(("{", "[")) else block["text"]

        # Protocol
        for version in ("2024-11-05", "2025-03-26", "2025-06-18"):
            assert rpc("initialize", {"protocolVersion": version})["result"]["protocolVersion"] == version
        assert "instructions" in rpc("initialize", {"protocolVersion": "1999"})["result"]
        proc.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        proc.stdin.flush()
        assert rpc("ping")["result"] == {}
        tools = rpc("tools/list")["result"]["tools"]
        names = [t["name"] for t in tools]
        for t in tools:
            assert t["inputSchema"]["additionalProperties"] is False, t["name"]
            assert t["description"], t["name"]
        print(f"{len(tools)} tools:", ", ".join(names))
        assert rpc("nope")["error"]["code"] == -32601

        # Workspace
        call("create_collection", {"name": "Smoke"})
        call("create_collection", {"name": "Smoke"}, expect_error=True)
        scene = call("create_scene", {"name": "Flow", "collectionId": "Smoke"})
        sid = scene["id"]
        assert sid == "Smoke/Flow", sid
        call("get_scene", {"sceneId": "Smoke/Nope"}, expect_error=True)

        # Edit: two labeled rectangles + bound arrow via tempIds (string-array form, like Excalidraw+)
        add = [
            {"tempId": "a", "type": "rectangle", "x": 100, "y": 100, "width": 180, "height": 90,
             "backgroundColor": "#a5d8ff", "roundness": {"type": 3}, "label": {"text": "Client"}},
            {"tempId": "b", "type": "rectangle", "x": 400, "y": 100, "width": 180, "height": 90,
             "label": {"text": "Server"}},
            {"tempId": "arrow", "type": "arrow", "x": 0, "y": 0,
             "startBinding": {"elementId": "a", "mode": "inside"},
             "endBinding": {"elementId": "b", "mode": "inside"}},
        ]
        edit = call("edit_scene_content", {"sceneId": sid, "add": json.dumps(add)})
        created = edit["created"]
        assert set(created) == {"a", "b", "arrow"}, edit
        assert not edit["warnings"], edit["warnings"]
        content = call("get_scene_content", {"sceneId": sid})
        by_id = {e["id"]: e for e in content["elements"]}
        arrow = by_id[created["arrow"]]
        assert arrow["startBinding"]["elementId"] == created["a"], arrow
        assert arrow["endBinding"]["elementId"] == created["b"], arrow
        assert sum(1 for e in content["elements"] if e["type"] == "text") == 2

        # Update (real array form) and delete
        call("edit_scene_content", {"sceneId": sid, "update": [{"id": created["b"], "backgroundColor": "#b2f2bb"}]})
        found = call("search_scene_content", {"sceneId": sid, "query": "server"})
        assert found["count"] == 1 and found["elements"][0]["backgroundColor"] == "#b2f2bb", found
        assert call("search_scene_content", {"sceneId": sid, "types": ["arrow"]})["count"] == 1
        call("edit_scene_content", {"sceneId": sid, "add": "not json"}, expect_error=True)
        call("edit_scene_content", {"sceneId": sid}, expect_error=True)

        # Slides
        s1 = call("create_slide", {"sceneId": sid, "title": "Intro", "presenterNotes": "- hello", "layout": "two-column"})
        s2 = call("create_slide", {"sceneId": sid, "title": "Outro"})
        assert set(s1["regions"]) == {"title", "left", "right"}, s1["regions"]
        assert s1["bounds"]["width"] == 854 and s2["slideNumber"] == 2
        call("edit_scene_content", {"sceneId": sid, "add": [
            {"type": "text", "x": s1["safeArea"]["x"], "y": s1["safeArea"]["y"], "text": "Hello", "fontSize": 40,
             "fontFamily": 7, "frameId": s1["frameId"]}]})
        call("update_slide", {"sceneId": sid, "frameId": s2["frameId"], "slideNumber": 1})
        slides = call("list_slides", {"sceneId": sid})["slides"]
        assert [s["name"] for s in slides] == ["Outro", "Intro"], slides
        assert slides[1]["elementCount"] == 1 and slides[1]["presenterNotes"] == "- hello", slides
        call("update_slide", {"sceneId": sid, "frameId": "nope", "title": "x"}, expect_error=True)

        # Image (1x1 PNG data URL)
        png = base64.b64encode(bytes.fromhex(
            "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
            "0000000d49444154789c6360f8cfc0f01f0005000201fb7c4ee30000000049454e44ae426082")).decode()
        img = call("add_image", {"sceneId": sid, "dataURL": "data:image/png;base64," + png, "x": 0, "y": 600, "width": 50})
        assert img["fileId"] and img["summary"]["width"] == 50, img
        content = call("get_scene_content", {"sceneId": sid})
        assert "dataURL" not in json.dumps(content["files"]), "dataURL leaked"

        # Editor state, metadata, rename, duplicate
        assert call("get_editor_state")["openSceneId"] is None
        meta = call("get_scene", {"sceneId": sid})
        assert len(meta["slides"]) == 2 and meta["elementCount"] > 5, meta
        moved = call("update_scene", {"sceneId": sid, "name": "Flow2"})
        sid = moved["id"]
        assert sid == "Smoke/Flow2", moved
        dup = call("duplicate_scene", {"sceneId": sid})
        assert dup["id"] == "Smoke/Flow2 copy", dup
        assert len(call("list_scenes")["scenes"]) == 2
        assert len(call("list_scenes", {"collectionId": "Smoke"})["scenes"]) == 2

        # Guides
        for g in ("read_diagram_format", "read_presentation_format", "read_freeform_format"):
            assert len(call(g)) > 500, g

        # Screenshot
        shot = call("take_screenshot", {"sceneId": sid, "maxWidth": 800})
        data = base64.b64decode(shot["data"])
        assert shot["mimeType"] == "image/png" and data[:8] == b"\x89PNG\r\n\x1a\n", "bad PNG"
        call("take_screenshot", {"sceneId": sid, "frameId": slides[1]["frameId"]})
        print(f"screenshot ok: {len(data)} bytes")

        # CLI render
        out = os.path.join(root, "out.png")
        subprocess.run([BINARY, "--root", root, "render", sid, out], check=True, capture_output=True)
        assert open(out, "rb").read(4) == b"\x89PNG"

        # Cleanup (Trash)
        call("delete_scene", {"sceneId": dup["id"]})
        call("delete_scene", {"sceneId": sid})
        assert call("list_scenes", {"collectionId": "Smoke"})["scenes"] == []
        call("update_collection", {"collectionId": "Smoke", "name": "Smoke2"})
        call("delete_collection", {"collectionId": "Smoke2"})
        assert [c["name"] for c in call("list_collections")["collections"]] == []

        # Malformed line
        proc.stdin.write("not-json\n")
        proc.stdin.flush()
        assert json.loads(proc.stdout.readline())["error"]["code"] == -32700
        proc.stdin.close()
        assert proc.wait(timeout=10) == 0
    print("MCP smoke passed")


main()
