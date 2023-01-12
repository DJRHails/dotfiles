##? This is a mistake! You're looking at help for the doc.sh file

doc::help_msg() {
   local -r file="$1"
   echo "USAGE: $(basename "$file") [options]"
   grep "^##?" "$file" | cut -c 5-
}

doc::maybe_help() {
   local -r file="${0}"

   for arg in "${@}"; do
      case "${arg}" in
         -h|--help|--version) doc::help_msg "$file"; return 1;;
      esac
   done

   return 0;
}