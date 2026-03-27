#!/bin/bash

# Bash completion for portage-ng / portage-ng-dev
# Install: source this file or copy to /etc/bash_completion.d/

_portage_ng() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  opts="
    --mode
    -a --ask
    -A --alert
    -v --verbose
    -p --pretend
    -f --fetchonly
    -F --fetch-all-uri
    -m --merge
    -u --update
    --upgrade
    -d --deep
    -e --emptytree
    -b --buildpkg
    -B --buildpkgonly
    --build
    -r --resume
    -N --newuse
    -U --changed-use
    --changed-deps
    --changed-slot
    --selective
    --select
    --deselect
    -n --noreplace
    -O --nodeps
    -o --onlydeps
    --with-bdeps
    --with-test-deps
    --dynamic-deps
    --rebuild-if-new-rev
    --rebuild-if-new-ver
    --rebuild-if-new-slot
    --rebuild-if-unbuilt
    --update-if-installed
    --exclude
    --skip
    -1 --oneshot
    --prefix
    --style
    --sync
    --clear
    --regen
    --metadata
    --list-sets
    --graph
    --check-news
    --read-news
    -c --depclean
    -i --info
    --bugs
    -s --search
    -C --unmerge
    -k --usepkg
    -K --usepkg-only
    -g --getbinpkg
    -G --getbinpkg-only
    --usepkg-exclude
    --usepkg-include
    --usepkg-exclude-live
    --binpkg-changed-deps
    --binpkg-respect-use
    --rebuilt-binaries
    --fail-clean
    -q --quiet
    -j --jobs
    --load-average
    --color
    --timeout
    --variants
    --host
    --port
    --shell
    --save
    --load
    -V --version
    --snapshot
    --rollback
    --snapshots
    --explain
    --llm
    --train-model
    --similar
    --estimate
    --upstream
    --search-bugs
    --contents
    --owner
    --size
    --verify
    --executables
    --fix-linkage
    --report
    --rdeps
    --unused-distfiles
    --import
    --unmanaged-files
    --continue-on-failure
    --favour
    --avoid
    --show-descriptions
    --permit-downgrade
    --preset
    --hide
    --early
    --late
    --lazy
    --complete
    --everything
    --background
    --status
    --cmd
    -l --logs
    --ci
    --profile
  "

  case "${prev}" in
    --mode)
      COMPREPLY=( $(compgen -W "standalone ipc daemon client server worker" -- "${cur}") )
      return 0
      ;;
    --style)
      COMPREPLY=( $(compgen -W "fancy column short" -- "${cur}") )
      return 0
      ;;
    --graph)
      COMPREPLY=( $(compgen -W "modified full build 'build modified' 'build full'" -- "${cur}") )
      return 0
      ;;
    --color|--with-bdeps|--with-test-deps)
      COMPREPLY=( $(compgen -W "y n" -- "${cur}") )
      return 0
      ;;
    --variants)
      COMPREPLY=( $(compgen -W "none auto all" -- "${cur}") )
      return 0
      ;;
    --llm)
      COMPREPLY=( $(compgen -W "claude grok chatgpt gemini ollama" -- "${cur}") )
      return 0
      ;;
    --cmd)
      COMPREPLY=( $(compgen -W "halt relaunch" -- "${cur}") )
      return 0
      ;;
    --continue-on-failure)
      COMPREPLY=( $(compgen -W "never if-satisfied if-independent always" -- "${cur}") )
      return 0
      ;;
    --show-descriptions)
      COMPREPLY=( $(compgen -W "none new all" -- "${cur}") )
      return 0
      ;;
    --prefix)
      COMPREPLY=( $(compgen -d -- "${cur}") )
      return 0
      ;;
    --host)
      COMPREPLY=( $(compgen -A hostname -- "${cur}") )
      return 0
      ;;
  esac

  if [[ "${cur}" == -* ]]; then
    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
    return 0
  fi
}

complete -F _portage_ng portage-ng
complete -F _portage_ng portage-ng-dev
