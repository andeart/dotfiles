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

@test "_offer_open_conflicts opens each pair via 'code --diff' when accepted" {
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
    "$DOTFILES_TEST_BIN" offer_open_conflicts "/tmp/r1|/tmp/l1" "/tmp/r2|/tmp/l2" <<< "y"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CODE_LOG" | tr -d ' ')" -eq 2 ]
  grep -qF -- "--diff /tmp/r1 /tmp/l1" "$CODE_LOG"
  grep -qF -- "--diff /tmp/r2 /tmp/l2" "$CODE_LOG"
}

@test "_offer_open_conflicts opens nothing when declined" {
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
    "$DOTFILES_TEST_BIN" offer_open_conflicts "/tmp/r1|/tmp/l1" <<< "n"
  [ "$status" -eq 0 ]
  [ ! -s "$CODE_LOG" ]
}

@test "_offer_open_conflicts is silent and skipped in non-interactive shells" {
  stub_dir="$(mktemp -d)"
  CODE_LOG="$stub_dir/calls.log"
  : > "$CODE_LOG"
  cat > "$stub_dir/code" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$CODE_LOG"
EOF
  chmod +x "$stub_dir/code"
  # No DOTFILES_ASSUME_INTERACTIVE — bats `run` has no tty on stdin.
  run env \
    PATH="$stub_dir:$PATH" \
    "$DOTFILES_TEST_BIN" offer_open_conflicts "/tmp/r1|/tmp/l1"
  [ "$status" -eq 0 ]
  [ ! -s "$CODE_LOG" ]
  [[ "$output" != *"code --diff"* ]]
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
  [[ "$output" != *"code --diff"* ]]
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
