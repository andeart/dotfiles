autoload -U promptinit; promptinit

# Uncomment this entire section below to enable random tab colors from rose-pine.
# function _iterm_random_tab_color() {
# local -a colors=(
#     "235 111 146"  # love  #eb6f92
#     "246 193 119"  # gold  #f6c177
#     "235 188 186"  # rose  #ebbcba
#     " 49 116 143"  # pine  #31748f
#     "156 207 216"  # foam  #9ccfd8
#     "196 167 231"  # iris  #c4a7e7
# )
# local pick="${colors[$((RANDOM % ${#colors[@]} + 1))]}"
# printf "\033]6;1;bg;red;brightness;%d\a"   ${pick%% *}
# printf "\033]6;1;bg;green;brightness;%d\a" ${${pick% *}##* }
# printf "\033]6;1;bg;blue;brightness;%d\a"  ${pick##* }
# }
# _iterm_random_tab_color
