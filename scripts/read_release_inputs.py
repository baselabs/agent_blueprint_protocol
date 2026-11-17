"""Read the first-listed toolchain and the equal source package versions for CI."""

import json
import os
import re
from pathlib import Path


tools = {}
for line in Path(".tool-versions").read_text().splitlines():
    fields = line.split("#", 1)[0].split()
    if len(fields) > 1:
        tools.setdefault(fields[0], fields[1])

patterns = {
    "elixir": r"\d+\.\d+\.\d+-otp-\d+",
    "erlang": r"\d+\.\d+\.\d+",
    "nodejs": r"\d+\.\d+\.\d+",
}
for tool, pattern in patterns.items():
    if not re.fullmatch(pattern, tools.get(tool, "")):
        raise SystemExit(f"Expected an exact default {tool} pin in .tool-versions")

if tools["elixir"].split("-otp-")[1] != tools["erlang"].split(".")[0]:
    raise SystemExit("Default Elixir build and Erlang/OTP major disagree")

versions = re.findall(r'^\s*@version "([^"\n]+)"', Path("mix.exs").read_text(), re.M)
if len(versions) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", versions[0]):
    raise SystemExit("Expected one exact release version in mix.exs")
version = versions[0]
if json.loads(Path("package.json").read_text())["version"] != version:
    raise SystemExit("mix.exs and package.json versions disagree")

values = {"elixir": tools["elixir"], "otp": tools["erlang"], "node": tools["nodejs"]}
with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8", newline="\n") as output:
    for name, value in {**values, "version": version}.items():
        output.write(f"{name}={value}\n")
with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8", newline="\n") as environment:
    environment.write(f"VERSION={version}\n")
