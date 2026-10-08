import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { latestRelease, releaseMetadata } from "./release.mjs";

const source = fileURLToPath(new URL("../src/", import.meta.url));
const output = fileURLToPath(new URL("../dist/", import.meta.url));
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
await cp(source, output, { recursive: true });
const release = process.argv.includes("--offline") ? releaseMetadata(null) : await latestRelease();
await writeFile(`${output}/latest.json`, `${JSON.stringify(release, null, 2)}\n`);
console.log(`Built website/dist. Release metadata: ${release.status}.`);
