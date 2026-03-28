# test54 — Expanding USE flags output

**Category:** Printer

Expanding use flags output

**Expected:** The printer should succesfully split up the different expanding use

![test54](test54.svg)

<details>
<summary><b>emerge -vp</b></summary>

```
These are the packages that would be merged, in order:

Calculating dependencies  .... done!
Dependency resolution took 0.78 s (backtrack: 0/20).

[ebuild  N     ] test54/app-1.0::overlay  USE="xattr -apidoc -bar1 -bar2 -bar3 -bar4 -bar5 -bar6 -bar7 -bar8 -bar9 -bar10 -bar11 -bar12 -bar13 -build -doc -foo1 -foo2 -foo3 -foo4 -foo5 -foo6 -foo7 -foo8 -foo9 -foo10 -foo11 -gentoo-dev -ipc -my_expanding_use_bar -my_expanding_use_cow -my_expanding_use_foo -native-extensions -rsync-verify (-selinux) -test" ALSA_CARDS="-bar -echo3g -emu10k1 -foo" VIDEO_CARDS="vmware -nouveau (-v3d) -zink" 0 KiB

Total: 1 package (1 new), Size of downloads: 0 KiB
```

</details>

<details>
<summary><b>portage-ng</b></summary>

```
>>> Emerging : overlay://test54/app-1.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─step  1─┤ download  overlay://test54/app-1.0

 └─step  2─┤ install   overlay://test54/app-1.0
             │           └─ conf ─┤ USE = "xattr* -selinux% -apidoc -bar1 -bar10 -bar11 -bar12 -bar13 -bar2 -bar3 -bar4 -bar5 -bar6 -bar7 -bar8 -bar9 -build
             │                    │          -doc -foo1 -foo10 -foo11 -foo2 -foo3 -foo4 -foo5 -foo6 -foo7 -foo8 -foo9 -gentoo-dev -ipc -native-extensions
             │                    │          -rsync-verify -test"
             │                    │ ALSA_CARDS = "-bar -echo3g -emu10k1 -foo"
             │                    │ MY_EXPANDING_USE = "-bar -cow -foo"
             │                    │ VIDEO_CARDS = "vmware -nouveau -v3d -zink"

 └─step  3─┤ run     overlay://test54/app-1.0

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.
```

</details>