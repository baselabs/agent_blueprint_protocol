import {spawnSync} from 'node:child_process';
import {relative,resolve} from 'node:path';

// Environment options never enter command diagnostics.
function announce(program,args,options) {
  const cwd=relative(process.cwd(),resolve(options.cwd??'.'))||'.';
  process.stderr.write('command: '+JSON.stringify([program,...args])+' (cwd: '+cwd+')\n');
}

export function capture(program,args,options={}) {
  announce(program,args,options);
  return spawnSync(program,args,options);
}

export function stream(program,args,options={}) {
  announce(program,args,options);
  return spawnSync(program,args,{...options,stdio:'inherit'});
}
