% *******************
% EBUILD declarations
% *******************

% Case 1: The ebuild has Metadata for the requested key

ebuild:get(Key,Context://Entry,Content) :-
  cache:entry(Context,Entry,_,_,_,_,Metadata),
  eapi:elem(Key,Metadata,Content).


% Case 2: The ebuild does not have Metadata for the requested key

ebuild:get(Key,Context://Entry,[]) :-
  cache:entry(Context,Entry,_,_,_,_,Metadata),
  not(eapi:elem(Key,Metadata,_)).
