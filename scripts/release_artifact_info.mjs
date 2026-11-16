import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

// Machine-readable publication inputs; no environment values are read or logged.
const [mode,file,version]=process.argv.slice(2);
if(mode==='npm-integrity'&&file&&process.argv.length===4){
  process.stdout.write('sha512-'+createHash('sha512').update(readFileSync(file)).digest('base64'));
}else if(mode==='hex-listed'&&file&&version&&process.argv.length===5){
  const pkg=JSON.parse(readFileSync(file,'utf8'));
  if(!Array.isArray(pkg.releases))throw new Error('Invalid Hex release list');
  process.stdout.write(pkg.releases.some(release=>release.version===version)?'true':'false');
}else{
  throw new Error('Expected npm-integrity ARCHIVE or hex-listed PACKAGE_JSON VERSION');
}
