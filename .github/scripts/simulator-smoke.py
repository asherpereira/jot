import json
import os
import pathlib
import re
import subprocess
import sys
import time

platform = sys.argv[1]
is_phone = platform == "iOS"
artifact = "Jot-iOS-Simulator" if is_phone else "Jot-watchOS-Simulator"
bundle = "au.com.asherpereira.jot" + ("" if is_phone else ".watchkitapp")
proof = pathlib.Path("proof")
proof.mkdir(exist_ok=True)

def sim(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True).strip()

def available():
    devices = json.loads(sim("list", "devices", "available", "-j"))["devices"]
    for runtime, items in sorted(devices.items(), reverse=True):
        if f"SimRuntime.{platform}-" not in runtime:
            continue
        for item in items:
            if (is_phone and "iPhone" in item["name"]) or (not is_phone and "Apple Watch" in item["name"]):
                return item["udid"]
    return None

device = available()
if device is None:
    subprocess.run(["xcodebuild", "-downloadPlatform", platform], check=True)
    device = available()
if device is None:
    runtimes = json.loads(sim("list", "runtimes", "-j"))["runtimes"]
    runtime = next(r for r in reversed(runtimes) if r.get("isAvailable") and f"SimRuntime.{platform}-" in r["identifier"])
    model = next(t for t in runtime["supportedDeviceTypes"] if ("iPhone" if is_phone else "Apple Watch") in t["name"])
    device = sim("create", "Jot smoke", model["identifier"], runtime["identifier"])
print(f"Booting {platform} simulator {device}", flush=True)
subprocess.run(["xcrun", "simctl", "boot", device], check=False)
sim("bootstatus", device, "-b")
package = next((pathlib.Path("downloads") / artifact).glob("*.zip"))
subprocess.run(["ditto", "-x", "-k", str(package), "unpacked"], check=True)
app = next(pathlib.Path("unpacked").glob("*.app"))
sim("install", device, str(app))
launched = sim("launch", device, bundle)
print(launched, flush=True)
pid = int(re.search(r": (\d+)", launched)[1])
if is_phone:
    container = sim("get_app_container", device, bundle, "data")
    subprocess.run([sys.executable, ".github/scripts/check-db.py", container], check=True)
time.sleep(6)
os.kill(pid, 0)
sim("io", device, "screenshot", str(proof / f"{platform}.png"))
print(f"{platform} installed and launched the packaged app")
