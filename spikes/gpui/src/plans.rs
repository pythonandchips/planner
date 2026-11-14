//! Finds planner plan folders under a parent folder.
//!
//! A plan folder is any directory directly inside `docs/plans/`, either in the
//! parent folder itself or in one of its immediate child folders (each child is
//! usually a git repo).

use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanFolder {
    /// Name of the repo folder the plan lives in.
    pub repo: String,
    /// Path of the repo folder (the agent session's working directory).
    pub repo_path: PathBuf,
    /// Folder name, e.g. `20260101-120000-desktop-view`.
    pub name: String,
    pub path: PathBuf,
    /// Markdown files in the folder, sorted by name.
    pub files: Vec<PathBuf>,
}

impl PlanFolder {
    /// The newest ITERATION-NNN.md file, if any.
    pub fn latest_iteration(&self) -> Option<&PathBuf> {
        self.files
            .iter()
            .filter(|f| file_name(f).starts_with("ITERATION-"))
            .max()
    }
}

pub fn file_name(path: &Path) -> String {
    path.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Plan folders under `parent` and its immediate children, sorted by repo then name.
pub fn discover(parent: &Path) -> Vec<PlanFolder> {
    let mut repos = vec![parent.to_path_buf()];
    if let Ok(entries) = fs::read_dir(parent) {
        let mut children: Vec<PathBuf> = entries
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_dir() && !file_name(p).starts_with('.'))
            .collect();
        children.sort();
        repos.extend(children);
    }

    let mut folders = Vec::new();
    for repo in repos {
        let plans_dir = repo.join("docs").join("plans");
        let Ok(entries) = fs::read_dir(&plans_dir) else {
            continue;
        };
        let mut dirs: Vec<PathBuf> = entries
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.is_dir())
            .collect();
        dirs.sort();
        for dir in dirs {
            folders.push(PlanFolder {
                repo: file_name(&repo),
                repo_path: repo.clone(),
                name: file_name(&dir),
                files: markdown_files(&dir),
                path: dir,
            });
        }
    }
    folders
}

fn markdown_files(dir: &Path) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(|e| e.ok())
                .map(|e| e.path())
                .filter(|p| p.is_file() && p.extension().is_some_and(|x| x == "md"))
                .collect()
        })
        .unwrap_or_default();
    files.sort();
    files
}

/// Path for the next ITERATION-NNN.md in a plan folder.
pub fn next_iteration_path(folder: &PlanFolder) -> PathBuf {
    let next = folder
        .files
        .iter()
        .filter_map(|f| {
            let name = file_name(f);
            name.strip_prefix("ITERATION-")?
                .strip_suffix(".md")?
                .parse::<u32>()
                .ok()
        })
        .max()
        .map_or(1, |n| n + 1);
    folder.path.join(format!("ITERATION-{next:03}.md"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn touch(path: &Path) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, "# x\n").unwrap();
    }

    #[test]
    fn finds_plans_in_parent_and_child_repos() {
        let tmp = tempfile::tempdir().unwrap();
        let root = tmp.path();
        touch(&root.join("docs/plans/001-root/ITERATION-001.md"));
        touch(&root.join("alpha/docs/plans/002-a/ITERATION-001.md"));
        touch(&root.join("alpha/docs/plans/002-a/FINDINGS-001.md"));
        touch(&root.join("alpha/docs/plans/002-a/notes.txt"));
        touch(&root.join("alpha/docs/plans/001-a/PLAN-001.md"));
        touch(&root.join("beta/docs/plans/003-b/REVIEW-001.md"));
        // Not discovered: too deep, hidden, or not under docs/plans.
        touch(&root.join("alpha/nested/docs/plans/x/ITERATION-001.md"));
        touch(&root.join(".hidden/docs/plans/h/ITERATION-001.md"));
        touch(&root.join("gamma/README.md"));

        let found = discover(root);
        let names: Vec<(String, String)> = found
            .iter()
            .map(|f| (f.repo.clone(), f.name.clone()))
            .collect();
        let root_name = file_name(root);
        assert_eq!(
            names,
            vec![
                (root_name, "001-root".into()),
                ("alpha".into(), "001-a".into()),
                ("alpha".into(), "002-a".into()),
                ("beta".into(), "003-b".into()),
            ]
        );
        let files: Vec<String> = found[2].files.iter().map(|f| file_name(f)).collect();
        assert_eq!(files, vec!["FINDINGS-001.md", "ITERATION-001.md"]);
        assert_eq!(found[1].repo_path, root.join("alpha"));
    }

    #[test]
    fn next_iteration_number() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path().join("docs/plans/p");
        touch(&dir.join("ITERATION-001.md"));
        touch(&dir.join("ITERATION-002.md"));
        let folder = &discover(tmp.path())[0];
        assert_eq!(next_iteration_path(folder), dir.join("ITERATION-003.md"));
        assert_eq!(folder.latest_iteration(), Some(&dir.join("ITERATION-002.md")));
    }

    #[test]
    fn missing_parent_yields_nothing() {
        assert!(discover(Path::new("/definitely/not/here")).is_empty());
    }
}
