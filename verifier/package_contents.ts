import { createHash } from 'node:crypto';
import { lstatSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const domain = 'agent-blueprint-protocol/package-contents';
const exclusions = {
  hex: ['priv/release-metadata.json', 'priv/release-history.json', '.hex', 'hex_metadata.config'],
  npm: ['dist/release-metadata.json', 'dist/release-history.json'],
} as const;

export type PackageDistribution = keyof typeof exclusions;

export function packageChecksum(root: string, distribution: PackageDistribution): string {
  const omitted: readonly string[] = exclusions[distribution];
  const paths: Buffer[] = [];
  function walk(relative: string): void {
    for (const entry of readdirSync(join(root, relative), { encoding: 'buffer' })) {
      const name = entry.toString('utf8');
      if (!entry.equals(Buffer.from(name)) || name.includes('\\')) {
        throw new Error('Invalid package path');
      }
      const path = relative + name;
      const info = lstatSync(join(root, path));
      if (info.isDirectory()) walk(path + '/');
      else if (!info.isFile()) throw new Error('Expected regular package files');
      else if (!omitted.includes(path)) paths.push(Buffer.from(path));
    }
  }
  walk('');

  const hash = createHash('sha256').update(domain + '\0' + distribution + '\0');
  const length = Buffer.alloc(8);
  for (const path of paths.sort(Buffer.compare)) {
    const bytes = readFileSync(join(root, path.toString('utf8')));
    for (const value of [path, bytes]) {
      length.writeBigUInt64BE(BigInt(value.length));
      hash.update(length).update(value);
    }
  }
  return 'sha-256:' + hash.digest('base64url');
}
