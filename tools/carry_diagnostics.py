from pathlib import Path
import json, os, subprocess
tag=os.environ["RELEASE_TAG"]
repo=os.environ["GITHUB_REPOSITORY"]
prior=Path("prior-diagnostics"); prior.mkdir(exist_ok=True)
def gh(*args):
 return subprocess.run(["gh",*args],check=False,capture_output=True,text=True)
latest=gh("api",f"repos/{repo}/releases/latest","--jq",".tag_name").stdout.strip()
got=gh("release","download",latest,"--pattern","diagnostics.json","--pattern","upstream-warnings.txt","--dir",str(prior))
if got.returncode or not all((prior/name).is_file() for name in ("diagnostics.json", "upstream-warnings.txt")):
 fallback="data-3cf11dfc9125-c6566da54634"
 subprocess.run(["gh","release","download",fallback,"--pattern","manifest.json","--pattern","upstream-warnings.txt","--dir",str(prior),"--clobber"],check=True)
 source=json.loads((prior/"manifest.json").read_text())["sourceCommit"]
else:
 source=json.loads((prior/"diagnostics.json").read_text())["sourceCommit"]
out=Path("dist")
(out/"upstream-warnings.txt").write_bytes((prior/"upstream-warnings.txt").read_bytes())
(out/"diagnostics.json").write_text(json.dumps({"sourceCommit":source,"diagnosticsProfile":"upstream-c-v1","diagnosticsURL":f"https://github.com/{repo}/releases/download/{tag}/upstream-warnings.txt"},indent=2))

