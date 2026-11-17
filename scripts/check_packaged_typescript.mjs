import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {run} from './run_package_typescript_examples.mjs';
import {npmCli} from './npm.mjs';
const scratch=mkdtempSync(join(tmpdir(),'abp-typescript-examples-'));
try {
  const packed=spawnSync(process.execPath,[npmCli(),'pack','./dist/package','--ignore-scripts','--json','--pack-destination',scratch],{encoding:'utf8'});
  if(packed.status!==0)throw new Error(packed.stdout+packed.stderr);
  const archive=join(scratch,JSON.parse(packed.stdout)[0].filename);
  run(archive,['verifier/README.md','documentation/typescript.md']);
} finally { rmSync(scratch,{recursive:true,force:true}); }
