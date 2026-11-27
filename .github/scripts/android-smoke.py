import pathlib
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

wear = sys.argv[1] == "wear"
artifact = "Jot-WearOS" if wear else "Jot-Android"
package = "au.com.asherpereira.jot"
activity = package + (".watch.WatchActivity" if wear else ".MainActivity")
proof = pathlib.Path("proof")
proof.mkdir(exist_ok=True)

def adb(*args):
    return subprocess.check_output(["adb", *args], text=True).strip()

def hierarchy():
    adb("shell", "uiautomator", "dump", "/sdcard/jot-test.xml")
    raw = adb("shell", "cat", "/sdcard/jot-test.xml")
    (proof / "screen.xml").write_text(raw)
    return ET.fromstring(raw).iter("node")

def lookup(label=None, edit=False):
    for node in hierarchy():
        a = node.attrib
        if edit and a.get("class") == "android.widget.EditText":
            return a
        if label and any(label == s.strip() for key in ("text", "content-desc") for s in a.get(key, "").splitlines()):
            return a
    return None

def find(label=None, edit=False, scroll=False):
    for _ in range(12):
        match = lookup(label, edit)
        if match is not None:
            return match
        if scroll:
            width, height = map(int, re.findall(r"(\d+)x(\d+)", adb("shell", "wm", "size"))[-1])
            adb("shell", "input", "swipe", str(width//2), str(height*3//4), str(width//2), str(height//3), "300")
        time.sleep(.5)
    raise RuntimeError(f"Control missing: {label or 'text field'}")

def tap(node):
    x1,y1,x2,y2 = map(int, re.findall(r"\d+", node["bounds"]))
    adb("shell", "input", "tap", str((x1+x2)//2), str((y1+y2)//2))

apk = next((pathlib.Path("downloads") / artifact).glob("*.apk"))
adb("install", "-r", str(apk))
print(adb("shell", "am", "start", "-W", "-n", f"{package}/{activity}"), flush=True)
time.sleep(5)
print("Jot PID", adb("shell", "pidof", package), flush=True)
if wear:
    find("Up next")
else:
    tap(find("Capture"))
    tap(find(edit=True))
    adb("shell", "input", "text", "Maths%shomework%sdue%sthis%sFriday")
    if re.search(r'(mInputShown|isInputViewShown)=true', adb("shell", "dumpsys", "input_method")):
        adb("shell", "input", "keyevent", "4")
    tap(find("Review local draft"))
    tap(find("Save homework", scroll=True))
    find("Maths homework")
    adb("shell", "am", "force-stop", package)
    adb("shell", "am", "start", "-W", "-n", f"{package}/{activity}")
    find("Maths homework")
with (proof / f"{artifact}.png").open("wb") as f:
    subprocess.run(["adb","exec-out","screencap","-p"],stdout=f,check=True)
print("Verified watch landing screen" if wear else "Verified capture, save and persistence across restart")
