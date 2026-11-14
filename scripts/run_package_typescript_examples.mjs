import {mkdtempSync,readFileSync,writeFileSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,dirname,basename} from 'node:path';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';

// Generic: the npm archive and document file list are the entire input.
export function run(archive, files) {
  if (!files.length) throw new Error('no TypeScript example documents');
  const scratch=mkdtempSync(join(tmpdir(),'package-typescript-'));
  const npmCli=[join(dirname(process.execPath),'node_modules/npm/bin/npm-cli.js'),resolve(dirname(process.execPath),'../lib/node_modules/npm/bin/npm-cli.js')].find(existsSync);
  const command=(program,args)=>{
    const result=spawnSync(program==='npm'&&npmCli?process.execPath:program,program==='npm'&&npmCli?[npmCli,...args]:args,{cwd:scratch,encoding:'utf8',maxBuffer:10_000_000});
    if(result.status!==0)throw new Error(`${program} ${args.join(' ')}: exit ${result.status}\n${result.stdout}${result.stderr}`);
    return result.stdout;
  };
  try {
    writeFileSync(join(scratch,'package.json'),' {"private":true,"type":"module"}');
    command('npm',['install','--ignore-scripts','--no-audit','--no-fund',resolve(archive)]);
    let total=0;
    for(const file of files) {
      const source=readFileSync(file,'utf8');
      let index=0;
      for(const match of source.matchAll(/^```(?:js|javascript|ts|typescript)([^\r\n]*)\r?\n([\s\S]*?)^```[ \t]*$/gm)) {
        index++;
        if(match[1].trim()==='fragment')continue;
        if(match[1].trim()!=='')throw new Error(`${file} block ${index}: unknown fence marking`);
        const script=join(scratch,`example-${total++}.mts`);
        writeFileSync(script,match[2]);
        try { process.stdout.write(command(process.execPath,[script])); }
        catch(error) { throw new Error(`${file} block ${index}: ${error.message}`); }
      }
      console.log(`package TypeScript ${basename(file)}: ${index} blocks checked`);
    }
    if(total===0)throw new Error('no runnable TypeScript examples');
    console.log(`package TypeScript: ${total} examples passed outside the checkout`);
  } finally { rmSync(scratch,{recursive:true,force:true}); }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)run(process.argv[2],process.argv.slice(3));
