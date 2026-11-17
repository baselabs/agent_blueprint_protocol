import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

// Machine-readable publication inputs; no environment values are read or logged.
const [mode,file]=process.argv.slice(2);
if(mode==='npm-integrity'&&file&&process.argv.length===4){
  process.stdout.write('sha512-'+createHash('sha512').update(readFileSync(file)).digest('base64'));
}else{
  throw new Error('Expected npm-integrity ARCHIVE');
}
