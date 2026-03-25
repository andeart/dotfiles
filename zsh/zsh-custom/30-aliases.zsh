# Remove %z to remove time-zone
# Remove -t to remove time-based sorting
# alias lsa="ls -AFGhoT -D '%FT%T%z' -t"
alias lsa="ls -AFGho"

alias mdlint='markdownlint-cli2 --config ~/.markdownlint.yml'
alias pip='python3 -m pip'

flu() {
    case "$1" in
        a)   flutter analyze "${@:2}" ;;
        b)   flutter build "${@:2}" ;;
        c)   flutter clean "${@:2}" ;;
        doc) flutter doctor "${@:2}" ;;
        pg)  flutter pub get ;;
        t)   flutter test "${@:2}" ;;
        *)   flutter "$@" ;;
    esac
}

allansicolors() {
    for i in {0..255}; do
        printf '\033[38;5;%dm████ %3d\033[0m\n' $i $i
        [ $(( (i+1) % 16 )) -eq 0 ] && echo
    done
}
