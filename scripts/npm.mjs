import {existsSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

// npm's own CLI script, found beside the running Node executable. On Windows,
// npm is a .cmd batch launcher that a native process spawn cannot start, so
// every repository caller runs this Node executable with the script instead
// of launching npm by name. The packaged TypeScript gate keeps its own copy of
// this lookup because it ships alone in the Hex package.
export function npmCli(){
  const cli=[join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'),resolve(dirname(process.execPath),'../lib/node_modules/npm/bin/npm-cli.js')].find(existsSync);
  if(!cli)throw new Error('npm CLI not found beside Node');
  return cli;
}

// Run directly, this is npm for callers outside Node, such as Elixir tests and
// gates: node scripts/npm.mjs <npm arguments>. It exits with npm's status.
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const result=spawnSync(process.execPath,[npmCli(),...process.argv.slice(2)],{stdio:'inherit'});
  if(result.error)throw result.error;
  process.exit(result.status??1);
}
