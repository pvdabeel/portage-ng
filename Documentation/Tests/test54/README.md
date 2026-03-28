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

```ansi
[93m>>> Emerging : overlay://test54/app-1.0:run?{[]}
[00m
[32mThese are the packages that would be merged, in order:

[00mCalculating dependencies... done!

 └─[90m[00m[100mstep  1[00m[90m[00m─┤ [36mdownload[32m  overlay://test54/app-1.0[00m

 └─[90m[00m[100mstep  2[00m[90m[00m─┤ [36minstall[32m   overlay://test54/app-1.0[00m
             │           [90m└─ conf ─┤ [00m[90m[00m[100mUSE[00m[90m[00m = "[32m[01mxattr[00m* [34m[01m-selinux[00m% [90m[03m-apidoc[00m [90m[03m-bar1[00m [90m[03m-bar10[00m [90m[03m-bar11[00m [90m[03m-bar12[00m [90m[03m-bar13[00m [90m[03m-bar2[00m [90m[03m-bar3[00m [90m[03m-bar4[00m [90m[03m-bar5[00m [90m[03m-bar6[00m [90m[03m-bar7[00m [90m[03m-bar8[00m [90m[03m-bar9[00m [90m[03m-build[00m
             │                    [90m│          [90m[03m-doc[00m [90m[03m-foo1[00m [90m[03m-foo10[00m [90m[03m-foo11[00m [90m[03m-foo2[00m [90m[03m-foo3[00m [90m[03m-foo4[00m [90m[03m-foo5[00m [90m[03m-foo6[00m [90m[03m-foo7[00m [90m[03m-foo8[00m [90m[03m-foo9[00m [90m[03m-gentoo-dev[00m [90m[03m-ipc[00m [90m[03m-native-extensions[00m
             │                    [90m│          [90m[03m-rsync-verify[00m [90m[03m-test[00m"
             │          [90m          │ [00m[90m[00m[100mALSA_CARDS[00m[90m[00m = "[90m[03m-bar[00m [90m[03m-echo3g[00m [90m[03m-emu10k1[00m [90m[03m-foo[00m"
             │          [90m          │ [00m[90m[00m[100mMY_EXPANDING_USE[00m[90m[00m = "[90m[03m-bar[00m [90m[03m-cow[00m [90m[03m-foo[00m"
             │          [90m          │ [00m[90m[00m[100mVIDEO_CARDS[00m[90m[00m = "[31m[01mvmware[00m [90m[03m-nouveau[00m [90m[03m-v3d[00m [90m[03m-zink[00m"

 └─[90m[00m[100mstep  3[00m[90m[00m─┤ [32m[00m[42mrun[00m[32m[00m[01m[32m     overlay://test54/app-1.0[00m[00m

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       0.00 Kb to be downloaded.
```

</details>