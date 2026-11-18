import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

export const npmIntegrity = file => 'sha512-'+createHash('sha512').update(readFileSync(file)).digest('base64');

// Machine-readable publication inputs; no environment values are read or logged.
if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  const [mode,file]=process.argv.slice(2);
  if(mode==='version'&&process.argv.length===3){
    const versions=[...readFileSync('mix.exs','utf8').matchAll(/^\s*@version "([^"\n]+)"/gm)];
    if(versions.length!==1||!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(versions[0][1])){
      throw new Error('Expected one exact release version in mix.exs');
    }
    const version=versions[0][1];
    if(JSON.parse(readFileSync('package.json','utf8')).version!==version){
      throw new Error('mix.exs and package.json versions disagree');
    }
    process.stdout.write(version);
  }else if(mode==='npm-integrity'&&file&&process.argv.length===4){
    process.stdout.write(npmIntegrity(file));
  }else{
    throw new Error('Expected version or npm-integrity ARCHIVE');
  }
}
