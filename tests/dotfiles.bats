#!/usr/bin/env bats

load helpers/setup

@test "dotfiles --help lists the new subcommands" {
  run "$DOTFILES_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"freeze"* ]]
  [[ "$output" == *"status"* ]]
}

@test "push exits 0 when everything is already in sync" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "dotfiles status exits 0 with clean state" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" status
  [ "$status" -eq 0 ]
}

@test "_sha256_file returns the sha256 of a file" {
  make_tmp_world
  run "$DOTFILES_TEST_BIN" sha256 "$TEST_REPO/agents/AGENTS.md"
  [ "$status" -eq 0 ]
  # sha256 of "@~/.agents/AGENTS.md\n" — verify length and hex
  [[ "$output" =~ ^[a-f0-9]{64}$ ]]
}

@test "_sha256_file returns empty string for a missing file" {
  run "$DOTFILES_TEST_BIN" sha256 "/no/such/path"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_manifest_read returns null for an unknown live path" {
  make_tmp_world
  echo '{}' > "$TEST_STATE"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" manifest_read "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "_manifest_write then _manifest_read round-trips a hash" {
  make_tmp_world
  echo '{}' > "$TEST_STATE"
  env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" manifest_write "$TEST_LIVE/.agents/AGENTS.md" "deadbeef"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" manifest_read "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "deadbeef" ]
}

@test "_manifest_delete removes a previously-written key" {
  make_tmp_world
  echo '{}' > "$TEST_STATE"
  env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" manifest_write "$TEST_LIVE/.agents/AGENTS.md" "deadbeef"
  env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" manifest_delete "$TEST_LIVE/.agents/AGENTS.md"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" manifest_read "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "classify: in_sync when repo, live, manifest all match" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "in_sync" ]
}

@test "classify: repo_changed when repo differs from manifest, live matches" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_LIVE/.agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "repo_changed" ]
}

@test "classify: live_changed when live differs from manifest, repo matches" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "live_changed" ]
}

@test "classify: both_changed when both differ from manifest and from each other" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live differently" > "$TEST_LIVE/.agents/AGENTS.md"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "both_changed" ]
}

@test "classify: repo_added when only repo exists" {
  make_tmp_world
  echo '{}' > "$TEST_STATE"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "repo_added" ]
}

@test "classify: live_added when only live exists" {
  make_tmp_world
  echo "live only" > "$TEST_LIVE/.agents/orphan.md"
  echo '{}' > "$TEST_STATE"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/no-such-file.md" "$TEST_LIVE/.agents/orphan.md"
  [ "$status" -eq 0 ]
  [ "$output" = "live_added" ]
}

@test "classify: repo_removed when manifest had it, repo doesn't, live still matches" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  rm "$TEST_REPO/agents/AGENTS.md"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "repo_removed" ]
}

@test "classify: live_removed when manifest had it, live doesn't, repo still matches" {
  make_tmp_world
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  run env DOTFILES_STATE_FILE="$TEST_STATE" "$DOTFILES_TEST_BIN" classify \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  [ "$output" = "live_removed" ]
}

@test "walk_mapping classifies a single-file mapping (in_sync)" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_TEST_BIN" walk
  [ "$status" -eq 0 ]
  [[ "$output" == *"in_sync"* ]]
  [[ "$output" == *"$TEST_REPO/agents/AGENTS.md"* ]]
  [[ "$output" == *"$TEST_LIVE/.agents/AGENTS.md"* ]]
}

@test "walk_mapping recurses into a directory and mirrors to multiple destinations" {
  make_tmp_world
  mkdir -p "$TEST_LIVE/.agents/skills" "$TEST_LIVE/.claude/skills"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.agents/skills/example-skill"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.claude/skills/example-skill"
  hash=$(shasum -a 256 "$TEST_REPO/agents/skills/example-skill/SKILL.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/skills/example-skill/SKILL.md": "$hash",
  "$TEST_LIVE/.claude/skills/example-skill/SKILL.md": "$hash"
}
EOF
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/skills|~/.agents/skills,~/.claude/skills" \
    "$DOTFILES_TEST_BIN" walk
  [ "$status" -eq 0 ]
  # Two mirror destinations, each with one file -> two in_sync lines
  count=$(echo "$output" | grep -c "in_sync")
  [ "$count" -eq 2 ]
}

@test "walk_mapping flags live_changed when one mirror drifts" {
  make_tmp_world
  mkdir -p "$TEST_LIVE/.agents/skills" "$TEST_LIVE/.claude/skills"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.agents/skills/example-skill"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.claude/skills/example-skill"
  hash=$(shasum -a 256 "$TEST_REPO/agents/skills/example-skill/SKILL.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/skills/example-skill/SKILL.md": "$hash",
  "$TEST_LIVE/.claude/skills/example-skill/SKILL.md": "$hash"
}
EOF
  echo "drifted" > "$TEST_LIVE/.claude/skills/example-skill/SKILL.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/skills|~/.agents/skills,~/.claude/skills" \
    "$DOTFILES_TEST_BIN" walk
  [ "$status" -eq 0 ]
  [[ "$output" == *"in_sync"* ]]
  [[ "$output" == *"live_changed"* ]]
}

@test "walk_mapping ignores .DS_Store and Thumbs.db on both sides" {
  make_tmp_world
  mkdir -p "$TEST_LIVE/.agents/skills" "$TEST_LIVE/.claude/skills"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.agents/skills/example-skill"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.claude/skills/example-skill"
  hash=$(shasum -a 256 "$TEST_REPO/agents/skills/example-skill/SKILL.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/skills/example-skill/SKILL.md": "$hash",
  "$TEST_LIVE/.claude/skills/example-skill/SKILL.md": "$hash"
}
EOF
  # Sprinkle OS junk on both sides
  echo "junk" > "$TEST_REPO/agents/skills/.DS_Store"
  echo "junk" > "$TEST_LIVE/.agents/skills/.DS_Store"
  echo "junk" > "$TEST_LIVE/.agents/skills/example-skill/Thumbs.db"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/skills|~/.agents/skills,~/.claude/skills" \
    "$DOTFILES_TEST_BIN" walk
  [ "$status" -eq 0 ]
  [[ "$output" != *".DS_Store"* ]]
  [[ "$output" != *"Thumbs.db"* ]]
}

@test "walk_mapping flags live_added when a directory mirror has an extra file" {
  make_tmp_world
  mkdir -p "$TEST_LIVE/.agents/skills" "$TEST_LIVE/.claude/skills"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.agents/skills/example-skill"
  cp -R "$TEST_REPO/agents/skills/example-skill" "$TEST_LIVE/.claude/skills/example-skill"
  hash=$(shasum -a 256 "$TEST_REPO/agents/skills/example-skill/SKILL.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/skills/example-skill/SKILL.md": "$hash",
  "$TEST_LIVE/.claude/skills/example-skill/SKILL.md": "$hash"
}
EOF
  # Drop an extra file into one of the live mirrors that doesn't exist in the repo
  echo "external addition" > "$TEST_LIVE/.agents/skills/external.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/skills|~/.agents/skills,~/.claude/skills" \
    "$DOTFILES_TEST_BIN" walk
  [ "$status" -eq 0 ]
  [[ "$output" == *"live_added"* ]]
  [[ "$output" == *"external.md"* ]]
}

@test "status prints a summary header and per-state counts" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"agents/claude sync status"* ]]
  [[ "$output" == *"in_sync"* ]]
}

@test "status returns non-zero and prints a diff when conflicts exist" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" status
  [ "$status" -eq 2 ]
  [[ "$output" == *"both_changed"* ]]
  # Diff body is printed inline
  [[ "$output" == *"-edited in repo"* ]]
  [[ "$output" == *"+edited in live"* ]]
}

@test "push copies repo file to live and updates manifest" {
  make_tmp_world
  echo '{}' > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 0 ]
  [ -f "$TEST_LIVE/.agents/AGENTS.md" ]
  diff "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "$hash" ]
}

@test "push leaves live drift untouched and reports it without aborting" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited externally" > "$TEST_LIVE/.agents/AGENTS.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 0 ]
  [[ "$output" == *"live drift"* ]]
  [[ "$output" == *"live_changed"* ]]
  # Live file untouched
  grep -q "edited externally" "$TEST_LIVE/.agents/AGENTS.md"
}

@test "push applies repo_changed and leaves live_changed on a different path" {
  make_tmp_world
  # AGENTS.md: in_sync at first, then we'll introduce live_changed on it
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  # CLAUDE.md: in_sync at first, then we'll introduce repo_changed on it
  cp "$TEST_REPO/claude/CLAUDE.md" "$TEST_LIVE/.claude/CLAUDE.md"
  hash_c=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/AGENTS.md": "$hash_a",
  "$TEST_LIVE/.claude/CLAUDE.md": "$hash_c"
}
EOF
  # AGENTS.md: live_changed on its own
  echo "live edit on agents" > "$TEST_LIVE/.agents/AGENTS.md"
  # CLAUDE.md: repo_changed on its own
  echo "repo edit on claude" > "$TEST_REPO/claude/CLAUDE.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 0 ]
  # Repo edit applied to live
  grep -q "repo edit on claude" "$TEST_LIVE/.claude/CLAUDE.md"
  # Live edit on the other path was left alone
  grep -q "live edit on agents" "$TEST_LIVE/.agents/AGENTS.md"
  # The unharvested live drift was reported
  [[ "$output" == *"live drift"* ]]
  [[ "$output" == *"AGENTS.md"* ]]
}

@test "push refuses to overwrite a symlink at the live destination" {
  make_tmp_world
  ln -s "/some/elsewhere" "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  # Symlink untouched
  [ -L "$TEST_LIVE/.agents/AGENTS.md" ]
}

@test "freeze_agents copies live changes to repo and updates manifest" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_TEST_BIN" freeze_agents
  [ "$status" -eq 0 ]
  diff "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  grep -q "edited in live" "$TEST_REPO/agents/AGENTS.md"
}

@test "freeze_agents leaves repo drift untouched and reports it without aborting" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_TEST_BIN" freeze_agents
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo drift"* ]]
  [[ "$output" == *"repo_changed"* ]]
  # Repo file untouched
  grep -q "edited in repo" "$TEST_REPO/agents/AGENTS.md"
}

@test "freeze_agents captures live_changed and leaves repo_changed on a different path" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  cp "$TEST_REPO/claude/CLAUDE.md" "$TEST_LIVE/.claude/CLAUDE.md"
  hash_c=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/AGENTS.md": "$hash_a",
  "$TEST_LIVE/.claude/CLAUDE.md": "$hash_c"
}
EOF
  # AGENTS.md: live_changed on its own
  echo "live edit on agents" > "$TEST_LIVE/.agents/AGENTS.md"
  # CLAUDE.md: repo_changed on its own
  echo "repo edit on claude" > "$TEST_REPO/claude/CLAUDE.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    "$DOTFILES_TEST_BIN" freeze_agents
  [ "$status" -eq 0 ]
  # Live edit harvested into repo
  grep -q "live edit on agents" "$TEST_REPO/agents/AGENTS.md"
  # Repo edit on the other path was left alone
  grep -q "repo edit on claude" "$TEST_REPO/claude/CLAUDE.md"
  # The unpushed repo drift was reported
  [[ "$output" == *"repo drift"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

@test "push seeds manifest for in_sync paths on first run" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  # Pre-condition: no manifest entry for this live path
  pre=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k] // "absent"' "$TEST_STATE")
  [ "$pre" = "absent" ]
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 0 ]
  # Post-condition: manifest now has an entry equal to the live file's hash
  expected_hash=$(shasum -a 256 "$TEST_LIVE/.agents/AGENTS.md" | awk '{print $1}')
  post=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$post" = "$expected_hash" ]
}

@test "freeze --pre-commit harvests live changes and skips repo_changed paths" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  cp "$TEST_REPO/claude/CLAUDE.md" "$TEST_LIVE/.claude/CLAUDE.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  hash_c=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/AGENTS.md": "$hash_a",
  "$TEST_LIVE/.claude/CLAUDE.md": "$hash_c"
}
EOF
  # Live drift: AGENTS.md edited externally
  echo "drifted" > "$TEST_LIVE/.agents/AGENTS.md"
  # Repo drift: CLAUDE.md edited and presumed staged for commit
  echo "user edit" > "$TEST_REPO/claude/CLAUDE.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    DOTFILES_PRECOMMIT_DRYRUN_GIT=1 \
    "$DOTFILES_BIN" freeze --pre-commit
  [ "$status" -eq 0 ]
  # AGENTS.md harvested
  grep -q "drifted" "$TEST_REPO/agents/AGENTS.md"
  # CLAUDE.md left alone (user edit preserved)
  grep -q "user edit" "$TEST_REPO/claude/CLAUDE.md"
  # Manifest updated for the harvested file
  new_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  manifest_a=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_a" = "$new_hash" ]
  # Manifest for CLAUDE.md unchanged (user edit was preserved, no harvest happened)
  manifest_c=$(jq -r --arg k "$TEST_LIVE/.claude/CLAUDE.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_c" = "$hash_c" ]
}

@test "_offer_merge_conflicts stages four distinctly named inputs for the merge editor" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  CODE_LOG="$stub_dir/calls.log"
  : > "$CODE_LOG"
  cat > "$stub_dir/code" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CODE_LOG"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
n"
  [ "$(wc -l < "$CODE_LOG" | tr -d ' ')" -eq 1 ]
  grep -qF -- "--wait --merge" "$CODE_LOG"
  grep -qF -- "REPO.AGENTS.md" "$CODE_LOG"
  grep -qF -- "LIVE.AGENTS.md" "$CODE_LOG"
  grep -qF -- "BASE.AGENTS.md" "$CODE_LOG"
  grep -qF -- "MERGED.AGENTS.md" "$CODE_LOG"
  # Argument order is left, right, base, result.
  grep -qE -- "REPO\.AGENTS\.md .*LIVE\.AGENTS\.md .*BASE\.AGENTS\.md .*MERGED\.AGENTS\.md" "$CODE_LOG"
}

@test "_offer_merge_conflicts writes the merged result to both sides and refreshes the manifest" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
# Simulate a completed merge: last arg is the result file.
printf 'merged result\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
y"
  [ "$status" -eq 0 ]
  grep -q "merged result" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged result" "$TEST_LIVE/.agents/AGENTS.md"
  merged_hash=$(shasum -a 256 "$TEST_LIVE/.agents/AGENTS.md" | awk '{print $1}')
  manifest=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest" = "$merged_hash" ]
}

@test "_offer_merge_conflicts leaves both sides alone when the apply prompt is declined" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged result\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
n"
  [ "$status" -eq 1 ]
  grep -q "repo side" "$TEST_REPO/agents/AGENTS.md"
  grep -q "live side" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k] // "absent"' "$TEST_STATE")" = "absent" ]
}

@test "_offer_merge_conflicts warns when the result still has conflict markers" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf '<<<<<<< REPO\nrepo side\n=======\nlive side\n>>>>>>> LIVE\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
n"
  [[ "$output" == *"conflict markers"* ]]
  grep -q "repo side" "$TEST_REPO/agents/AGENTS.md"
}

@test "_offer_merge_conflicts opens nothing when the first prompt is declined" {
  stub_dir="$(mktemp -d)"
  CODE_LOG="$stub_dir/calls.log"
  : > "$CODE_LOG"
  cat > "$stub_dir/code" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CODE_LOG"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts "/tmp/r1|/tmp/l1" <<< "n"
  [ "$status" -eq 1 ]
  [ ! -s "$CODE_LOG" ]
}

@test "_offer_merge_conflicts is silent and skipped in non-interactive shells" {
  stub_dir="$(mktemp -d)"
  CODE_LOG="$stub_dir/calls.log"
  : > "$CODE_LOG"
  cat > "$stub_dir/code" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CODE_LOG"
EOF
  chmod +x "$stub_dir/code"
  # No DOTFILES_ASSUME_INTERACTIVE - helpers/setup detaches stdin from any tty.
  run env \
    PATH="$stub_dir:$PATH" \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts "/tmp/r1|/tmp/l1"
  [ "$status" -eq 1 ]
  [ ! -s "$CODE_LOG" ]
  [[ "$output" != *"--merge"* ]]
}

@test "push exits non-zero on conflicts without prompting in non-interactive shells" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 2 ]
  [[ "$output" != *"--merge"* ]]
  # The inline diff is still printed.
  [[ "$output" == *"-edited in repo"* ]]
  [[ "$output" == *"+edited in live"* ]]
}

@test "_pair_is_byte_identical returns 0 when both files match, 1 otherwise" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  run "$DOTFILES_TEST_BIN" pair_is_byte_identical \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 0 ]
  echo "different" > "$TEST_LIVE/.agents/AGENTS.md"
  run "$DOTFILES_TEST_BIN" pair_is_byte_identical \
    "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 1 ]
}

@test "_pair_is_byte_identical returns 1 when either file is missing" {
  make_tmp_world
  run "$DOTFILES_TEST_BIN" pair_is_byte_identical \
    "$TEST_REPO/agents/AGENTS.md" "/no/such/path"
  [ "$status" -eq 1 ]
  run "$DOTFILES_TEST_BIN" pair_is_byte_identical \
    "/no/such/path" "/another/missing"
  [ "$status" -eq 1 ]
}

@test "status appends (byte-identical) when sides match but manifest is stale" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  # Manifest hash is stale — does not match either side
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" status
  [ "$status" -eq 2 ]
  [[ "$output" == *"both_changed"* ]]
  [[ "$output" == *"(byte-identical)"* ]]
  # No diff section, since byte-identical pairs have nothing to diff
  [[ "$output" != *"conflict diffs:"* ]]
}

@test "status shows (byte-identical) only on matching pairs in a mixed conflict set" {
  make_tmp_world
  # AGENTS.md: byte-identical (sides match, manifest stale)
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  # CLAUDE.md: true conflict (sides differ)
  cp "$TEST_REPO/claude/CLAUDE.md" "$TEST_LIVE/.claude/CLAUDE.md"
  hash_c=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/AGENTS.md": "deadbeef",
  "$TEST_LIVE/.claude/CLAUDE.md": "$hash_c"
}
EOF
  echo "edited in repo" > "$TEST_REPO/claude/CLAUDE.md"
  echo "edited in live" > "$TEST_LIVE/.claude/CLAUDE.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    "$DOTFILES_BIN" status
  [ "$status" -eq 2 ]
  # AGENTS.md line carries the marker; CLAUDE.md line does not
  [[ "$output" =~ AGENTS\.md.*\(byte-identical\) ]]
  [[ ! "$output" =~ CLAUDE\.md.*\(byte-identical\) ]]
  # Only the true conflict shows up in the diff section
  [[ "$output" == *"conflict diffs:"* ]]
  [[ "$output" == *"-edited in repo"* ]]
  [[ "$output" == *"+edited in live"* ]]
}

@test "push auto-resolves byte-identical conflicts when prompt accepted" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  shared_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "y"
  [ "$status" -eq 0 ]
  [[ "$output" == *"byte-identical conflicts"* ]]
  [[ "$output" == *"resolved"* ]]
  # Manifest now matches the shared content hash
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "$shared_hash" ]
}

@test "push aborts when byte-identical prompt is declined" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "n"
  [ "$status" -eq 2 ]
  [[ "$output" == *"byte-identical conflicts"* ]]
  [[ "$output" == *"resolve conflicts manually"* ]]
  # Manifest unchanged
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "deadbeef" ]
}

@test "push aborts on byte-identical conflicts in non-interactive shells" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" push
  [ "$status" -eq 2 ]
  [[ "$output" == *"byte-identical conflicts"* ]]
  # No prompt was emitted
  [[ "$output" != *"auto-resolve"* ]]
  # Manifest unchanged
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "deadbeef" ]
}

@test "push resolves byte-identical and still aborts on a true conflict alongside it" {
  make_tmp_world
  # AGENTS.md: byte-identical
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  # CLAUDE.md: true content conflict
  cp "$TEST_REPO/claude/CLAUDE.md" "$TEST_LIVE/.claude/CLAUDE.md"
  hash_c=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/AGENTS.md": "deadbeef",
  "$TEST_LIVE/.claude/CLAUDE.md": "$hash_c"
}
EOF
  echo "repo edit" > "$TEST_REPO/claude/CLAUDE.md"
  echo "live edit" > "$TEST_LIVE/.claude/CLAUDE.md"
  shared_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "y"
  [ "$status" -eq 2 ]
  # AGENTS.md got auto-resolved
  manifest_a=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_a" = "$shared_a" ]
  # CLAUDE.md still triggers the true-conflict abort path with diff output
  [[ "$output" == *"conflicts on the same path"* ]]
  [[ "$output" == *"-repo edit"* ]]
  [[ "$output" == *"+live edit"* ]]
}

@test "freeze_agents auto-resolves byte-identical conflicts when prompt accepted" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  shared_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents <<< "y"
  [ "$status" -eq 0 ]
  [[ "$output" == *"byte-identical conflicts"* ]]
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "$shared_hash" ]
}

@test "freeze --pre-commit auto-resolves byte-identical conflicts when accepted" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  shared_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    DOTFILES_PRECOMMIT_DRYRUN_GIT=1 \
    "$DOTFILES_BIN" freeze --pre-commit <<< "y"
  [ "$status" -eq 0 ]
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "$shared_hash" ]
}

@test "_offer_resolve_byte_identical writes manifest hashes when accepted" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  shared_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  run env \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_resolve_byte_identical \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y"
  [ "$status" -eq 0 ]
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "$shared_hash" ]
}

@test "_offer_resolve_byte_identical leaves manifest untouched when declined" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  run env \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_resolve_byte_identical \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "n"
  [ "$status" -eq 1 ]
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "deadbeef" ]
}

@test "_offer_resolve_byte_identical is silent and declines in non-interactive shells" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"deadbeef\"}" > "$TEST_STATE"
  run env \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    "$DOTFILES_TEST_BIN" offer_resolve_byte_identical \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -eq 1 ]
  [[ "$output" != *"auto-resolve"* ]]
  manifest_hash=$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")
  [ "$manifest_hash" = "deadbeef" ]
}

@test "freeze --pre-commit aborts on both_changed without harvesting other live_changed files" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  cp "$TEST_REPO/claude/CLAUDE.md" "$TEST_LIVE/.claude/CLAUDE.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  hash_c=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  cat > "$TEST_STATE" <<EOF
{
  "$TEST_LIVE/.agents/AGENTS.md": "$hash_a",
  "$TEST_LIVE/.claude/CLAUDE.md": "$hash_c"
}
EOF
  # AGENTS.md: live_changed only (would harvest cleanly under the buggy flow)
  echo "live drift only" > "$TEST_LIVE/.agents/AGENTS.md"
  # CLAUDE.md: both_changed (forces an abort)
  echo "repo edit" > "$TEST_REPO/claude/CLAUDE.md"
  echo "live edit" > "$TEST_LIVE/.claude/CLAUDE.md"
  # Snapshot AGENTS.md repo content before run
  agents_before=$(cat "$TEST_REPO/agents/AGENTS.md")
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    DOTFILES_PRECOMMIT_DRYRUN_GIT=1 \
    "$DOTFILES_BIN" freeze --pre-commit
  [ "$status" -eq 2 ]
  [[ "$output" == *"both_changed"* ]]
  [[ "$output" == *"-repo edit"* ]]
  [[ "$output" == *"+live edit"* ]]
  # AGENTS.md repo file was NOT mutated despite being live_changed (proves abort happened before harvest)
  agents_after=$(cat "$TEST_REPO/agents/AGENTS.md")
  [ "$agents_before" = "$agents_after" ]
}

@test "push resolves its only conflict and completes" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "y
y"
  [ "$status" -eq 0 ]
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged by hand" "$TEST_LIVE/.agents/AGENTS.md"
  [[ "$output" == *"resolved"* ]]
}

@test "push still exits 2 when a conflict is left unresolved" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "y
n"
  [ "$status" -eq 2 ]
  grep -q "edited in repo" "$TEST_REPO/agents/AGENTS.md"
  grep -q "edited in live" "$TEST_LIVE/.agents/AGENTS.md"
}

@test "freeze resolves its only conflict and completes" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents <<< "y
y"
  [ "$status" -eq 0 ]
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged by hand" "$TEST_LIVE/.agents/AGENTS.md"
}

@test "freeze --pre-commit resolves a conflict and stages the repo side" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_PRECOMMIT_DRYRUN_GIT=1 \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" freeze --pre-commit <<< "y
y"
  [ "$status" -eq 0 ]
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged by hand" "$TEST_LIVE/.agents/AGENTS.md"
}

@test "status resolves a conflict and exits clean" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" status <<< "y
y"
  [ "$status" -eq 0 ]
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged by hand" "$TEST_LIVE/.agents/AGENTS.md"
}

@test "_offer_merge_conflicts refuses a symlinked side from a non-push caller" {
  make_tmp_world
  # freeze_agents has no symlink guard of its own, so this exercises the
  # refusal inside the shared helper.
  printf 'unrelated target\n' > "$TEST_LIVE/outside.md"
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  ln -sf "$TEST_LIVE/outside.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/claude/CLAUDE.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  CODE_LOG="$stub_dir/calls.log"
  : > "$CODE_LOG"
  cat > "$stub_dir/code" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CODE_LOG"
printf 'merged by hand\n' > "\${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents <<< "y
y"
  [ "$status" -eq 2 ]
  [[ "$output" == *"symlink"* ]]
  # The editor never opened and the symlink target was never written through.
  [ ! -s "$CODE_LOG" ]
  grep -q "unrelated target" "$TEST_LIVE/outside.md"
  grep -q "edited in repo" "$TEST_REPO/agents/AGENTS.md"
}

@test "freeze does not harvest a stale live copy over a just-merged repo file" {
  make_tmp_world
  # agents/skills maps to two live destinations, so one repo file sits in two
  # pairs. Pair 1 is a conflict; pair 2 is anchored to the current repo content
  # and only its live side drifted, so phase 1 calls it live_changed.
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'edited in live one\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf 'edited in live two\n' > "$TEST_LIVE/.claude/AGENTS.md"
  repo_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  jq -n --arg k1 "$TEST_LIVE/.agents/AGENTS.md" \
        --arg k2 "$TEST_LIVE/.claude/AGENTS.md" \
        --arg anchor1 "0000000000000000000000000000000000000000000000000000000000000000" \
        --arg anchor2 "$repo_hash" \
        '{($k1): $anchor1, ($k2): $anchor2}' > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md,~/.claude/AGENTS.md" \
    "$DOTFILES_TEST_BIN" walk
  [[ "$output" == *"both_changed	$TEST_REPO/agents/AGENTS.md	$TEST_LIVE/.agents/AGENTS.md"* ]]
  [[ "$output" == *"live_changed	$TEST_REPO/agents/AGENTS.md	$TEST_LIVE/.claude/AGENTS.md"* ]]

  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md,~/.claude/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents <<< "y
y"
  # The merged result survives on both sides of the pair that was resolved.
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged by hand" "$TEST_LIVE/.agents/AGENTS.md"
  merged_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  [ "$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")" = "$merged_hash" ]
  # The second destination now genuinely conflicts, so freeze reports it rather
  # than harvesting it over the merge.
  [ "$status" -eq 2 ]
  grep -q "edited in live two" "$TEST_LIVE/.claude/AGENTS.md"
}

@test "_offer_merge_conflicts leaves the manifest alone when a copy fails" {
  if [ "$(id -u)" -eq 0 ]; then
    skip "cp cannot fail on permissions when running as root"
  fi
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  chmod 444 "$TEST_REPO/agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged result\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to write"* ]]
  # Neither side was rewritten and no anchor was recorded, so the path stays
  # classified as a conflict.
  grep -q "repo side" "$TEST_REPO/agents/AGENTS.md"
  grep -q "live side" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k] // "absent"' "$TEST_STATE")" = "absent" ]
}

@test "freeze --pre-commit stages the merged repo file in the override root" {
  make_tmp_world
  git -c init.defaultBranch=main init -q "$TEST_REPO"
  git -C "$TEST_REPO" add agents/AGENTS.md
  git -C "$TEST_REPO" commit -qm "seed"
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  manifest_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$manifest_hash\"}" > "$TEST_STATE"
  echo "edited in repo" > "$TEST_REPO/agents/AGENTS.md"
  echo "edited in live" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  # No DOTFILES_PRECOMMIT_DRYRUN_GIT: the real `git add` branch runs, against
  # the temp repo rather than this one.
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents_precommit <<< "y
y"
  [ "$status" -eq 0 ]
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  run git -C "$TEST_REPO" diff --cached --name-only
  [[ "$output" == *"agents/AGENTS.md"* ]]
}

@test "_offer_merge_conflicts hands the editor a base of the shared lines only" {
  make_tmp_world
  printf 'line one\nrepo only\nline three\n\nshared tail\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'line one\nlive only\nline three\n\nshared tail\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  BASE_COPY="$stub_dir/base-seen"
  cat > "$stub_dir/code" <<EOF
#!/usr/bin/env bash
# args: --wait --merge <left> <right> <base> <result>
cp "\$5" "$BASE_COPY"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
n"
  # Common lines only: each side's unique line is absent, so the editor sees it
  # as an addition instead of unchanged context. The shared blank line survives.
  [ "$(cat "$BASE_COPY")" = "$(printf 'line one\nline three\n\nshared tail')" ]
}

@test "_offer_merge_conflicts leaves a pair alone when the editor exits non-zero" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged result\n' > "${!#}"
exit 3
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"editor exited 3"* ]]
  grep -q "repo side" "$TEST_REPO/agents/AGENTS.md"
  grep -q "live side" "$TEST_LIVE/.agents/AGENTS.md"
  [ "$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k] // "absent"' "$TEST_STATE")" = "absent" ]
}

@test "_offer_merge_conflicts reports when code is missing from PATH" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  # A PATH with the system utilities but no VS Code install on it.
  run env \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'code' is not on PATH"* ]]
  grep -q "repo side" "$TEST_REPO/agents/AGENTS.md"
  grep -q "live side" "$TEST_LIVE/.agents/AGENTS.md"
}

@test "push rebuilds its lists after a resolution and reports the new conflict" {
  make_tmp_world
  # agents/AGENTS.md maps to two live destinations. Pair 1 is a conflict; pair 2
  # is anchored to the current repo content with only its live side drifted, so
  # phase 1 files it as informational drift rather than a conflict.
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'edited in live one\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf 'edited in live two\n' > "$TEST_LIVE/.claude/AGENTS.md"
  repo_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  jq -n --arg k1 "$TEST_LIVE/.agents/AGENTS.md" \
        --arg k2 "$TEST_LIVE/.claude/AGENTS.md" \
        --arg anchor1 "0000000000000000000000000000000000000000000000000000000000000000" \
        --arg anchor2 "$repo_hash" \
        '{($k1): $anchor1, ($k2): $anchor2}' > "$TEST_STATE"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md,~/.claude/AGENTS.md" \
    "$DOTFILES_TEST_BIN" walk
  [[ "$output" == *"both_changed	$TEST_REPO/agents/AGENTS.md	$TEST_LIVE/.agents/AGENTS.md"* ]]
  [[ "$output" == *"live_changed	$TEST_REPO/agents/AGENTS.md	$TEST_LIVE/.claude/AGENTS.md"* ]]

  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md,~/.claude/AGENTS.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "y
y"
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "merged by hand" "$TEST_LIVE/.agents/AGENTS.md"
  # The merge made destination 2 a real conflict, so push must re-walk and
  # report it instead of finishing on the pre-merge classification.
  [ "$status" -eq 2 ]
  [[ "$output" == *"re-run push"* ]]
  grep -q "edited in live two" "$TEST_LIVE/.claude/AGENTS.md"
}

@test "freeze --pre-commit rebuilds its harvest list after a resolution" {
  make_tmp_world
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'edited in live one\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf 'edited in live two\n' > "$TEST_LIVE/.claude/AGENTS.md"
  repo_hash=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  jq -n --arg k1 "$TEST_LIVE/.agents/AGENTS.md" \
        --arg k2 "$TEST_LIVE/.claude/AGENTS.md" \
        --arg anchor1 "0000000000000000000000000000000000000000000000000000000000000000" \
        --arg anchor2 "$repo_hash" \
        '{($k1): $anchor1, ($k2): $anchor2}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md,~/.claude/AGENTS.md" \
    DOTFILES_PRECOMMIT_DRYRUN_GIT=1 \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents_precommit <<< "y
y"
  # Harvesting destination 2 from the pre-merge list would copy it over the
  # merged repo file. The re-walk sees the new conflict and aborts instead.
  [ "$status" -eq 2 ]
  grep -q "merged by hand" "$TEST_REPO/agents/AGENTS.md"
  grep -q "edited in live two" "$TEST_LIVE/.claude/AGENTS.md"
}

@test "_manifest_write refuses to blank the manifest when jq fails" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf '{"seeded":"anchor"}\n' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged result\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  # jq fails for every invocation, so the manifest write cannot produce content.
  cat > "$stub_dir/jq" <<'EOF'
#!/usr/bin/env bash
echo "stub jq failure" >&2
exit 1
EOF
  chmod +x "$stub_dir/jq"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
y"
  # The truncated temp file must never be moved over the state file, and the
  # failure has to surface as an unresolved pair rather than a resolution.
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to record"* ]]
  [[ "$output" != *"resolved"* ]]
  [ "$(cat "$TEST_STATE")" = '{"seeded":"anchor"}' ]
}

@test "_manifest_write reports failure when the manifest move fails" {
  make_tmp_world
  printf 'repo side\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'live side\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf '{"seeded":"anchor"}\n' > "$TEST_STATE"
  manifest_before="$(mktemp)"
  cp "$TEST_STATE" "$manifest_before"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged result\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  real_mv="$(command -v mv)"
  # Only the move that installs the manifest fails; every other mv is real.
  cat > "$stub_dir/mv" <<EOF
#!/usr/bin/env bash
if [ "\${!#}" = "$TEST_STATE" ]; then
  echo "stub mv: refusing to install the manifest" >&2
  exit 1
fi
exec "$real_mv" "\$@"
EOF
  chmod +x "$stub_dir/mv"
  # Pin the manifest temp path so the failure path's cleanup is observable. The
  # merge staging directory is built with `mktemp -d`, so passing every
  # argument-bearing call through keeps that one on the real mktemp.
  temp_file="$stub_dir/manifest-temp"
  real_mktemp="$(command -v mktemp)"
  cat > "$stub_dir/mktemp" <<EOF
#!/usr/bin/env bash
if [ "\$#" -gt 0 ]; then
  exec "$real_mktemp" "\$@"
fi
: > "$temp_file"
echo "$temp_file"
EOF
  chmod +x "$stub_dir/mktemp"
  # _merge_apply_result reads the return value, which disables set -e inside
  # _manifest_write, so the failed move is only visible if the function reports
  # it. Both copies have already landed by then, so a silent success would
  # record the pair as resolved against a manifest that never changed.
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" offer_merge_conflicts \
      "$TEST_REPO/agents/AGENTS.md|$TEST_LIVE/.agents/AGENTS.md" <<< "y
y"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to record"* ]]
  [[ "$output" != *"resolved"* ]]
  cmp -s "$manifest_before" "$TEST_STATE"
  [ ! -e "$temp_file" ]
}

@test "_manifest_delete refuses to blank the manifest when jq fails" {
  make_tmp_world
  printf '{"seeded":"anchor","%s":"deadbeef"}\n' "$TEST_LIVE/.agents/AGENTS.md" > "$TEST_STATE"
  before="$(cat "$TEST_STATE")"
  stub_dir="$(mktemp -d)"
  real_jq="$(command -v jq)"
  # `del(` appears only in the delete's own rewrite, so _manifest_ensure and
  # every read still reach the real jq while that one invocation fails.
  cat > "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *"del("* ]]; then
  echo "stub jq: refusing to rewrite the manifest" >&2
  exit 1
fi
exec "$real_jq" "\$@"
EOF
  chmod +x "$stub_dir/jq"
  # Pin the temp path so the failure path's cleanup is observable.
  temp_file="$stub_dir/manifest-temp"
  cat > "$stub_dir/mktemp" <<EOF
#!/usr/bin/env bash
: > "$temp_file"
echo "$temp_file"
EOF
  chmod +x "$stub_dir/mktemp"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    "$DOTFILES_TEST_BIN" manifest_delete "$TEST_LIVE/.agents/AGENTS.md"
  # The truncated temp file must never be moved over the state file, and the
  # failure has to clean up after itself rather than tripping the EXIT trap.
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_STATE")" = "$before" ]
  [ ! -e "$temp_file" ]
  [[ "$output" != *"unbound variable"* ]]
}

@test "_manifest_delete reports failure when the manifest move fails" {
  make_tmp_world
  printf '{"seeded":"anchor","%s":"deadbeef"}\n' "$TEST_LIVE/.agents/AGENTS.md" > "$TEST_STATE"
  manifest_before="$(mktemp)"
  cp "$TEST_STATE" "$manifest_before"
  stub_dir="$(mktemp -d)"
  real_mv="$(command -v mv)"
  # Only the move that installs the manifest fails; every other mv is real.
  cat > "$stub_dir/mv" <<EOF
#!/usr/bin/env bash
if [ "\${!#}" = "$TEST_STATE" ]; then
  echo "stub mv: refusing to install the manifest" >&2
  exit 1
fi
exec "$real_mv" "\$@"
EOF
  chmod +x "$stub_dir/mv"
  # Pin the temp path so the failure path's cleanup is observable.
  temp_file="$stub_dir/manifest-temp"
  cat > "$stub_dir/mktemp" <<EOF
#!/usr/bin/env bash
: > "$temp_file"
echo "$temp_file"
EOF
  chmod +x "$stub_dir/mktemp"
  # Every call site is a bare command, so set -e already aborts on the failing
  # move and the status is non-zero either way. What the check buys is clearing
  # the trap while $tmp is still in scope, instead of leaving it to fire at exit
  # under set -u and die on the unbound local before the rm runs.
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    "$DOTFILES_TEST_BIN" manifest_delete "$TEST_LIVE/.agents/AGENTS.md"
  [ "$status" -ne 0 ]
  cmp -s "$manifest_before" "$TEST_STATE"
  [ ! -e "$temp_file" ]
  [[ "$output" != *"unbound variable"* ]]
}

@test "freeze --pre-commit keeps a pair whose staging failed after both sides were written" {
  make_tmp_world
  git -c init.defaultBranch=main init -q "$TEST_REPO"
  # Two conflicting pairs and an empty manifest: with no anchor, a pair whose
  # sides were both rewritten by a failed resolution classifies as in_sync.
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'edited in live\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf 'claude edited in repo\n' > "$TEST_REPO/claude/CLAUDE.md"
  printf 'claude edited in live\n' > "$TEST_LIVE/.claude/CLAUDE.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  real_git="$(command -v git)"
  cat > "$stub_dir/git" <<EOF
#!/usr/bin/env bash
# Fail staging for the second pair only; everything else is real git.
if [ "\$1" = "-C" ] && [ "\$3" = "add" ] && [ "\${!#}" = "$TEST_REPO/claude/CLAUDE.md" ]; then
  echo "stub: refusing to stage \${!#}" >&2
  exit 1
fi
exec "$real_git" "\$@"
EOF
  chmod +x "$stub_dir/git"
  # No DOTFILES_PRECOMMIT_DRYRUN_GIT, so the helper's real `git add` runs.
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents_precommit <<< "y
y
y
y"
  [[ "$output" == *"failed to stage"* ]]
  # The unresolved pair now looks in_sync to a fresh walk, so only carrying
  # _MERGE_UNRESOLVED over keeps it reported and the commit blocked.
  [ "$status" -eq 2 ]
  [[ "$output" == *"resolve manually"* ]]
  run git -C "$TEST_REPO" diff --cached --name-only
  [[ "$output" != *"claude/CLAUDE.md"* ]]
}

@test "push keeps a pair whose manifest write failed after both sides were written" {
  make_tmp_world
  # Two conflicting pairs and an empty manifest: with no anchor, a pair whose
  # sides were both rewritten by a failed resolution classifies as in_sync.
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'edited in live\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf 'claude edited in repo\n' > "$TEST_REPO/claude/CLAUDE.md"
  printf 'claude edited in live\n' > "$TEST_LIVE/.claude/CLAUDE.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  real_jq="$(command -v jq)"
  # _MERGE_GIT_ADD is unset outside the pre-commit path, so _manifest_write is
  # the only step left that can fail once both copies have landed. It passes
  # `--arg v` and _manifest_read does not, so failing on that flag alone breaks
  # the second pair's write while every read still reaches the real jq.
  cat > "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" --arg v "* && " \$* " == *" $TEST_LIVE/.claude/CLAUDE.md "* ]]; then
  echo "stub jq: refusing to write the manifest entry" >&2
  exit 1
fi
exec "$real_jq" "\$@"
EOF
  chmod +x "$stub_dir/jq"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_BIN" push <<< "y
y
y"
  [[ "$output" == *"failed to record $TEST_LIVE/.claude/CLAUDE.md"* ]]
  # Both copies landed before the manifest write failed, so a fresh walk reads
  # the pair as in_sync. Only carrying _MERGE_UNRESOLVED over keeps it reported.
  [ "$status" -eq 2 ]
  [[ "$output" == *"re-run push"* ]]
  [[ "$output" != *"push complete"* ]]
  grep -q "merged by hand" "$TEST_REPO/claude/CLAUDE.md"
  grep -q "merged by hand" "$TEST_LIVE/.claude/CLAUDE.md"
  [ "$(jq -r --arg k "$TEST_LIVE/.claude/CLAUDE.md" '.[$k] // "null"' "$TEST_STATE")" = "null" ]
}

@test "freeze keeps a pair whose manifest write failed after both sides were written" {
  make_tmp_world
  printf 'edited in repo\n' > "$TEST_REPO/agents/AGENTS.md"
  printf 'edited in live\n' > "$TEST_LIVE/.agents/AGENTS.md"
  printf 'claude edited in repo\n' > "$TEST_REPO/claude/CLAUDE.md"
  printf 'claude edited in live\n' > "$TEST_LIVE/.claude/CLAUDE.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
printf 'merged by hand\n' > "${!#}"
EOF
  chmod +x "$stub_dir/code"
  real_jq="$(command -v jq)"
  cat > "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" --arg v "* && " \$* " == *" $TEST_LIVE/.claude/CLAUDE.md "* ]]; then
  echo "stub jq: refusing to write the manifest entry" >&2
  exit 1
fi
exec "$real_jq" "\$@"
EOF
  chmod +x "$stub_dir/jq"
  # freeze_agents, not the public `freeze`: this asserts on the agent-sync
  # output alone, which the other freeze phases would bury.
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md
claude/CLAUDE.md|~/.claude/CLAUDE.md" \
    DOTFILES_ASSUME_INTERACTIVE=1 \
    "$DOTFILES_TEST_BIN" freeze_agents <<< "y
y
y"
  [[ "$output" == *"failed to record $TEST_LIVE/.claude/CLAUDE.md"* ]]
  [ "$status" -eq 2 ]
  [[ "$output" == *"re-run freeze"* ]]
  [[ "$output" != *"captured"* ]]
  grep -q "merged by hand" "$TEST_REPO/claude/CLAUDE.md"
  grep -q "merged by hand" "$TEST_LIVE/.claude/CLAUDE.md"
  [ "$(jq -r --arg k "$TEST_LIVE/.claude/CLAUDE.md" '.[$k] // "null"' "$TEST_STATE")" = "null" ]
}

@test "freeze_vscode writes the extensions file under the overridden root" {
  make_freeze_world
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
echo "publisher.installed"
EOF
  chmod +x "$stub_dir/code"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    "$DOTFILES_TEST_BIN" freeze_vscode
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_REPO/vscode/extensions.txt")" = "publisher.installed" ]
}

@test "freeze_brew reads the Brewfile under the overridden root" {
  make_freeze_world
  stub_dir="$(mktemp -d)"
  # Nothing installed, so every formula the Brewfile declares is reported
  # missing - which is what names the file the helper actually read.
  cat > "$stub_dir/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/brew"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    "$DOTFILES_TEST_BIN" freeze_brew
  [ "$status" -eq 0 ]
  [[ "$output" == *"temp-root-only-formula"* ]]
  [[ "$output" == *"temp-root-only-cask"* ]]
}

@test "freeze --pre-commit stages the harvested file in the overridden repo" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash_a\"}" > "$TEST_STATE"
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit -qm "seed"
  echo "drifted" > "$TEST_LIVE/.agents/AGENTS.md"
  # No DOTFILES_PRECOMMIT_DRYRUN_GIT: this is the real staging path.
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" freeze --pre-commit
  [ "$status" -eq 0 ]
  grep -q "drifted" "$TEST_REPO/agents/AGENTS.md"
  git -C "$TEST_REPO" diff --cached --name-only | grep -qx "agents/AGENTS.md"
}

@test "freeze --pre-commit leaves the manifest alone when staging a harvest fails" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash_a\"}" > "$TEST_STATE"
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit -qm "seed"
  echo "drifted" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  real_git="$(command -v git)"
  cat > "$stub_dir/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$3" = "add" ] && [ "\${!#}" = "$TEST_REPO/agents/AGENTS.md" ]; then
  echo "stub: refusing to stage \${!#}" >&2
  exit 1
fi
exec "$real_git" "\$@"
EOF
  chmod +x "$stub_dir/git"
  # No DOTFILES_PRECOMMIT_DRYRUN_GIT: this is the real staging path.
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" freeze --pre-commit
  [ "$status" -eq 2 ]
  [[ "$output" == *"failed to stage $TEST_REPO/agents/AGENTS.md"* ]]
  # Nothing may be claimed as captured when the file never reached the index.
  [[ "$output" != *"auto-harvested"* ]]
  run git -C "$TEST_REPO" diff --cached --name-only
  [[ "$output" != *"agents/AGENTS.md"* ]]
  # The anchor still names the pre-drift content and the repo side was rolled
  # back, so the pair stays live_changed rather than reading in_sync (which
  # would drop the harvest) or both_changed (which no hook could resolve).
  [ "$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")" = "$hash_a" ]
  ! grep -q "drifted" "$TEST_REPO/agents/AGENTS.md"
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_TEST_BIN" walk
  [[ "$output" == live_changed* ]]

  # The retry, with staging working again, has to complete the harvest.
  run env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" freeze --pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"auto-harvested"* ]]
  grep -q "drifted" "$TEST_REPO/agents/AGENTS.md"
  git -C "$TEST_REPO" diff --cached --name-only | grep -qx "agents/AGENTS.md"
}

@test "freeze --pre-commit reports the path when recording a harvest fails" {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  hash_a=$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')
  echo "{\"$TEST_LIVE/.agents/AGENTS.md\":\"$hash_a\"}" > "$TEST_STATE"
  echo "drifted" > "$TEST_LIVE/.agents/AGENTS.md"
  stub_dir="$(mktemp -d)"
  real_jq="$(command -v jq)"
  # Only _manifest_write passes `--arg v`, so failing on that flag breaks the
  # harvest's write while every _manifest_read still reaches the real jq.
  cat > "$stub_dir/jq" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" --arg v "* && " \$* " == *" $TEST_LIVE/.agents/AGENTS.md "* ]]; then
  echo "stub jq: refusing to write the manifest entry" >&2
  exit 1
fi
exec "$real_jq" "\$@"
EOF
  chmod +x "$stub_dir/jq"
  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_PRECOMMIT_DRYRUN_GIT=1 \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_TEST_BIN" freeze_agents_precommit
  [ "$status" -eq 2 ]
  [[ "$output" == *"failed to record $TEST_LIVE/.agents/AGENTS.md in the sync manifest"* ]]
  [[ "$output" != *"auto-harvested"* ]]
  [ "$(jq -r --arg k "$TEST_LIVE/.agents/AGENTS.md" '.[$k]' "$TEST_STATE")" = "$hash_a" ]
}

@test "freeze against an overridden root leaves the real repo untouched" {
  make_freeze_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  echo '{}' > "$TEST_STATE"
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/code" <<'EOF'
#!/usr/bin/env bash
echo "publisher.installed"
EOF
  cat > "$stub_dir/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$stub_dir/code" "$stub_dir/brew"

  real_ext="$DOTFILES_ROOT/vscode/extensions.txt"
  real_brewfile="$DOTFILES_ROOT/brew/Brewfile"
  cp "$real_ext" "$stub_dir/extensions.bak"
  cp "$real_brewfile" "$stub_dir/Brewfile.bak"
  status_before="$(git -C "$DOTFILES_ROOT" status --porcelain)"

  run env \
    PATH="$stub_dir:$PATH" \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$DOTFILES_BIN" freeze

  # Record the verdict, then put the real files back before asserting. A
  # regression here writes to the developer's working tree, and a test that
  # detects that must not also leave it that way.
  ext_intact=0; cmp -s "$real_ext" "$stub_dir/extensions.bak" || ext_intact=1
  brew_intact=0; cmp -s "$real_brewfile" "$stub_dir/Brewfile.bak" || brew_intact=1
  cp "$stub_dir/extensions.bak" "$real_ext"
  cp "$stub_dir/Brewfile.bak" "$real_brewfile"

  [ "$status" -eq 0 ]
  [ "$ext_intact" -eq 0 ]
  [ "$brew_intact" -eq 0 ]
  # Catches stray files dropped in the repo root as well as tracked-file edits.
  [ "$(git -C "$DOTFILES_ROOT" status --porcelain)" = "$status_before" ]
  # The overridden root is where the write should have landed.
  [ "$(cat "$TEST_REPO/vscode/extensions.txt")" = "publisher.installed" ]
}
