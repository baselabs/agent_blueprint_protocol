// Compatibility entry for the conformance CLI. Importing it performs no I/O.
import { pathToFileURL } from "node:url";

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await import("./cli.ts");
}
