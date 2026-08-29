import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import YAML from "yaml";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "..", "..");

export function absoluteFromRelative(relativePath) {
	return path.resolve(REPO_ROOT, relativePath);
}

export function loadCatalog() {
	const catalogPath = absoluteFromRelative("docs/repo-catalog.yaml");
	const raw = fs.readFileSync(catalogPath, "utf8");
	return YAML.parse(raw);
}

export function ensureDir(absolutePath) {
	fs.mkdirSync(absolutePath, { recursive: true });
}

export function ensureWorkspaceRoots(catalog) {
	ensureDir(absoluteFromRelative(catalog.core_root));
	ensureDir(absoluteFromRelative(catalog.external_root));
}

export function fileExists(absolutePath) {
	return fs.existsSync(absolutePath);
}

export function isGitRepo(absolutePath) {
	return fileExists(path.join(absolutePath, ".git"));
}

export function repoAbsolutePath(repo) {
	return absoluteFromRelative(repo.path);
}

export function runCommand(command, args, options = {}) {
	const result = spawnSync(command, args, {
		stdio: "inherit",
		cwd: REPO_ROOT,
		...options,
	});

	if (result.status !== 0) {
		throw new Error(`Command failed: ${command} ${args.join(" ")}`);
	}
}

export function childDirectoryNames(absolutePath) {
	if (!fileExists(absolutePath)) {
		return [];
	}

	return fs
		.readdirSync(absolutePath, { withFileTypes: true })
		.filter((entry) => entry.isDirectory())
		.map((entry) => entry.name);
}
