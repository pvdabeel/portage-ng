/*                                                                              
  Author:   Pieter Van den Abeele                                               
  E-mail:   pvdabeel@mac.com                                                    
  Copyright (c) 2005-2019, Pieter Van den Abeele                                
                                                                                
  Distributed under the terms of the LICENSE file in the root directory of this 
  project.                                                                      
*/                                                                              
                                                                                
                                                                                
/** <module> SCRIPTSi
This file declares a predicate to execute a script inside the scripts directory                                                             
*/     

:- module(script,[]).

% *******************
% SCRIPT declarations
% *******************


%! script:exec(+Name,+Args)
%
% Call script with arguments

script:exec(S,Args) :-
  is_list(Args),
  atomic_list_concat(['Source/Scripts/',S],Call),
  atomic_list_concat([Call|Args],' ',Cmd),
  shell(Cmd),!.
