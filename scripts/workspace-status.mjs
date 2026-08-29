#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { absoluteFromRelative, isGitRepo, loadCatalog, repoAbsolutePath } from "./lib/workspace-utils.mjs";

const catalog = loadCatalog();

for (const repo of catalog.repos) {
	const targetPath = repoAbsolutePath(repo);
	console.log(`\n${repo.path} (${repo.id})`);

	if (!isGitRepo(targetPath)) {
		console.log("  not cloned yet — run `bun run workspace:setup`");
		continue;
	}

	const result = spawnSync("git", ["status", "--short", "--branch"], {
		cwd: absoluteFromRelative(repo.path),
		encoding: "utf8",
	});
	console.log(
		result.stdout
			.trimEnd()
			.split("\n")
			.map((line) => `  ${line}`)
			.join("\n"),
	);
}

console.log("");
