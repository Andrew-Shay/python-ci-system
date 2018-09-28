#!/bin/bash
# Andrew Shay
# License MIT

FILE="./quick_test.py"
/bin/cat <<EOM >$FILE

import json
import os

# -- Get and save GitHub API Payload
github_data = json.loads(os.environ['payload'])
github_str = json.dumps(github_data, sort_keys=True, indent=4)

with open("github_payload.txt", "w", encoding="utf-8") as f:
    f.write(github_str)
    
# -- Print payload description
full_name = github_data['repository']['full_name']
clone_url = github_data['repository']['clone_url']
print("#"*60)
print(full_name)
print(clone_url)


# -- Determine if we want to operate on this payload
if 'after' in github_data and 'pull_request' in github_data:  # New commit
    commit = github_data['after']
    with open("commit.txt", "w", encoding="utf8") as f:
        f.write(commit)
    print(commit)
elif 'action' in github_data and github_data['action'] in ('opened', 'reopened'):  # Opened and Reopened Pull Requests
    commit = github_data['pull_request']['head']['ref']
    with open("commit.txt", "w", encoding="utf8") as f:
        f.write(commit)
    print(commit)

print("#"*60)

print(github_str)

EOM

FILE="./ci.py"
/bin/cat <<EOM >$FILE

import subprocess
import os
import sys
import configparser
import requests
import json
import base64
import shutil

def check_proc(p):
  if p.returncode:
      print(p.returncode)
      print(p.stdout)
      print(p.stderr)
      print(sys.exit(1))


# -- Get GitHub API Payload
github_data = json.loads(os.environ['payload'])


# -- GitHub creds
github_user = ""
github_password = ""


# -- Clone Repo
clone_url = github_data['pull_request']['base']['repo']['clone_url']
clone_url = clone_url.replace("https://", "")
clone_url = clone_url.replace("http://", "")
cmd = f"git clone https://{github_user}:{github_password}@{clone_url}"
p = subprocess.run(cmd, shell=True)
check_proc(p)


# -- Move repo contents up one level
folder_name = github_data['pull_request']['base']['repo']['name']
source = f'./{folder_name}/'
dest = './'
files = os.listdir(source)
for f in files:
    shutil.move(source+f, dest)


# -- Checkout branch or commit
with open("commit.txt", "r", encoding="utf-8") as f:
    commit = f.read().strip()
cmd = "git checkout {}".format(commit)
print(cmd)
p = subprocess.run(cmd, shell=True)
check_proc(p)


# -- Install package reqs
cmd = "pip install -r requirements.txt"
print(cmd)
subprocess.run(cmd, shell=True)
check_proc(p)


# -- Install CI reqs
cmd = "pip install requests radon pydocstyle coverage pycodestyle vulture tox pytest pytest-cov"
print(cmd)
subprocess.run(cmd, shell=True)
check_proc(p)


# -- Load simple_ci.ini
config = configparser.ConfigParser()
config.read('simple_ci.ini')
package_path = config['Project']['package']
package_path = "./" + package_path


# -- Static Analysis Tools to run
tools = [ 
{
    "title": "TOX",
    "cmd": "tox",
    "file": "tox_out.txt",
    "enabled": True
},
{
    "title": "COVERAGE",
    "cmd": "coverage report",
    "file": "coverage_out.txt",
    "enabled": True
},
{
    "title": "RADON CC",
    "cmd": "radon cc --total-average --show-complexity -n C {}".format(package_path),
    "file": "radon_cc_out.txt",
    "enabled": True
},
{
    "title": "RADON MI",
    "cmd": "radon mi --show -n C {}".format(package_path),
    "file": "radon_mi_out.txt",
    "enabled": True
},
{
    "title": "PYCODESTYLE",
    "cmd": "pycodestyle --max-line-length=120 --count --statistics {}".format(package_path),
    "file": "pycode_out.txt",
    "enabled": True
},
{
    "title": "PYDOCSTYLE",
    "cmd": "pydocstyle --add-ignore D400,D401,D205,D105,D107 {}".format(package_path),
    "file": "pydoc_out.txt",
    "enabled": True
},
{
    "title": "VULTURE",
    "cmd": "vulture --min-confidence 80 {}".format(package_path),
    "file": "vulture_out.txt",
    "enabled": True
},
]

# Update tools from simple_ci.ini
for tool in tools:
    section_title = tool['title'].lower()
    if section_title in config:
        section = config[section_title]
        if 'cmd' in section:
            tool['cmd'] = section['cmd']
        if 'enabled' in section:
            enabled = section['enabled'].lower()
            enabled = enabled == 'true'
            tool['enabled'] = enabled


# -- Runs tools and create GitHub comment body
github_body = "\`\`\`\n"

for tool in tools:
    if not tool['enabled']:
        continue
    r = subprocess.run(tool['cmd'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print(r.returncode)
    print(r.stdout)
    print(r.stderr)
    output = f"########## {tool['title']} ##########\n"
    output += r.stdout.decode('utf-8') + r.stderr.decode('utf-8')
    github_body += output
    github_body += "\n\n\n\n"
    with open(tool['file'], 'w', encoding="utf-8") as f:
        f.write(output)

github_body += "\n\`\`\`"
build_url = os.environ['BUILD_URL']  # Add link to Jenkins build
github_body += "\n{}".format(build_url)

# -- Add GitHub Commit
github_body += "\nCommit/Branch: {}".format(commit)

# -- POST GitHub comment
payload = {
    "body": github_body,
}
headers = {
    'Content-Type': "application/json",
    'Cache-Control': "no-cache",
}

comment_url = github_data['pull_request']['_links']['comments']['href']
auth = ('GITHUB API USERNAME', 'GITHUB API PASSWORD')
response = requests.post(comment_url, json=payload, headers=headers, auth=auth)
print(response.text)    


EOM

python3 ./quick_test.py


FILE="./commit.txt"     
if [ -f $FILE ]; then
  virtualenv env
  . ./env/bin/activate
  
  pip install requests
  
  python3 ./ci.py
fi
