# Gantry image builds: ENOSPC poisons cached layers

When a gantry node's disk fills mid-build, `bootstrap.sh --yes …` can complete a
module with a swallowed download failure (observed 2026-08-04 on the control-plane
node: the python module lost `uv` to ENOSPC, the layer cached as successful, and
every later rebuild at that dotfiles rev died at `RUN uv python install 3.13` with
`uv: command not found` — seven remembered failures, while another node built the
same rev cleanly).

Remedies, cheapest first:

1. **Land any dotfiles commit.** The agent Dockerfiles embed the dotfiles rev as a
   cache probe inside the clone step, so a new rev forces the clone + bootstrap
   layers to rebuild while keeping base/apt layers cached.
2. `docker builder prune -f` on the affected node — full cache bust, slower rebuild.

Check disk before rebuilding: the fresh bootstrap needs a few GB transient space,
and a node that just recovered from ENOSPC may still be tight.
