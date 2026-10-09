#!/usr/bin/env python3
"""Build an unsaved, isolated tutorial overlay for the authored native place.

The supplied Rojo rbxlx contains code; the opened authored place supplies maps,
tools and UI assets. This command only writes a local installer and JSON payload.
It never publishes, saves a place, or selects a real persistence backend.
"""
import argparse
import json
from pathlib import Path
import re
import uuid
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PLACE_ID = 119874582058419
UNIVERSE_ID = 9667193329
STORE_LOOKUP = re.compile(r"game:GetService\(\s*(['\"])DataStoreService\1\s*\)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8765, help="Loopback payload HTTP server port")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    namespace = "TutorialAudit_" + uuid.uuid4().hex[:8]
    backend = 'require(game:GetService("ServerScriptService"):WaitForChild("BetaAuditBackend"))'
    payload = [{"Path": ["ServerScriptService", "BetaAuditBackend"], "Class": "ModuleScript",
                "Source": (ROOT / "scripts/studio-backend.luau").read_text()}]
    flags = {"mock": False, "preview": False}

    def walk(item, path):
        props = item.find("Properties")
        if props is None:
            raise ValueError("Rojo item has no properties")
        name = props.find("string[@name='Name']")
        if name is None or not name.text:
            raise ValueError("Rojo item has no name")
        current = path + [name.text]
        if len(current) == 1:
            for child in item.findall("Item"):
                walk(child, current)
            return
        source_node = props.find("*[@name='Source']")
        source = source_node.text if source_node is not None else None
        if source is not None:
            source = STORE_LOOKUP.sub(lambda _: backend, source)
            if current == ["ReplicatedStorage", "Modules", "DataConfig"]:
                source, count = re.subn(r"UseMockProfiles\s*=\s*false", "UseMockProfiles = true", source)
                if count != 1:
                    raise ValueError("Expected one explicit UseMockProfiles=false in source DataConfig")
                flags["mock"] = True
                for old, new in (("PlayerData_v1.0.2_MainData", namespace + "_Profiles"),
                                 ("PlayerVIP_v1_TESTING", namespace + "_VIP"),
                                 ("PurchaseReceipts_v1", namespace + "_Receipts")):
                    source = source.replace(old, new)
            if current == ["ReplicatedStorage", "Modules", "TutorialConfig"]:
                source, count = re.subn(r"EnableSoloPreview\s*=\s*false", "EnableSoloPreview = true", source)
                if count != 1:
                    raise ValueError("Expected one explicit EnableSoloPreview=false in source TutorialConfig")
                flags["preview"] = True
            if STORE_LOOKUP.search(source):
                raise ValueError("A source DataStoreService lookup escaped replacement")
        enabled = item.attrib["class"] in ("Script", "LocalScript") and current[0] == "ServerScriptService"
        # All ordinary client/character scripts stay disabled. A single local
        # helper constructs the new UI without duplicate startup controllers.
        payload.append({"Path": current, "Class": item.attrib["class"], "Source": source, "Enabled": enabled})
        for child in item.findall("Item"):
            walk(child, current)

    for service in ET.parse(args.model).getroot().findall("Item"):
        walk(service, [])
    if not all(flags.values()):
        raise ValueError("The source model must contain both tutorial and data config modules")
    payload.extend([
        {"Path": ["ReplicatedStorage", "TutorialVisualAudit"], "Class": "RemoteEvent", "Source": None},
        {"Path": ["ServerScriptService", "TutorialNativeTests"], "Class": "Script", "Enabled": True,
         "Source": (ROOT / "scripts/studio-tutorial-server-tests.luau").read_text()},
        {"Path": ["StarterPlayer", "StarterPlayerScripts", "TutorialNativeUI"], "Class": "LocalScript", "Enabled": True,
         "Source": (ROOT / "scripts/studio-tutorial-ui.luau").read_text()},
    ])
    json_path = args.output.with_suffix(".json")
    url = f"http://127.0.0.1:{args.port}/{json_path.name}"
    lines = [
        "local Http=game:GetService('HttpService')",
        "local Run=game:GetService('RunService')",
        f"assert(Run:IsStudio() and game.PlaceId=={PLACE_ID} and game.GameId=={UNIVERSE_ID},'Open the authored place in Studio; this isolated overlay must never run in a live server')",
        "Http.HttpEnabled=true",
        "local payload=Http:JSONDecode(Http:GetAsync(" + json.dumps(url) + "))",
        "for _,item in ipairs(game:GetDescendants()) do if item:IsA('BaseScript') then item.Enabled=false end end",
        "for _,item in ipairs(game:GetService('StarterGui'):GetChildren()) do if item:IsA('ScreenGui') then item.Enabled=false end end",
        "local SS=game:GetService('ServerStorage')",
        "local fixture='authored Studs'; local alias=false",
        "if not SS:FindFirstChild('Studs') then local original=SS:FindFirstChild('Classic ROBLOX'); assert(original and (original:IsA('Model') or original:IsA('Folder')),'No Studs or Classic ROBLOX native test template'); local map=original:Clone(); assert(map,'Native map must be Archivable'); map.Name='Studs'; for _,part in ipairs(map:GetDescendants()) do if part:IsA('BasePart') then part.CFrame+=Vector3.new(0,2000,0) end end; map.Parent=SS; fixture='Classic ROBLOX test alias'; alias=true end",
        "local RS=game:GetService('ReplicatedStorage'); RS:SetAttribute('TutorialTestMapFixture',fixture); RS:SetAttribute('TutorialTestMapAlias',alias)",
        "local function put(entry) local node=game; for i,name in ipairs(entry.Path) do local old=node:FindFirstChild(name); if not old or i==#entry.Path and old.ClassName~=entry.Class then local fresh=Instance.new(i==#entry.Path and entry.Class or 'Folder'); fresh.Name=name; if old then for _,child in ipairs(old:GetChildren()) do child.Parent=fresh end; old:Destroy() end; fresh.Parent=node; old=fresh end; node=old end; if entry.Source then node.Source=entry.Source end; if node:IsA('BaseScript') then node.Enabled=entry.Enabled==true end; return node end",
        "for _,entry in ipairs(payload) do put(entry) end",
        "assert(require(RS.Modules.DataConfig).UseMockProfiles==true,'Mock profiles were not enabled')",
        "assert(require(RS.Modules.TutorialConfig).Studio.EnableSoloPreview==true,'Preview was not enabled')",
        "print('TUTORIAL_OVERLAY_INSTALLED '..#payload..' MAP_FIXTURE '..fixture)",
        "task.wait(1)",
        "local ok,result=pcall(function() return game:GetService('StudioTestService'):ExecuteMultiplayerTestAsync(1,{Players=1,MapFixture=fixture,MapAlias=alias,NativeOverlay=true}) end)",
        "print('STAB_TUTORIAL_NATIVE_REPORT '..Http:JSONEncode({Started=ok,Result=ok and result or tostring(result)}))",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines) + "\n")
    json_path.write_text(json.dumps(payload, ensure_ascii=True))
    print(f"Wrote unsaved isolated tutorial installer {args.output} and payload {json_path}")


if __name__ == "__main__":
    main()
