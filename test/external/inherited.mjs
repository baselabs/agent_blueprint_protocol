import {spawn} from 'node:child_process';
// The descendant holds the pipes after its adapter exits. It has a finite
// lifetime on Windows, where the harness owns only the direct process handle.
spawn(process.execPath,['-e','setTimeout(()=>{},10000)'],{stdio:['ignore',process.stdout,process.stderr],windowsHide:true}).unref();
process.exit(0);
