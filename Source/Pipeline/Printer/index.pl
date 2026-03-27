/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> INDEX
HTML index page rendering for repository, category, and package listings.
Self-contained pages with inline CSS, day/night theme toggle, and card layout.
*/

:- module(index, []).

% =============================================================================
%  INDEX declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry points
% -----------------------------------------------------------------------------

%! index:print_repository_index(+Repository)
%
% Print the repository index listing all categories.

index:print_repository_index(Repository) :-
    findall(Cat, cache:category(Repository, Cat), Cats),
    length(Cats, Count),
    emit_page_open(Repository, '', Count, 'categories'),
    emit_breadcrumb_repo(Repository),
    collect_letters(Cats, Letters),
    emit_alphabet_bar(Letters),
    emit_grid_open_vertical,
    emit_anchored_items(Cats, category),
    emit_grid_close,
    emit_page_close.


%! index:print_category_index(+Repository, +Category)
%
% Print the category index listing all packages.

index:print_category_index(Repository, Category) :-
    findall(Name, cache:package(Repository, Category, Name), Names),
    length(Names, Count),
    atomic_list_concat([Repository, '://', Category], Title),
    emit_page_open(Title, '../', Count, 'packages'),
    emit_breadcrumb_category(Repository, Category),
    collect_letters(Names, Letters),
    emit_alphabet_bar(Letters),
    emit_grid_open_vertical,
    emit_anchored_items(Names, package),
    emit_grid_close,
    emit_page_close.


%! index:print_package_index(+Repository, +Category, +Name)
%
% Print the package index listing all versions with links to graph types.

index:print_package_index(Repository, Category, Name) :-
    findall(Entry-Version,
            ( cache:ordered_entry(Repository, Entry, Category, Name, Ver),
              eapi:version_full(Ver, Version)
            ),
            Pairs),
    length(Pairs, Count),
    atomic_list_concat([Repository, '://', Category, '/', Name], Title),
    emit_page_open(Title, '../', Count, 'versions'),
    emit_breadcrumb_package(Repository, Category, Name),
    emit_grid_open_vertical,
    forall(member(Entry-Version, Pairs),
           emit_card_version(Name, Entry, Version)),
    emit_grid_close,
    emit_page_close.


% -----------------------------------------------------------------------------
%  Page structure
% -----------------------------------------------------------------------------

emit_page_open(Title, CssPrefix, Count, Unit) :-
    write('<!DOCTYPE html>'), nl,
    write('<html lang="en" data-theme="dark">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    format('<title>~w</title>~n', [Title]),
    navtheme:emit_css_link(CssPrefix),
    write('</head>'), nl,
    write('<body class="page-index">'), nl,
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w <span class="count">(~w ~w)</span></h1>~n', [Title, Count, Unit]),
    navtheme:emit_theme_btn,
    write('</div>'), nl.

emit_page_close :-
    navtheme:emit_theme_script('index-theme'),
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  Breadcrumb navigation
% -----------------------------------------------------------------------------

emit_breadcrumb_repo(_Repository) :-
    write('<div class="breadcrumb"></div>'), nl,
    write('</div>'), nl.

emit_breadcrumb_category(Repository, _Category) :-
    write('<div class="breadcrumb">'), nl,
    format('  <a href="../index.html">~w</a>~n', [Repository]),
    write('</div>'), nl,
    write('</div>'), nl.

emit_breadcrumb_package(Repository, Category, _Name) :-
    write('<div class="breadcrumb">'), nl,
    format('  <a href="../index.html">~w</a> <span class="sep">/</span>~n', [Repository]),
    format('  <a href="./index.html">~w</a>~n', [Category]),
    write('</div>'), nl,
    write('</div>'), nl.


% -----------------------------------------------------------------------------
%  Grid and card elements
% -----------------------------------------------------------------------------

emit_grid_open :-
    write('<div class="grid">'), nl.

emit_grid_open_vertical :-
    write('<div class="grid vertical">'), nl.

emit_grid_close :-
    write('</div>'), nl.

emit_card_category(Cat) :-
    format('<a class="card" href="./~w/index.html">~w</a>~n', [Cat, Cat]).

emit_card_package(Name) :-
    format('<a class="card" href="./~w.html">~w</a>~n', [Name, Name]).


% -----------------------------------------------------------------------------
%  Alphabet quick-jump bar
% -----------------------------------------------------------------------------

%! index:collect_letters(+Items, -Letters)
%
% Extract sorted unique first letters (uppercased) from a list of atoms.

collect_letters(Items, Letters) :-
    maplist(item_first_letter, Items, Raw),
    sort(Raw, Letters).

item_first_letter(Item, Letter) :-
    sub_atom(Item, 0, 1, _, Ch),
    upcase_atom(Ch, Letter).


%! index:emit_alphabet_bar(+ActiveLetters)
%
% Emit a horizontal bar of A-Z letter links. Letters present in
% ActiveLetters are clickable anchors; others are grayed out.

emit_alphabet_bar(ActiveLetters) :-
    write('<div class="alpha-bar">'), nl,
    forall(member(L, ['A','B','C','D','E','F','G','H','I','J','K','L','M',
                       'N','O','P','Q','R','S','T','U','V','W','X','Y','Z']),
           emit_alpha_link(L, ActiveLetters)),
    write('</div>'), nl.

emit_alpha_link(Letter, Active) :-
    (   memberchk(Letter, Active)
    ->  format('<a class="alpha-link" href="#letter-~w">~w</a>~n', [Letter, Letter])
    ;   format('<span class="alpha-link disabled">~w</span>~n', [Letter])
    ).


%! index:emit_anchored_items(+Items, +Type)
%
% Emit card items with anchor spans inserted before each new letter group.

emit_anchored_items([], _).
emit_anchored_items([Item|Rest], Type) :-
    item_first_letter(Item, Letter),
    format('<span class="anchor" id="letter-~w"></span>~n', [Letter]),
    emit_letter_group(Letter, [Item|Rest], Type, Remaining),
    emit_anchored_items(Remaining, Type).

emit_letter_group(_, [], _, []).
emit_letter_group(Letter, [Item|Rest], Type, Remaining) :-
    item_first_letter(Item, ItemLetter),
    (   ItemLetter == Letter
    ->  emit_card_by_type(Type, Item),
        emit_letter_group(Letter, Rest, Type, Remaining)
    ;   Remaining = [Item|Rest]
    ).

emit_card_by_type(category, Cat) :- emit_card_category(Cat).
emit_card_by_type(package, Name) :- emit_card_package(Name).


emit_card_version(Name, Entry, Version) :-
    file_base_name(Entry, Base),
    write('<div class="card version-card">'), nl,
    format('  <a class="ver-label" href="./~w-detail.html">~w-~w</a>~n', [Base, Name, Version]),
    write('  <div class="ver-links">'), nl,
    format('    <a href="./~w-detail.html" title="detail">detail</a>~n', [Base]),
    format('    <a href="./~w-deptree.html" title="deptree">deptree</a>~n', [Base]),
    format('    <a href="./~w-gantt.html" title="gantt">gantt</a>~n', [Base]),
    format('    <a href="./~w-merge.html" title="merge">merge</a>~n', [Base]),
    format('    <a href="./~w-info.html" title="info">info</a>~n', [Base]),
    write('  </div>'), nl,
    write('</div>'), nl.




% -----------------------------------------------------------------------------
%  Legacy entry point (backward compatibility)
% -----------------------------------------------------------------------------

%! index:print_index(+Type, +Title, +TitleHtml, +Generator, +Template, +Stylesheet)
%
% Legacy entry point kept for backward compatibility. Delegates to the new
% type-specific predicates cannot be used directly because the new predicates
% need Repository/Category/Name context. Falls back to old XHTML rendering.

index:print_index(Type, Title, TitleHtml, Generator, Template, Stylesheet) :-
    index:print_index_header_legacy(Title, TitleHtml, Stylesheet),
    forall(Generator, index:print_index_element(Type, Template)),
    index:print_index_footer_legacy.

index:print_index_header_legacy(Title, TitleHtml, Stylesheet) :-
    writeln('<!DOCTYPE html>'),
    writeln('<html lang="en">'),
    writeln('<head>'),
    writeln('<meta charset="UTF-8">'),
    write('<title>'), write(Title), write('</title>'), nl,
    write('<link rel="stylesheet" href="'), write(Stylesheet), write('"/>'),
    writeln('</head>'),
    writeln('<body>'),
    write('<h1>'), write(TitleHtml), write('</h1>'), nl,
    writeln('<ul>').

index:print_index_footer_legacy :-
    writeln('</ul>'),
    writeln('</body>'),
    writeln('</html>').

index:print_index_element(repository, E) :-
    format('<li class="element"><a href="./~w/index.html">~w</a></li>~n', [E, E]).

index:print_index_element(category, E) :-
    format('<li class="element"><a href="./~w.html">~w</a></li>~n', [E, E]).

index:print_index_element(package, [E, V]) :-
    format('<li class="element"><a href="./~w-~w-detail.html">~w</a></li>~n', [E, V, V]).
