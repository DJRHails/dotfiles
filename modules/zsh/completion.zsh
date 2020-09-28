_grab() {
  _files -W "(${1//:/ })" -/;
}
compdef _grab grab

_jump() {
  _files -W "(${1//:/ })" -/;
}
compdef _jump jump

_p() { _jump $PROJECTS }
compdef _p p

_s() { _jump $SITES }
compdef _s s

_j() { _jump $JUMPPOINTS }
compdef _j j