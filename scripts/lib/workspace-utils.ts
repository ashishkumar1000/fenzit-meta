import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import YAML from "yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "..", "..");

export interface RepoCatalogEntry {
	id: string;
	path: string;
	remote: string;
	role: string;
	default_branch: string;
	status: string;
	docs_dir: string;
}

export interface RepoCatalog {
	version: number;
	workspace_root: string;
	core_root: string;
	external_root: string;
	repos: RepoCatalogEntry[];
}

export interface GitStatus {
	branch: string | null;
	upstream: string | null;
	ahead: number;
	behind: number;
	dirtyCount: number;
	/** "in-sync" | "ahead" | "behind" | "diverged" | "no-upstream" | "not-a-repo" */
	state: "in-sync" | "ahead" | "behind" | "diverged" | "no-upstream" | "not-a-repo";
}

export function absoluteFromRelative(relativePath: string): string {
	return path.resolve(REPO_ROOT, relativePath);
}

export function loadCatalog(): RepoCatalog {
	const catalogPath = absoluteFromRelative("docs/repo-catalog.yaml");
	const raw = fs.readFileSync(catalogPath, "utf8");
	return YAML.parse(raw) as RepoCatalog;
}

export function ensureDir(absolutePath: string): void {
	fs.mkdirSync(absolutePath, { recursive: true });
}

export function ensureWorkspaceRoots(catalog: RepoCatalog): void {
	ensureDir(absoluteFromRelative(catalog.core_root));
	ensureDir(absoluteFromRelative(catalog.external_root));
}

export function fileExists(absolutePath: string): boolean {
	return fs.existsSync(absolutePath);
}

export function isGitRepo(absolutePath: string): boolean {
	return fileExists(path.join(absolutePath, ".git"));
}

export function repoAbsolutePath(repo: RepoCatalogEntry): string {
	return absoluteFromRelative(repo.path);
}

export function runCommand(command: string, args: string[], options: object = {}): void {
	const result = spawnSync(command, args, {
		stdio: "inherit",
		cwd: REPO_ROOT,
		...options,
	});

	if (result.status !== 0) {
		throw new Error(`Command failed: ${command} ${args.join(" ")}`);
	}
}

/** Run a git command in a repo directory and return trimmed stdout, or null if git failed. */
export function gitCapture(repoDir: string, args: string[]): string | null {
	const result = spawnSync("git", args, { cwd: repoDir, encoding: "utf8" });
	return result.status === 0 ? result.stdout.trim() : null;
}

/** Collect branch, upstream, ahead/behind and dirty-file counts for one repo. */
export function gitStatus(repoDir: string): GitStatus {
	if (!isGitRepo(repoDir)) {
		return {
			branch: null, upstream: null, ahead: 0, behind: 0, dirtyCount: 0,
			state: "not-a-repo",
		};
	}

	const branchInfo = gitCapture(repoDir, ["status", "--short", "--branch"]) ?? "";
	const dirtyCount = branchInfo
		.split("\n")
		.filter((line) => line.length > 0 && !line.startsWith("##")).length;

	// First ## line, e.g. "## main...origin/main [ahead 1, behind 2]"
	const header = (branchInfo.split("\n").find((line) => line.startsWith("##")) ?? "").slice(3);
	const [branchPart, upstreamPart = ""] = header.split("...");
	const branch = branchPart.trim() || null;
	const upstream = upstreamPart ? upstreamPart.replace(/\s*\[.*\]\s*$/, "").trim() : null;
	const note = header.match(/\[(.+)\]/)?.[1] ?? "";

	const ahead = Number(note.match(/ahead (\d+)/)?.[1] ?? 0);
	const behind = Number(note.match(/behind (\d+)/)?.[1] ?? 0);

	let state: GitStatus["state"];
	if (!upstream) {
		state = "no-upstream";
	} else if (ahead > 0 && behind > 0) {
		state = "diverged";
	} else if (ahead > 0) {
		state = "ahead";
	} else if (behind > 0) {
		state = "behind";
	} else {
		state = "in-sync";
	}

	return { branch, upstream, ahead, behind, dirtyCount, state };
}

export function childDirectoryNames(absolutePath: string): string[] {
	if (!fileExists(absolutePath)) {
		return [];
	}

	return fs
		.readdirSync(absolutePath, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name);
}