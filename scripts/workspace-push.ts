#!/usr/bin/env bun

// Pushes every repo that has unpushed commits: all repos registered in
// docs/repo-catalog.yaml (children first), then the meta repo itself last.
// Philosophy: skip, never force. Dirty or diverged repos are reported, not pushed.

import { spawnSync } from "node:child_process";
import {
	REPO_ROOT,
	gitCapture,
	gitStatus,
	loadCatalog,
	repoAbsolutePath,
	type RepoCatalogEntry,
} from "./lib/workspace-utils.ts";

interface CliArgs {
	dryRun: boolean;
	only: string | null;
	except: string | null;
}

interface PushTarget {
	id: string;
	path: string;
	absolutePath: string;
}

const META_TARGET: PushTarget = {
	id: "fenzit-meta",
	path: ".",
	absolutePath: REPO_ROOT,
};

function parseArgs(argv: string[]): CliArgs {
	const args: CliArgs = { dryRun: false, only: null, except: null };
	for (let i = 0; i < argv.length; i++) {
		const arg = argv[i];
		if (arg === "--dry-run") {
			args.dryRun = true;
		} else if (arg === "--only" && argv[i + 1]) {
			args.only = argv[++i];
		} else if (arg === "--except" && argv[i + 1]) {
			args.except = argv[++i];
		} else {
			console.error(`Unknown or incomplete flag: ${arg}`);
			process.exit(2);
		}
	}
	return args;
}

function buildTargets(catalog: ReturnType<typeof loadCatalog>, args: CliArgs): PushTarget[] {
	const targets: PushTarget[] = catalog.repos
		.filter((repo) => repo.status === "active")
		.map((repo: RepoCatalogEntry) => ({
			id: repo.id,
			path: repo.path,
			absolutePath: repoAbsolutePath(repo),
		}));

	// Meta repo last: code ships before the docs that describe it.
	targets.push(META_TARGET);

	if (args.only) {
		const matched = targets.filter((t) => t.id === args.only);
		if (matched.length === 0) {
			console.error(
				`--only "${args.only}" matched no repo. Known ids: ${targets.map((t) => t.id).join(", ")}`,
			);
			process.exit(2);
		}
		return matched;
	}
	if (args.except) {
		return targets.filter((t) => t.id !== args.except);
	}
	return targets;
}

function pushRepo(target: PushTarget, dryRun: boolean): boolean {
	const status = gitStatus(target.absolutePath);

	const dirtyNote = status.dirtyCount > 0 ? `, ${status.dirtyCount} uncommitted` : "";
	const stateNote =
		status.state === "no-upstream"
			? "no upstream"
			: status.state === "in-sync"
				? "in sync"
				: status.state === "diverged"
					? `ahead ${status.ahead} / behind ${status.behind} (diverged)`
					: status.state === "not-a-repo"
						? "not a git repo"
						: `ahead ${status.ahead}`;
	console.log(`\n${target.path} (${target.id})  [${status.branch ?? "?"}: ${stateNote}${dirtyNote}]`);

	switch (status.state) {
		case "not-a-repo":
			console.log("  ⚠ not cloned — run `bun run workspace:setup`");
			return true;
		case "no-upstream":
			console.log("  ⚠ branch has no upstream — push it manually the first time:");
			console.log(`    git -C ${target.path} push -u origin ${status.branch}`);
			return true;
		case "in-sync":
			console.log("  ✓ nothing to push");
			return true;
		case "behind":
		case "diverged":
			console.log("  ⚠ local branch is behind origin — pull/rebase first, then re-run.");
			console.log(`    git -C ${target.path} pull --rebase`);
			return true;
	}

	if (status.dirtyCount > 0) {
		console.log("  ⚠ has uncommitted changes — commit them first; not pushing anything.");
		return true;
	}

	if (dryRun) {
		const commits = gitCapture(target.absolutePath, ["log", "--oneline", "@{u}.."]) ?? "";
		for (const line of commits.split("\n").filter(Boolean)) {
			console.log(`  would push  ${line}`);
		}
		return true;
	}

	const result = spawnSync("git", ["push"], { cwd: target.absolutePath, stdio: "inherit" });
	return result.status === 0;
}

try {
	const catalog = loadCatalog();
	const args = parseArgs(process.argv.slice(2));
	const targets = buildTargets(catalog, args);

	if (args.dryRun) {
		console.log("Dry run — nothing will be pushed.\n");
	}

	let failed = 0;
	for (const target of targets) {
		const ok = pushRepo(target, args.dryRun);
		if (!ok) failed++;
	}

	console.log("");
	console.log(
		failed === 0
			? "All repos handled."
			: `${failed} repo(s) failed to push — see output above.`,
	);
	process.exit(failed === 0 ? 0 : 1);
} catch (error) {
	console.error(error instanceof Error ? error.message : error);
	process.exit(1);
}