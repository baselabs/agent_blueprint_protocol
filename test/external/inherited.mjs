import {spawn} from 'node:child_process';
// The adapter exits before answering while a descendant holds the output
// pipe open; the harness reports the exit, not a timeout, on every platform.
spawn(process.execPath,['-e','setTimeout(()=>{},10000)'],{stdio:['ignore',process.stdout,process.stderr],windowsHide:true}).unref();
process.exit(0);
