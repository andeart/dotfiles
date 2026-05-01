#!/usr/bin/env bats

load helpers/setup

@test "dotfiles --help lists the new subcommands" {
  run "$DOTFILES_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"freeze"* ]]
  [[ "$output" == *"status"* ]]
}

@test "dotfiles push exits 0 when not implemented (stub)" {
  run "$DOTFILES_BIN" push --dry-run
  [ "$status" -eq 0 ]
}

@test "dotfiles status exits 0 when not implemented (stub)" {
  run "$DOTFILES_BIN" status
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
