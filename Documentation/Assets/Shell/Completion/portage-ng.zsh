#compdef portage-ng portage-ng-dev

# Zsh completion for portage-ng
# Install: copy to a directory in $fpath, or source directly.
#   cp portage-ng.zsh /usr/local/share/zsh/site-functions/_portage-ng

_portage-ng() {
  local -a flags
  flags=(
    # Modes
    '--mode[Operation mode]:mode:(standalone ipc daemon client server worker)'

    # Core actions
    {-a,--ask}'[Ask for confirmation before proceeding]'
    {-A,--alert}'[Ring terminal bell when action needs attention]'
    {-v,--verbose}'[Turn on verbose mode]'
    {-p,--pretend}'[Turn on pretend mode]'
    {-f,--fetchonly}'[Turn on fetchonly mode]'
    {-F,--fetch-all-uri}'[Fetch all SRC_URI files regardless of USE flags]'
    {-m,--merge}'[Merge target package]'
    {-u,--update}'[Update target package]'
    '--upgrade[Upgrade set: emptytree plan then depclean]'
    {-d,--deep}'[Also consider dependencies]'
    {-e,--emptytree}'[Pretend no other packages are installed]'
    {-b,--buildpkg}'[Create binary packages after building from source]'
    {-B,--buildpkgonly}'[Build binary packages but do not merge]'
    '--build[Build target with live progress]'
    {-r,--resume}'[Resume previous command]'
    {-N,--newuse}'[Rebuild if USE or IUSE changed since install]'
    {-U,--changed-use}'[Rebuild only if effective USE flags changed]'
    '--changed-deps[Rebuild if runtime dependencies changed since install]'
    '--changed-slot[Rebuild if SLOT changed since install]'
    '--selective[Do not reinstall already-installed packages]'
    '--select[Add targets to world set]'
    '--deselect[Remove targets from world set without unmerging]'
    {-n,--noreplace}'[Skip already-installed packages]'
    {-O,--nodeps}'[Merge without resolving dependencies]'
    {-o,--onlydeps}'[Only merge dependencies, not the target itself]'
    '--with-bdeps[Include build-time dependencies]:yn:(y n)'
    '--with-test-deps[Include test dependencies]:yn:(y n)'
    '--dynamic-deps[Use repo dependency info instead of installed VDB]'
    '--rebuild-if-new-rev[Rebuild packages with new revision]'
    '--rebuild-if-new-ver[Rebuild packages with new version available]'
    '--rebuild-if-new-slot[Rebuild packages when slot operator deps change]'
    '--rebuild-if-unbuilt[Rebuild deps that have been rebuilt from source]'
    '--update-if-installed[Like --update but only for already-installed packages]'
    '--exclude[Exclude atoms from merge]:atom:'
    '--skip[Skip packages during --resume]:atom:'
    {-1,--oneshot}'[Do not add package to world]'
    '--prefix[Set the prefix directory]:path:_directories'
    '--style[Set printing style]:style:(fancy column short)'

    # Repository operations
    '--sync[Sync repository]'
    '--clear[Clear knowledge base]'
    '--regen[Regenerate ebuild metadata cache]'
    '--metadata[Regenerate ebuild metadata cache]'
    '--list-sets[List available package sets]'
    '--graph[Create graph]:type:(modified full build "build modified" "build full")'
    '--check-news[Check for and display unread news items]'
    '--read-news[Display news items when using --ask]'

    # Package queries
    {-c,--depclean}'[Clean dependencies]'
    {-i,--info}'[Show package version]'
    '--bugs[Print bug report drafts for the given target]'
    {-s,--search}'[Search for a target]'
    {-C,--unmerge}'[Unmerge target]'

    # Binary packages
    {-k,--usepkg}'[Use binary packages when available]'
    {-K,--usepkg-only}'[Use only binary packages]'
    {-g,--getbinpkg}'[Download binary packages from BINHOST]'
    {-G,--getbinpkg-only}'[Use only remote binary packages]'
    '--usepkg-exclude[Exclude atoms from binary package usage]:atom:'
    '--usepkg-include[Force binary package usage for specific atoms]:atom:'
    '--usepkg-exclude-live[Do not use binary packages for live ebuilds]'
    '--binpkg-changed-deps[Ignore binpkgs whose deps have changed]'
    '--binpkg-respect-use[Ignore binpkgs whose USE flags do not match]'
    '--rebuilt-binaries[Replace installed packages with rebuilt binaries]'
    '--fail-clean[Clean build directory on failure]'

    # Output
    {-q,--quiet}'[Reduced output]'
    {-j,--jobs}'[Number of parallel build jobs]:jobs:'
    '--load-average[Do not start new jobs if load average exceeds N]:load:'
    '--color[Enable or disable color output]:yn:(y n)'
    '--timeout[Abort proving/planning after N seconds]:seconds:'
    '--variants[Show alternative plans]:mode:(none auto all)'

    # Network
    '--host[Set server hostname]:hostname:_hosts'
    '--port[Set server port]:port:'
    '--shell[Go to interactive Prolog shell]'
    '--save[Save knowledgebase]'
    '--load[Load knowledgebase]'
    {-V,--version}'[Show version]'

    # Snapshot and rollback
    '--snapshot[Create snapshot before merge]:id:'
    '--rollback[Rollback to a named snapshot]:id:'
    '--snapshots[List available snapshots]'

    # LLM interaction
    '--explain[Explain build plan via LLM]:question:'
    '--llm[Start interactive chat with LLM]:service:(claude grok chatgpt gemini ollama)'
    '--train-model[Build semantic search embedding index]'
    '--similar[Find semantically similar packages]'
    '--estimate[Show estimated build time for packages]'

    # Upstream
    '--upstream[Check upstream for newer package versions]'
    '--search-bugs[Search Bugzilla for bugs matching the given term]'

    # VDB queries
    '--contents[List files installed by a package]'
    '--owner[Find which package owns a file]'
    '--size[Show disk space used by an installed package]'
    '--verify[Verify installed package files against recorded checksums]'
    '--executables[Show executables provided by a package]'

    # Maintenance
    '--fix-linkage[Rebuild packages with broken shared library linkage]'
    '--report[Report problems with installed packages]'
    '--rdeps[Show reverse dependencies of a package]'
    '--unused-distfiles[List distfiles not used by any installed package]'
    '--import[Track manually installed software in VDB]'
    '--unmanaged-files[Find files not owned by any installed package]'

    # Resolver hints
    '--continue-on-failure[Continue after build failure]:mode:(never if-satisfied if-independent always)'
    '--favour[Favour package in || dep choices]:atom:'
    '--avoid[Avoid package in || dep choices]:atom:'
    '--show-descriptions[Show USE flag descriptions]:mode:(none new all)'
    '--permit-downgrade[Allow older package versions]'
    '--preset[Pin a specific version]:atom:'
    '--hide[Exclude packages/repos from resolution]:atom:'
    '--early[Order matching packages earlier in the plan]:atom:'
    '--late[Order matching packages later in the plan]:atom:'

    # Presets
    '--lazy[Minimal work: skip installed, no deep deps]'
    '--complete[Full update: deep, newuse, follow build deps]'
    '--everything[Reinstall everything: emptytree + deep]'

    # Lifecycle
    '--background[Fork to background]'
    '--status[Check if daemon/server is running]'
    '--cmd[Send command to daemon/server]:command:(halt relaunch)'

    # Build options
    {-l,--logs}'[Show build log paths in --build output]'

    # Debugging
    '--ci[CI mode: non-interactive, fail with nonzero exit code on assumptions]'
    '--profile[Enable instrumentation]'
  )

  _arguments -s -S $flags '*:target:'
}

_portage-ng "$@"
