#!/usr/bin/env node

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const root = process.argv[2];
const flatten = process.argv.includes("--flatten");
if (!root) {
	throw new Error("usage: pin-bun-dependencies.mjs <source-root>");
}

const lock = JSON.parse(readFileSync(join(root, "package-lock.json"), "utf8"));
const lockPackages = lock.packages ?? {};

const workspaces = new Map();
for (const [relativePath, entry] of Object.entries(lockPackages)) {
	if (relativePath.split("/").includes("node_modules")) continue;
	if (typeof entry?.name !== "string") continue;
	const packageJson = join(root, relativePath, "package.json");
	if (existsSync(packageJson)) workspaces.set(entry.name, relativePath);
}

function lockedDependency(workspacePath, name) {
	let current = workspacePath;
	for (;;) {
		const key = current ? `${current}/node_modules/${name}` : `node_modules/${name}`;
		const entry = lockPackages[key];
		if (typeof entry?.version === "string") return entry.version;
		if (!current) break;
		const slash = current.lastIndexOf("/");
		current = slash < 0 ? "" : current.slice(0, slash);
	}
	throw new Error(`package-lock.json has no resolved version for ${name} from ${workspacePath || "the root"}`);
}

for (const [workspaceName, relativePath] of workspaces) {
	const packageJsonPath = join(root, relativePath, "package.json");
	const pkg = JSON.parse(readFileSync(packageJsonPath, "utf8"));

	for (const section of ["dependencies", "devDependencies", "optionalDependencies"]) {
		for (const name of Object.keys(pkg[section] ?? {})) {
			// The private root package is only a workspace/build orchestrator. Its
			// dependency on the coding-agent workspace makes Bun invalidate an
			// otherwise current lockfile, so omit that redundant edge.
			if (!relativePath && name === "@earendil-works/pi-coding-agent") {
				delete pkg[section][name];
				continue;
			}

			pkg[section][name] = workspaces.has(name) ? "workspace:*" : lockedDependency(relativePath, name);
		}
	}

	writeFileSync(packageJsonPath, `${JSON.stringify(pkg, null, "\t")}\n`);
	console.log(`Pinned Bun dependencies for ${workspaceName}`);
}

if (flatten) {
	const dependencies = {};
	const buildWorkspaces = ["", "packages/tui", "packages/ai", "packages/agent", "packages/coding-agent"];
	for (const relativePath of buildWorkspaces) {
		const pkg = JSON.parse(readFileSync(join(root, relativePath, "package.json"), "utf8"));
		for (const section of ["dependencies", "devDependencies", "optionalDependencies"]) {
			for (const name of Object.keys(pkg[section] ?? {})) {
				if (!workspaces.has(name)) dependencies[name] = lockedDependency(relativePath, name);
			}
		}
	}

	const originalRoot = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
	const syntheticRoot = {
		name: "prime-agent-bun-build",
		private: true,
		version: originalRoot.version,
		type: "module",
		dependencies: Object.fromEntries(Object.entries(dependencies).sort(([left], [right]) => left.localeCompare(right))),
	};
	writeFileSync(join(root, "package.json"), `${JSON.stringify(syntheticRoot, null, "\t")}\n`);
	console.log("Flattened Bun's install graph for the Nix build");
}
