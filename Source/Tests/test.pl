
% Check that for a given repository, package names are parsed correctly

% portage:get_location(L),portage:read_entry(I,_,C,N,_),os:compose_path(L,C,CP),os:compose_path(CP,N,NP),not(exists_directory(NP)).


% Check that all entries on file have actually been read. 
% Compare also with find metadata/md5-cache -type f | wc -l

% findall(E,portage:read_entry(E,_,_,_,_),Es),length(Es,L),findall(EE,cache:entry(portage,EE,_,_,_,_,_),EEs),length(EEs,L)


% Find all ebuilds which clearly cannot be built

% findall(I,(portage:ebuild(I,C,N,V),ebuild:get(depend,I,D),member(package_dependency(no,DC,DN,_,_,_,_),D),not(cache:entry(_,CA,_,DC,DN,_,_)),write('BROKEN: '),write(I),write(' reason: Dependency '),write(DC),write('/'),write(DN),write(' does not exist.'),nl),Broken).


mytest :-
  testeapipackage('package'),nl,
  testeapipackage('package-1.1'),nl,
  testeapipackage('package-1.1-r1'),nl,
  testeapipackage('package-1.1-r1_p1'),nl,
  testeapipackage('package-1'),nl,
  testeapipackage('package-1-r1'),nl,
  testeapipackage('package-r1-1.1'),nl,
  testeapipackage('package-r1-1.1_p0-r1'),nl,
  testeapipackage('package-1-2'),nl,
  testeapipackage('package-r-1.1'),nl,
  testeapipackage('package-r-1-r1'),nl,
  testeapipackage('package-r1-1-r1'),nl,
  testeapipackage('package-2c'),nl,
  testeapipackage('package-2c-1'),nl,
  testeapipackage('package-2ch'),nl,
  testeapipackage('package-2ch-1'),nl,
  testeapipackage('package-2ch-2015'),nl,
  testeapipackage('package-2ch-2015_p1'),nl,
  testeapipackage('package-100dpi-1'),nl,
  testeapipackage('package-100dpi-1.1'),nl.


testeapipackage(A) :-
  atom_codes(A,C),phrase(eapi:package(P),C,R),
  write('A = '),write(A),nl,
  write('P = '),write(P),nl,
  write('R = '),write(R),nl.




testeapi :-
  packageversion('unp-2.0_pre7_p1-r1','unp','2.0_pre7_p1-r1'),
  packageversion('canna-2ch-20030827','canna-2ch','20030827'),
  packageversion('canna-2ch-20040519','canna-2ch','20040519'),
  packageversion('xxdiff-4.0_beta1_p20110426-r1','xxdiff','4.0_beta1_p20110426-r1'),
  packageversion('font-adobe-100dpi-1.0.3','font-adobe-100dpi','1.0.3'),
  packageversion('font-adobe-75dpi-1.0.3','font-adobe-75dpi','1.0.3'),
  packageversion('font-adobe-utopia-100dpi-1.0.4','font-adobe-utopia-100dpi','1.0.4'),
  packageversion('font-adobe-utopia-75dpi-1.0.4','font-adobe-utopia-75dpi','1.0.4'),
  packageversion('font-bh-100dpi-1.0.3','font-bh-100dpi','1.0.3'),
  packageversion('font-bh-75dpi-1.0.3','font-bh-75dpi','1.0.3'),
  packageversion('font-bh-lucidatypewriter-100dpi-1.0.3','font-bh-lucidatypewriter-100dpi','1.0.3'),
  packageversion('font-bh-lucidatypewriter-75dpi-1.0.3','font-bh-lucidatypewriter-75dpi','1.0.3'),
  packageversion('font-bitstream-100dpi-1.0.3','font-bitstream-100dpi','1.0.3'),
  packageversion('font-bitstream-75dpi-1.0.3','font-bitstream-75dpi','1.0.3'),
  packageversion('fping-2.4_beta2_p161-r2','fping','2.4_beta2_p161-r2'),
  packageversion('freerdp-1.1.0_beta1_p20130710-r2','freerdp','1.1.0_beta1_p20130710-r2'),
  packageversion('pkgconfig-0-r1','pkgconfig','0-r1'),
  packageversion('rb-readline-r7-0.5.2.0','rb-readline-r7','0.5.2.0').
