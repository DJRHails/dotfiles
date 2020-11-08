doc::help_msg() {
   local -r file="$1"
   grep "^##?" "$file" | cut -c 5-
}

doc::maybe_help() {
   local -r file="$0"

   case "${!#:-}" in
      -h|--help|--version) doc::help_msg "$file"; exit 0 ;;
   esac
}