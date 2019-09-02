#!/usr/bin/env python3
import subprocess
import json

command = "i3-msg"
arguments = ['-t', 'get_workspaces']
output = subprocess.check_output([command] + arguments)

workspaces = json.loads(output.decode('utf-8'))
last_nonempty_workspace = workspaces[-1]['num']
first_empty_workspace = last_nonempty_workspace + 1 

print(first_empty_workspace)