import * as assert from 'assert';
import { spawn } from 'child_process';
import { SpawnedCoreProcess } from '../../coreProcess';

function processAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code !== 'ESRCH';
  }
}

describe('SpawnedCoreProcess', () => {
  it('terminates a real detached process and is idempotent', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }

    const child = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
      detached: true,
      stdio: 'ignore'
    });
    assert.ok(child.pid);
    const pid = child.pid;
    const owner = new SpawnedCoreProcess(child, process.platform, 100, 100);

    await owner.terminate();
    await owner.terminate();

    assert.strictEqual(processAlive(pid), false);
  });

  it('terminates descendants in the detached Core process group', async function () {
    if (process.platform === 'win32') {
      this.skip();
    }

    const script =
      "const {spawn}=require('child_process');" +
      "const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{detached:true,stdio:'ignore'});" +
      "process.stdout.write(String(child.pid)+'\\n');setInterval(()=>{},1000);";
    const core = spawn(process.execPath, ['-e', script], {
      detached: true,
      stdio: ['ignore', 'pipe', 'ignore']
    });
    assert.ok(core.pid);
    const childPid = await new Promise<number>((resolve, reject) => {
      let output = '';
      core.stdout!.on('data', (chunk) => {
        output += chunk.toString();
        const line = output.split('\n')[0];
        if (line.length > 0) {
          resolve(Number(line));
        }
      });
      core.once('error', reject);
    });
    const owner = new SpawnedCoreProcess(core, process.platform, 100, 100);

    await owner.terminate();

    assert.strictEqual(processAlive(core.pid), false);
    assert.strictEqual(processAlive(childPid), false);
  });
});
