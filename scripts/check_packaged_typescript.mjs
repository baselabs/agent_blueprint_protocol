import {mkdtempSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,dirname} from 'node:path';
import {spawnSync} from 'node:child_process';
import {run} from './run_package_typescript_examples.mjs';
const scratch=mkdtempSync(join(tmpdir(),'abp-typescript-examples-'));
try {
  const npmCli=[join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'),resolve(dirname(process.execPath),'../lib/node_modules/npm/bin/npm-cli.js')].find(existsSync);
  if(!npmCli)throw new Error('npm CLI not found beside Node');
  const packed=spawnSync(process.execPath,[npmCli,'pack','./dist/package','--ignore-scripts','--json','--pack-destination',scratch],{encoding:'utf8'});
  if(packed.status!==0)throw new Error(packed.stdout+packed.stderr);
  const archive=join(scratch,JSON.parse(packed.stdout)[0].filename);
  run(archive,['verifier/README.md','documentation/typescript.md']);
} finally { rmSync(scratch,{recursive:true,force:true}); }
