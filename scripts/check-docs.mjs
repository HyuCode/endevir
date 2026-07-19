import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

const root = process.cwd();
const docsRoot = join(root, "docs");
const errors = [];

const publicCategories = new Set([
  "01-adr",
  "02-design",
  "03-benchmarks",
  "04-integration",
]);

const publicDocuments = new Set([
  "docs/README.md",
  "docs/01-adr/README.md",
  "docs/01-adr/00-template.md",
  "docs/01-adr/01-event-driven-waiting.md",
  "docs/01-adr/02-agent-transport.md",
  "docs/01-adr/03-hot-restart-loop.md",
  "docs/01-adr/04-trace-recording-cost.md",
  "docs/01-adr/05-static-test-enumeration.md",
  "docs/01-adr/06-native-test-mapping.md",
  "docs/01-adr/07-monorepo-tooling.md",
  "docs/01-adr/08-test-mode-boundary.md",
  "docs/02-design/01-trace-schema.md",
  "docs/03-benchmarks/01-mvp-benchmarks.md",
  "docs/04-integration/01-cloud.md",
]);

function walk(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? walk(path) : [path];
  });
}

function display(path) {
  return relative(root, path).replaceAll("\\", "/");
}

for (const entry of readdirSync(docsRoot, { withFileTypes: true })) {
  if (entry.isDirectory() && !publicCategories.has(entry.name)) {
    errors.push(`non-public or unreviewed docs category: docs/${entry.name}`);
  }
}

const actualDocuments = walk(docsRoot)
  .filter((path) => path.endsWith(".md"))
  .map(display);

for (const document of actualDocuments) {
  const basename = document.split("/").at(-1);
  if (basename !== "README.md" && !/^\d{2}-[a-z0-9][a-z0-9-]*\.md$/.test(basename)) {
    errors.push(`public document must start with NN-: ${document}`);
  }
  if (!publicDocuments.has(document)) {
    errors.push(`document is not on the reviewed public allowlist: ${document}`);
  }
}

for (const document of publicDocuments) {
  if (!actualDocuments.includes(document)) {
    errors.push(`allowlisted public document is missing: ${document}`);
  }
}

for (const file of [join(root, "README.md"), ...actualDocuments.map((path) => join(root, path))]) {
  const markdown = readFileSync(file, "utf8");
  for (const match of markdown.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
    const link = match[1].split("#", 1)[0];
    if (!link || /^(?:https?:|mailto:)/.test(link)) continue;

    const target = resolve(dirname(file), decodeURIComponent(link));
    if (!existsSync(target)) {
      errors.push(`broken local link: ${display(file)} -> ${match[1]}`);
    }
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log("Public documentation boundary, structure, and links are valid.");
