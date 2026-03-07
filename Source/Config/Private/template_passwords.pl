% =================================================================================
% Rename this file to passwords.pl and set your passwords for the following below.
% =================================================================================


%! config:certificate_password(?Key,?Pass)
%
% Declares the password for the SSL client/server certificates

config:certificate_password(server,'').
config:certificate_password(client,'').


%! config:digestpassword(?User,?Pass)
%
% Declares the password for digest user authentication

config:digest_password('portage-ng','').


%! config:realm(?Pass)
%
% Declares the realm for digest user authentication

config:digest_realm('portage-ng').