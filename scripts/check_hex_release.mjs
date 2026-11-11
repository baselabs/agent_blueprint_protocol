import { readFileSync,appendFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

// Publication is established by the public API, never by upload success.
const [version,archive]=process.argv.slice(2);
if(!version||!archive||process.argv.length!==4)throw new Error('Expected version and verified Hex archive');
const base='https://hex.pm/api/packages/agent_blueprint_protocol';
async function json(url){const response=await fetch(url,{signal:AbortSignal.timeout(30_000)});if(!response.ok)throw new Error('Hex API request failed: '+response.status);return response.json();}
const pkg=await json(base);
if(!Array.isArray(pkg.releases))throw new Error('Hex API release list is malformed');
const listed=pkg.releases.some(release=>release.version===version);
if(!listed){
  if(process.env.GITHUB_OUTPUT)appendFileSync(process.env.GITHUB_OUTPUT,'live=false\n');
  console.log('::notice::Hex version is not live. It may be staged and awaiting approval. The GitHub release did not run.');
  console.log('Approve the staged release on hex.pm, then rerun this workflow on the same tag.');
}else{
  const release=await json(base+'/releases/'+encodeURIComponent(version));
  const checksum=createHash('sha256').update(readFileSync(archive)).digest('hex');
  if(release.version!==version||release.checksum!==checksum)throw new Error('Live Hex bytes differ from the verified archive');
  if(process.env.GITHUB_OUTPUT)appendFileSync(process.env.GITHUB_OUTPUT,'live=true\n');
  console.log('Hex: exact version is live and matches the verified archive');
}
