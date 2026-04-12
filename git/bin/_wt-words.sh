#!/usr/bin/env bash
# Shared word lists for worktree branch-name generation.
# Sourced by git-wt-start and git-wt-pickup.

adjectives=(
  bold    brave   bright  calm    clean   clear   cool    deep
  dry     fair    fast    firm    flat    free    fresh   full
  great   hard    high    keen    kind    lean    light   long
  neat    new     noble   old     open    pure    quiet   raw
  rich    safe    sharp   slim    smart   soft    still   strong
  swift   thin    true    vast    warm    wide    wild    wise
  young   dark    fine    late
)
nouns=(
  arch    arrow   birch   blade   bluff   brook   cedar   cliff
  cloud   coral   cove    crest   dawn    dune    ember   falcon
  fern    field   flame   forest  gate    glade   grove   harbor
  knoll   lake    maple   marsh   meadow  mesa    oak     pass
  peak    pine    plain   pond    reef    ridge   river   shore
  spark   stone   storm   tide    torch   trail   vale    willow
  shield  frost   mist    north
)
# 36-character set: digits + uppercase letters
charset='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
