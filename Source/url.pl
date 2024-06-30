/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> URL
Implements a parser for Universal Resource Locators as described
in RFC 3986. Successfull parsing results in an url prototype.
Using RFC 3986 ABNF (page 48) as basis for this grammar. This parser
does not support IPV6 nor fragments.
*/

:- module(url, [url/3]).

% ****************
% URL declarations
% ****************


% <url> ::= <scheme> <hierarchy>
%
% Parses url

url([S|H]) --> scheme(Ss), hierarchy(Hs), { atom_codes(S,Ss), atom_codes(H,Hs),! }.


% <scheme> ::= <alpha> *( <alpha> / <digit> / <minus> / <myplus> / <underscore> ) ":"
%
% Parses scheme

scheme([A|M])       --> alpha(A), scheme_more(M), ":".

scheme_more([A|M])  --> alpha(A), scheme_more(M).
scheme_more([D|M])  --> digit(D), scheme_more(M).
scheme_more([I|M])  --> minus(I), scheme_more(M).
scheme_more([P|M])  --> myplus(P), scheme_more(M).
scheme_more([U|M])  --> underscore(U), scheme_more(M).
scheme_more([])     --> [].


% <hierarchy> ::= "//" ( <authority> ) <host> ( <port> ) ( <path> ) ( <modules> )
%
% Parses hierarchy

hierarchy([A,H,P,T,M]) --> "//", authority(A), host(H), port(P), path(T), modules(M).


% <authority> ::= *( <alpha> / <digit> / <colon> ) "@"
%
% Parses authority

authority([A|M])    --> alpha(A), authority_more(M).
authority([D|M])    --> digit(D), authority_more(M).
authority([C|M])    --> colon(C), authority_more(M).
authority([])       --> [].

authority_more([A|M]) --> alpha(A), authority_more(M).
authority_more([D|M]) --> digit(D), authority_more(M).
authority_more([C|M]) --> colon(C), authority_more(M).
authority_more([])    --> "@".


% <host> ::=  ( <alpha> / <digit> ) *( <dot> <alpha> <digit> <minus> <underscore> )
%
% Parses host

host([A|M]) --> alpha(A), host_more(M).
host([D|M]) --> digit(D), host_more(M).
host([])    --> [].

host_more([D|M])  --> dot(D), host_more_after_dot(M).
host_more([A|M])  --> alpha(A), host_more(M).
host_more([D|M])  --> digit(D), host_more(M).
host_more([I|M])  --> minus(I), host_more(M).
host_more([U|M])  --> underscore(U), host_more(M).
host_more([])     --> [].

host_more_after_dot([A|M]) --> alpha(A), host_more(M).
host_more_after_dot([D|M]) --> digit(D), host_more(M).


% <port> ::= ":" <digit> *( <digit> )
%
% Parses port

port([D|M]) --> ":", digit(D), port_more(M).
port([])    --> [].

port_more([D|M])  --> digit(D), port_more(M).
port_more([])     --> [].


% <path> ::= <slash> *( <dot> / <tilde> / <alpha> / <digit> / <minus> / <slash> / <myplus> / <percent> / <ampersant> / <underscore> / <questionmark> )
%
% Parses path

path([L|M]) --> slash(L), path_more(M).
path([])    --> [].

path_more([D|M])  --> dot(D), path_more(M).
path_more([T|M])  --> tilde(T), path_more(M).
path_more([A|M])  --> alpha(A), path_more(M).
path_more([D|M])  --> digit(D), path_more(M).
path_more([I|M])  --> minus(I), path_more(M).
path_more([S|M])  --> slash(S), path_more(M).
path_more([P|M])  --> myplus(P), path_more(M).
path_more([P|M])  --> percent(P), path_more(M).
path_more([A|M])  --> ampersant(A), path_more(M).
path_more([U|M])  --> underscore(U), path_more(M).
path_more([Q|M])  --> questionmark(Q), path_more(M).
path_more([])     --> [].


% <modules> ::= *( <module> )
%
% Parses modules

modules([O|M]) --> module(O), modules(M).
modules([])    --> [].


% <module> ::= ":" <path> / ":" <alpha> *( <alpha> / <digit> / <minus> / <underscore> )
%
% Parses module

module(P)       --> colon(_), path(P).
module([A|M])   --> colon(_), alpha(A), module_more(M).

module_more([A|M]) --> alpha(A), module_more(M).
module_more([D|M]) --> digit(D), module_more(M).
module_more([I|M]) --> minus(I), module_more(M).
module_more([U|M]) --> underscore(U), module_more(M).
module_more([])    --> [].


% <unreserved> ::= <alpha> / <digit> / <minus / <dot> / <underscore> / <tilde>
%
% Parses unreserved chars

unreserved(A) --> alpha(A).
unreserved(D) --> digit(D).
unreserved(I) --> minus(I).
unreserved(D) --> dot(D).
unreserved(U) --> underscore(U).
unreserved(T) --> tilde(T).


% <char(X)> ::= <charcode>
%
% Parses chars

alpha(A)        --> [A], { code_type(A,alpha) }.
digit(D)        --> [D], { code_type(D,digit) }.
dot(D)          --> ".", { [D] = "." }.
star(S)         --> "*", { [S] = "*" }.
comma(C)        --> ",", { [C] = "," }.
colon(C)        --> ":", { [C] = ":" }.
minus(I)        --> "-", { [I] = "-" }.
equal(E)        --> "=", { [E] = "=" }.
tilde(T)        --> "~", { [T] = "~" }.
slash(S)        --> "/", { [S] = "/" }.
dollar(D)       --> "$", { [D] = "$" }.
myplus(P)       --> "+", { [P] = "+" }.
bracket(B)      --> "(", { [B] = "(" }.
bracket(B)      --> ")", { [B] = ")" }.
bracket(B)      --> "[", { [B] = "[" }.
bracket(B)      --> "]", { [B] = "]" }.
percent(B)      --> "%", { [B] = "%" }.
semicolon(S)    --> ";", { [S] = ";" }.
ampersant(A)    --> "&", { [A] = "&" }.
underscore(U)   --> "_", { [U] = "_" }.
exclamation(E)  --> "!", { [E] = "!" }.
questionmark(Q) --> "?", { [Q] = "?" }.


%! urltest(-Url)
%
% A test function

urltest(Url) :-
  url([P,H,O,A,T,M],Url,[]),
  string_to_list(PS,P),
  string_to_list(HS,H),
  string_to_list(OS,O),
  string_to_list(AS,A),
  string_to_list(TS,T),
  writeln(PS),
  writeln(HS),
  writeln(OS),
  writeln(AS),
  writeln(TS),
  maplist(string_to_list,MS,M),
  maplist(writeln,MS).
