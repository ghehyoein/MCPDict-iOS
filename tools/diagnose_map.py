import subprocess,sys,time
for _ in range(240):
    result=subprocess.run(["pgrep","-x","MCPDictIOS"],capture_output=True,text=True)
    if result.returncode == 0:
        pid=result.stdout.splitlines()[-1]
        break
    time.sleep(2)
else:
    raise SystemExit("App not found")
for i in range(3):
    time.sleep(20)
    subprocess.run(["sample",pid,"5","1","-file",f"dense-sample-{i}.txt"],check=False)
    subprocess.run(["xcrun","simctl","io",sys.argv[1],"screenshot",f"dense-screen-{i}.png"],check=False)
