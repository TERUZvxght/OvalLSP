import * as path from 'path';
import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  const extensionDevelopmentPath = path.resolve(__dirname, '../../../');
  const extensionTestsPath = path.resolve(__dirname, './index');
  const workspacePath = path.resolve(__dirname, '../../../test-fixtures/sample-workspace');

  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
    launchArgs: [workspacePath, '--disable-extensions']
  });
}

main().catch((err) => {
  console.error('Failed to run integration tests:', err);
  process.exit(1);
});
