from pathlib import Path
import tempfile, subprocess, os, shutil
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as td:
 root=Path(td); (root/'roms').mkdir(); ports=root/'roms'/'ports'
 ports.mkdir(); old=ports/'RGB-PI Updater27'; (old/'data').mkdir(parents=True); (old/'update.sh').write_text('old'); (old/'data'/'private-test.sh').write_text('preserved')
 cmd=['bash',str(repo/'install.sh'),str(ports)]
 subprocess.run(cmd,check=True)
 target=root/'.rgbpi-updater27'; (target/'logs').mkdir(); (target/'logs'/'keep').write_text('keep')
 subprocess.run(cmd,check=True)
 assert (target/'logs'/'keep').read_text()=='keep'
 assert len(list(ports.rglob('*.sh')))==1
 assert len(list(target.glob('legacy.*/port/data/private-test.sh')))==1
 assert (target/'data'/'manifest.json').read_bytes()==(repo/'manifest.json').read_bytes()
 # Replace hardware/update actions with recording stubs; exercise launcher dispatch.
 for f in (target/'data').glob('*.sh'): f.write_text('#!/bin/bash\nprintf "called:%s\\n" "$0"\n')
 launcher=(target/'update.sh').read_text().replace('$EUID','$TEST_EUID')
 (target/'update.sh').write_text(launcher)
 mock=root/'bin';mock.mkdir();(mock/'sudo').write_text('#!/bin/bash\necho unexpected-sudo >&2\nexit 1\n');(mock/'sudo').chmod(0o755)
 env=dict(os.environ,PATH=str(mock)+':'+os.environ['PATH'],TEST_EUID='0')
 for action in ('retroarch','cores','timings','bootstrap','mount'):
  p=subprocess.run(['bash',str(target/'update.sh'),action],env=env,capture_output=True,text=True)
  assert p.returncode==0,(action,p.stderr)
  assert 'called:' in p.stdout and 'unexpected-sudo' not in p.stderr
 p=subprocess.run(['bash',str(ports/'RGB-PI Updater27'/'update.sh'),'cores'],env=env,capture_output=True,text=True)
 assert p.returncode==0 and 'called:' in p.stdout
 env['TEST_EUID']='1000'
 p=subprocess.run(['bash',str(target/'update.sh'),'retroarch'],env=env,capture_output=True,text=True)
 assert p.returncode==77 and 'Ports' in p.stdout and 'called:' not in p.stdout
 p=subprocess.run(['bash',str(target/'update.sh'),'root'],env=env,capture_output=True,text=True)
 assert p.returncode==77
 print('PASS: repeat installation preserves logs; all root dispatches bypass sudo; restricted SSH/root bootstrap fail safely.')
for f in [repo/'update.sh',repo/'install.sh',*(repo/'data').glob('*.sh')]:
 subprocess.run(['bash','-n',str(f)],check=True)
print('PASS: all shell scripts parse.')
