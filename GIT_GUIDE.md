# Git Quick Reference for Mercurial Users

A practical guide for using Git with this project, tailored for users coming from Mercurial (hg).

## 🎯 Key Conceptual Differences

### 1. **Staging Area (Index)**
- **hg**: Changes are committed directly (`hg commit`)
- **git**: Changes must be *staged* first, then committed
  ```bash
  git add file.txt        # Stage changes
  git commit -m "message" # Commit staged changes
  ```
  
  **Shortcut** (like hg): `git commit -a -m "message"` stages and commits tracked files in one step

### 2. **Local vs Remote Branches**
- **hg**: `hg pull` + `hg update` (or `hg pull -u`)
- **git**: `git pull` = `git fetch` + `git merge` automatically
  - `git fetch` - downloads changes without merging
  - `git pull` - downloads and merges in one step

### 3. **Branch Model**
- **hg**: Branches are permanent named labels
- **git**: Branches are lightweight pointers (easily created/deleted)
  - For this project: mostly stay on `main` branch

### 4. **Command Terminology**
| Mercurial (hg) | Git | Notes |
|----------------|-----|-------|
| `hg commit` | `git commit -a` | Commit all tracked files |
| `hg addremove` | `git add -A` | Stage all changes including new/deleted files |
| `hg status` | `git status` | Show working directory status |
| `hg diff` | `git diff` | Show uncommitted changes |
| `hg log` | `git log` | Show commit history |
| `hg pull -u` | `git pull` | Get remote changes and update |
| `hg push` | `git push` | Send commits to remote |
| `hg revert FILE` | `git restore FILE` | Discard changes to file |
| `hg update REV` | `git checkout REV` | Update to specific revision |
| `hg heads` | `git branch -a` | Show all branches |
| `hg incoming` | `git fetch && git log ..origin/main` | Preview incoming changes |
| `hg outgoing` | `git log origin/main..` | Preview outgoing changes |

## 🚀 Initial Setup

### 1. Initialize Git Repository
```bash
cd /home/da1061/docker/jade-prod/0_nginx_authentik

# Initialize git repo (like hg init)
git init

# Configure your identity
git config user.name "Your Name"
git config user.email "your.email@example.org"

# Optional: Set default branch name to 'main'
git branch -M main
```

### 2. Create Private GitHub Repository

1. Go to https://github.com/new
2. Repository name: `edge-auth-stack` (or your choice)
3. **Privacy**: Select "Private"
4. **DON'T** initialize with README (we already have files)
5. Click "Create repository"

### 3. Connect Local Repo to GitHub

```bash
# Add GitHub as remote (like adding a path in hg)
git remote add origin git@github.com:YOUR_USERNAME/edge-auth-stack.git

# Verify remote
git remote -v
```

### 4. Set Up SSH Key (if not already done)

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your.email@example.org"

# Copy public key
cat ~/.ssh/id_ed25519.pub

# Add to GitHub: Settings → SSH and GPG keys → New SSH key
```

### 5. Initial Commit and Push

```bash
# Stage all files (respecting .gitignore)
git add -A

# Check what will be committed
git status

# Commit
git commit -m "Initial commit: Edge-auth stack with nginx + Authentik"

# Push to GitHub
git push -u origin main
```

## 📝 Daily Workflow (Your Use Case)

### Making Changes on Development Machine

```bash
# 1. Make your changes to files
nano nginx/conf.d/itsm.conf

# 2. Check what changed (like hg status)
git status

# 3. See detailed changes (like hg diff)
git diff

# 4. Stage and commit all changes
git commit -a -m "Update ITSM protected paths"

# Alternative: Add specific files only
git add nginx/conf.d/itsm.conf
git commit -m "Update ITSM protected paths"

# Alternative: Add all changes including new files (like hg addremove)
git add -A
git commit -m "Add new monitoring configs"

# 5. Push to GitHub
git push
```

### Deploying to Production Server

```bash
# SSH to production server
ssh production-server

cd /path/to/edge-auth-stack

# First time only: Clone from GitHub
git clone git@github.com:YOUR_USERNAME/edge-auth-stack.git
cd edge-auth-stack

# Subsequent updates: Pull latest changes
git pull

# Restart services if needed
docker compose up -d
```

## 🔧 Common Operations

### View History
```bash
# Show commit log (like hg log)
git log

# Compact one-line format
git log --oneline

# Last 10 commits
git log -10

# Show changes in a commit
git show COMMIT_HASH
```

### Undo/Revert Changes

```bash
# Discard uncommitted changes to a file (like hg revert)
git restore nginx/nginx.conf

# Discard all uncommitted changes
git restore .

# Unstage a file (but keep changes)
git restore --staged file.txt

# Amend last commit message (before pushing)
git commit --amend -m "Corrected commit message"

# Undo last commit (keep changes as uncommitted)
git reset --soft HEAD~1

# Undo last commit (discard changes - DANGEROUS)
git reset --hard HEAD~1
```

### Working with New Files

```bash
# Add new file (like hg add)
git add new-script.sh

# Add all new files in directory
git add scripts/

# Add everything (new, modified, deleted) - like hg addremove
git add -A

# Check .gitignore is working
git status    # .env should NOT appear
git check-ignore -v .env  # Should show which rule excludes it
```

### Check Remote Status

```bash
# See what commits haven't been pushed yet
git log origin/main..HEAD

# See what commits are on remote but not local
git fetch
git log HEAD..origin/main

# Compare local with remote
git fetch
git status
```

### Stashing (Temporary Shelving)

```bash
# Save uncommitted changes temporarily (like hg shelve)
git stash

# List stashed changes
git stash list

# Restore stashed changes
git stash pop

# Discard stashed changes
git stash drop
```

## ⚡ Quick Command Cheat Sheet

### Most Common Operations
```bash
# Daily workflow (commit all and push)
git commit -a -m "Description of changes"
git push

# Add new files and commit
git add -A
git commit -m "Added new configs"
git push

# Get latest from GitHub
git pull

# Check status
git status

# View history
git log --oneline -10
```

## 🎓 Key Mental Model Differences

### 1. **Three States in Git** (vs two in hg)
```
Working Directory → Staging Area → Repository
                ↑                ↑
            git add          git commit
```

In hg: `Working Directory → Repository` (direct)

### 2. **Staging Area Workflow**
Think of staging as "preparing a commit" - you can selectively choose what to include:

```bash
# Modify 5 files
nano file1.txt file2.txt file3.txt file4.txt file5.txt

# But only commit 2 of them
git add file1.txt file2.txt
git commit -m "Partial update"

# The other 3 files remain modified but uncommitted
```

**When to use**:
- `git add FILE` - Add specific files
- `git add -A` - Add everything (new, modified, deleted) - **use this most often**
- `git commit -a` - Skip staging for tracked files only (doesn't add new files)

### 3. **Branches are Cheap**
Unlike hg, creating branches is instantaneous and encouraged. But for your use case, staying on `main` is fine:

```bash
# Create branch (if you ever need to experiment)
git checkout -b experiment

# Switch back to main
git checkout main

# Delete branch
git branch -d experiment
```

## 🔐 Security Notes

### Files That Should NEVER Be Committed
Already in `.gitignore`:
- `.env` - Contains secrets
- `certs/*.pem` - TLS certificates
- `*.sql` - Database backups
- Volume data directories

### Verify Before First Push
```bash
# Check what's staged
git status

# Ensure .env is NOT listed
# If it is: git rm --cached .env

# Check .gitignore is working
cat .gitignore
git check-ignore -v .env
```

## 🆘 Common Issues & Solutions

### "Your branch is ahead of 'origin/main'"
You have local commits not pushed to GitHub:
```bash
git push
```

### "Your branch is behind 'origin/main'"
Remote has commits you don't have locally:
```bash
git pull
```

### "Merge conflict"
If you edited the same file on dev and production:
```bash
# Git will mark conflicts in the file
nano CONFLICTED_FILE   # Manually resolve, remove <<<< ==== >>>> markers
git add CONFLICTED_FILE
git commit -m "Resolved merge conflict"
```

### Accidentally Committed .env
```bash
# Remove from git but keep local file
git rm --cached .env
git commit -m "Remove .env from git"
git push

# Ensure it's in .gitignore
echo ".env" >> .gitignore
git add .gitignore
git commit -m "Add .env to gitignore"
git push
```

### Want to See What Will Be Pushed
```bash
git log origin/main..HEAD
```

## 📚 Learn More

- **Git vs Mercurial**: https://git-scm.com/book/en/v2
- **GitHub Docs**: https://docs.github.com/en/get-started
- **Interactive Tutorial**: https://learngitbranching.js.org/

## 💡 Tips for Mercurial Users

1. **Get used to `git status`** - Run it often, it's your friend
2. **`git commit -a`** is your hg-like commit (but doesn't add new files)
3. **`git add -A`** is your hg addremove
4. **Staging is actually useful** - you can craft precise commits
5. **`.gitignore` syntax** is almost identical to `.hgignore` (without regex mode)
6. **GitHub is like Bitbucket** - same concept, different platform

## 🔄 Typical Workflow Summary

**Development Machine**:
```bash
# Make changes
nano docker-compose.yml

# Review changes
git status
git diff

# Commit everything
git add -A
git commit -m "Update authentik version to 2024.12"

# Push to GitHub backup
git push
```

**Production Server**:
```bash
# Pull latest changes
git pull

# Apply changes
docker compose pull
docker compose up -d
```

That's it! No complex branching, no merging headaches - just commit, push, pull, deploy.
