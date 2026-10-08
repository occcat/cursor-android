import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { resolve, sep, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../dist/", import.meta.url));
const port = Number(process.env.PORT ?? 4173);
const types = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".xml": "application/xml",
    ".txt": "text/plain; charset=utf-8",
};
createServer(async (request, response) => {
    try {
        const pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
        let file = resolve(root, `.${pathname}`);
        if (file !== root.slice(0, -1) && !file.startsWith(`${root.replace(/\/$/, "")}${sep}`)) {
            response.writeHead(403).end();
            return;
        }
        if ((await stat(file)).isDirectory()) file = resolve(file, "index.html");
        const data = await readFile(file);
        response.writeHead(200, {
            "Content-Type": types[extname(file)] ?? "application/octet-stream",
        });
        response.end(data);
    } catch {
        response.writeHead(404, { "Content-Type": "text/plain" }).end("Not found");
    }
}).listen(port, "127.0.0.1", () => console.log(`Preview: http://127.0.0.1:${port}`));
