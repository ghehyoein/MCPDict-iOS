import subprocess, sys, time
from pathlib import Path
for i in range(100):
    time.sleep(15)
    result = subprocess.run(["pgrep", "-x", "MCPDictIOS"], capture_output=True, text=True)
    if result.returncode != 0:
        continue
    pid = result.stdout.splitlines()[-1]
    subprocess.run(["sample", pid, "3", "1", "-file", f"dense-sample-{i:03}-{pid}.txt"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "io", sys.argv[1], "screenshot", f"dense-screen-{i:03}-{pid}.png"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
