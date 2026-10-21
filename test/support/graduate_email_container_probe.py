"""Host-only resolved-template regression. Installed image only; no external network.

Mount check: python3 test/support/graduate_email_container_probe.py --image IMAGE
Also run guarded SQLite/real foreground workers: add --workers.
Only the template example is parsed; no populated environment file is read.
"""
import argparse
import json
import os
import pathlib
import re
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--image', required=True)
parser.add_argument('--workers', action='store_true')
parser.add_argument('--runtime-container', default='etd-graduate-auth',
                    help='Existing installed dependency source, copied read-only without config/cache')
opts = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
env = dict(os.environ, GRADUATE_EMAIL_IMAGE=opts.image,
           GRADUATE_EMAIL_UID='65534', GRADUATE_EMAIL_GID='65534',
           GRADUATE_EMAIL_ENV_FILE='config/deploy/graduate-email.env.example')
resolved = subprocess.run(['docker', 'compose', '-f', 'docker-compose.graduate-email.yml',
                          '--profile', 'graduate-email', 'config', '--format', 'json'],
                         cwd=root, env=env, capture_output=True, timeout=30)
assert resolved.returncode == 0, 'Compose resolve failed'
services = json.loads(resolved.stdout)['services']
a = services['graduate-email-worker-a']
assert a == services['graduate-email-worker-b']
assert a['user'] == '65534:65534' and a['read_only'] and a['cap_drop'] == ['ALL']
assert a['security_opt'] == ['no-new-privileges:true']
assert a['environment']['QUEUES'] == 'graduate_email,graduate_email_notice'
assert a['command'][-1].endswith('exec bundle exec rake jobs:work\n')
assert a['restart'] == 'on-failure' and a['stop_grace_period'] == '40s'
assert a['logging'] == {'driver': 'local', 'options': {'max-size': '5m', 'max-file': '2'}}
args = ['docker', 'run', '--rm', '--pull=never', '--network', 'none', '--read-only',
        '--user', a['user'], '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges:true',
        '--stop-timeout', '40', '--log-driver', 'local', '--log-opt', 'max-size=5m',
        '--log-opt', 'max-file=2', '--workdir', a['working_dir']]
for mount in a['tmpfs']:
    args += ['--tmpfs', mount]
code = """require 'json'
checks=%w[/tmp /app/tmp /app/log].map do |p|
  s=File.stat(p); ok=false
  begin
    d=p+'/task8-fix1-probe'; Dir.mkdir(d); File.write(d+'/safe','ok')
    ok=File.read(d+'/safe')=='ok'; File.delete(d+'/safe'); Dir.rmdir(d)
  rescue SystemCallError
  end
  {path:p,uid:s.uid,gid:s.gid,mode:(s.mode & 0777).to_s(8),write:ok}
end
status=File.read('/proc/self/status')
restricted=status.match?(/^NoNewPrivs:\s+1$/) && status.match?(/^CapEff:\s+0+$/)
readonly=File.readlines('/proc/self/mountinfo').any?{|line|f=line.split;f[4]=='/' && f[5].split(',').include?('ro')}
puts JSON.generate(euid:Process.euid,egid:Process.egid,paths:checks,no_new_privileges_and_no_caps:restricted,root_read_only:readonly)
exit(restricted && readonly && checks.all?{|c|c[:uid]==Process.euid && c[:gid]==Process.egid && c[:mode]=='700' && c[:write]} ? 0:1)
"""
r = subprocess.run(args + ['--entrypoint', 'ruby', opts.image, '-e', code],
                   capture_output=True, timeout=30)
print(r.stdout.decode(), end='')  # Fixed, no-DB probe JSON only.
print(json.dumps({'mount_exit': r.returncode, 'resolved_tmpfs': a['tmpfs']}), flush=True)
if r.returncode:
    sys.exit(r.returncode)
# Compose's config representation preserves $$; its container command uses $.
# Exercise that exact validation prefix with no Rails/DB, including negatives.
validation = a['command'][-1].replace('$$', '$').replace('exec bundle exec rake jobs:work', 'exit 0')
for uid, gid, accepted in [('65534', '65534', True), ('0', '65534', False),
                           ('65534', '0', False), ('', '65534', False),
                           ('065534', '65534', False), ('name', '65534', False),
                           ('65534x', '65534', False), ('65533', '65534', False)]:
    result = subprocess.run(args + ['-e', 'GRADUATE_EMAIL_UID='+uid,
        '-e', 'GRADUATE_EMAIL_GID='+gid, '--entrypoint', 'sh', opts.image, '-ec', validation],
        capture_output=True, timeout=30)
    assert (result.returncode == 0) == accepted, 'Identity validation outcome'
    assert result.stdout in (b'', b'graduate_email worker_identity_rejected\n'), 'Static rejection only'
print(json.dumps({'identity_cases': 8, 'passed': True}), flush=True)
if opts.workers:
    # A new in-container tmpfs DB, at the existing guard's ONLY allowed SQLite
    # path. /app is read-only; no host uploads, workbook, DB or report is written.
    # Every real child worker inherits exactly these container restrictions.
    command = """set +x
set -eu
bash script/verify_graduate_email_storage sqlite fresh
bash script/verify_graduate_email_storage sqlite exec ruby test/support/graduate_email_task5_test_reporter.rb test/integration/graduate_email_worker_operations_test.rb -v --seed=27183
"""
    runtime = ['--mount', 'type=bind,source='+str(root)+',target=/app,readonly', '-e', 'HOME=/tmp']
    # No values from the parsed env_file are copied. Synthetic configuration is
    # installed by the existing test helpers, never an SMTP transport.
    for key in ['GRADUATE_EMAIL_WORKER', 'QUEUES', 'QUIET', 'RAILS_MAX_THREADS']:
        runtime += ['-e', key+'='+a['environment'][key]]
    runtime += ['-e', 'GRADUATE_EMAIL_STRICT_REPORT=1']
    # The original local image predates locked OAuth/Delayed Job gems installed
    # in the existing runtime. Copy ONLY code/specs/extensions/bin, never bundle
    # config, env, cache, /tmp or application secrets. No install/network/pull.
    volume = 'etd-task8-fix1-bundle-' + uuid.uuid4().hex
    subprocess.run(['docker', 'volume', 'create', volume], capture_output=True, check=True)
    fingerprint = """import pathlib,hashlib,json
base=pathlib.Path('/usr/local/bundle'); digest=hashlib.sha256(); count=0
for p in sorted(p for d in ['gems','specifications','extensions','bin','bundler/gems'] for p in (base/d).rglob('*') if p.is_file() and '.git' not in p.parts):
 digest.update(str(p.relative_to(base)).encode()+b'\\0'+hashlib.sha256(p.read_bytes()).digest());count+=1
print(json.dumps({'files':count,'sha256':digest.hexdigest()}))
"""
    try:
        before = subprocess.check_output(['docker','exec',opts.runtime_container,'python3','-c',fingerprint])
        producer = subprocess.Popen(['docker', 'exec', opts.runtime_container, 'tar', '-C', '/usr/local/bundle',
            '--exclude=.git', '-cf', '-', 'gems', 'specifications', 'extensions', 'bin', 'bundler/gems'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            copied = subprocess.run(['docker', 'run', '--rm', '--pull=never', '--network', 'none', '-i',
                '--mount', 'type=volume,source='+volume+',target=/bundle', '--entrypoint', 'tar',
                opts.image, '-xf', '-', '-C', '/bundle'], stdin=producer.stdout, capture_output=True, timeout=120)
            producer.stdout.close()
            producer.communicate(timeout=30)
            assert copied.returncode == 0 and producer.returncode == 0, 'Installed dependency copy failed'
        finally:
            if producer.poll() is None:
                producer.kill(); producer.communicate()
        after = subprocess.check_output(['docker','exec',opts.runtime_container,'python3','-c',fingerprint])
        assert before == after, 'Installed dependency source changed'
        mounted = subprocess.check_output(['docker','run','--rm','--pull=never','--network','none',
            '--mount','type=volume,source='+volume+',target=/usr/local/bundle,readonly',
            '--entrypoint','python3',opts.image,'-c',fingerprint])
        assert before == mounted, 'Copied installed dependency bytes differ'
        print(json.dumps({'installed_dependency_code':json.loads(before),'copied_read_only':True}),flush=True)
        runtime += ['--mount', 'type=volume,source='+volume+',target=/usr/local/bundle,readonly']
        result = subprocess.run(args + runtime + ['--entrypoint', 'sh', opts.image, '-ec', command],
                                capture_output=True, timeout=300)
    finally:
        removed = subprocess.run(['docker','volume','rm',volume],capture_output=True,timeout=30)
        assert removed.returncode == 0, 'Disposable dependency volume cleanup failed'

    # Guard/reporter output only, additionally allowlisted here. Raw diagnostics
    # remain in RAM even if Docker, Ruby or startup fails.
    for line in result.stdout.decode(errors='replace').splitlines():
        if re.fullmatch(r'(sqlite [a-z_]+: (PASS|FAIL)|STORAGE_PROBE (PASS|FAIL) [a-z_]+|[0-9]+ runs, [0-9]+ assertions, [0-9]+ failures, [0-9]+ errors, [0-9]+ skips|TEST_(DIAGNOSTIC|LOCATION|CATEGORY|EXCEPTION) [A-Za-z0-9_ ./#:]+|VERSIONS ruby=[0-9.]+ rails=[0-9.]+ delayed_job=[0-9.]+ backend=[0-9.]+ database=[0-9.]+)', line):
            print(line)
    print(json.dumps({'foreground_container_exit': result.returncode,
                      'user': a['user'], 'network': 'none', 'root_read_only': True,
                      'mount_source_read_only': True, 'private_tmpfs': a['tmpfs']}), flush=True)
    sys.exit(result.returncode)
