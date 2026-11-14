import {mkdtempSync,mkdirSync,writeFileSync,readdirSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';

const version=process.argv[2];
if(!/^\d+\.\d+\.\d+(?:-[\w.-]+)?$/.test(version??''))throw new Error('expected released version');
const scratch=mkdtempSync(join(tmpdir(),'abp-published-examples-'));
async function fetchBytes(url){const r=await fetch(url,{signal:AbortSignal.timeout(60_000)});if(!r.ok)throw new Error(`${url}: ${r.status}`);return Buffer.from(await r.arrayBuffer());}
function command(program,args){const r=spawnSync(program,args,{cwd:scratch,encoding:'utf8',maxBuffer:20_000_000});process.stdout.write(r.stdout??'');if(r.status!==0)throw new Error(`${program}: exit ${r.status}\n${r.stderr}`);}
try {
  const hex=await fetchBytes(`https://repo.hex.pm/tarballs/agent_blueprint_protocol-${version}.tar`);
  const release=JSON.parse(await fetchBytes(`https://hex.pm/api/packages/agent_blueprint_protocol/releases/${version}`));
  if(createHash('sha256').update(hex).digest('hex')!==release.checksum)throw new Error('Hex checksum mismatch');
  const archive=join(scratch,'package.tar');writeFileSync(archive,hex);
  const pkg=join(scratch,'hex');mkdirSync(pkg);
  command('elixir',['-e',"[archive, target] = System.argv(); {:ok, entries} = :erl_tar.extract(String.to_charlist(archive), [:memory]); {_, bytes} = List.keyfind(entries, ~c\"contents.tar.gz\", 0); :ok = :erl_tar.extract({:binary, bytes}, [:compressed, {:cwd, String.to_charlist(target)}])",archive,pkg]);
  const npm=JSON.parse(await fetchBytes(`https://registry.npmjs.org/@agent-blueprint-protocol%2fverifier/${version}`));
  const packed=await fetchBytes(npm.dist.tarball);
  const [algorithm,expected]=npm.dist.integrity.split('-');
  if(createHash(algorithm).update(packed).digest('base64')!==expected)throw new Error('npm integrity mismatch');
  const tarball=join(scratch,'verifier.tgz');writeFileSync(tarball,packed);
  const installed=join(scratch,'npm');mkdirSync(installed);
  command('elixir',['-e',"[archive, target] = System.argv(); :ok = :erl_tar.extract(String.to_charlist(archive), [:compressed, {:cwd, String.to_charlist(target)}])",tarball,installed]);
  const notebooks=readdirSync(join(pkg,'docs/livebooks')).filter(x=>x.endsWith('.livemd')).sort().map(x=>join(pkg,'docs/livebooks',x));
  const guides=readdirSync(join(pkg,'documentation')).filter(x=>/\.(?:md|cheatmd)$/.test(x)).sort().map(x=>join(pkg,'documentation',x));
  command('elixir',[join(pkg,'scripts/extract_livebooks.exs'),'--archive',archive,...notebooks]);
  command('elixir',[join(pkg,'scripts/package_examples.exs'),'--archive',archive,'--doctests']);
  command('elixir',[join(pkg,'scripts/package_examples.exs'),'--archive',archive,'--snippets',join(pkg,'README.md'),...guides]);
  command(process.execPath,[join(pkg,'scripts/run_package_typescript_examples.mjs'),tarball,join(installed,'package/README.md'),join(pkg,'documentation/typescript.md')]);
  console.log(`published examples: Hex and npm ${version}, all four consumer gates passed`);
} finally {rmSync(scratch,{recursive:true,force:true});}
