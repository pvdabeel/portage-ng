#!/bin/sh

openssl req -new -key imac-pro.local.client-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Client Cert/OU=Client - imac-pro.local/CN=imac-pro.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out imac-pro.local.client-cert.pem -days 7300

openssl req -new -key imac-pro.local.server-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Server Cert/OU=Server - imac-pro.local/CN=imac-pro.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out imac-pro.local.server-cert.pem -days 7300

openssl req -new -key mac-pro.local.client-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Client Cert/OU=Client - mac-pro.local/CN=mac-pro.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out mac-pro.local.client-cert.pem -days 7300

openssl req -new -key mac-pro.local.server-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Server Cert/OU=Server - mac-pro.local/CN=mac-pro.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out mac-pro.local.server-cert.pem -days 7300

openssl req -new -key macbook-pro.local.client-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Client Cert/OU=Client - macbook-pro.local/CN=macbook-pro.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out macbook-pro.local.client-cert.pem -days 7309

openssl req -new -key macbook-pro.local.server-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Server Cert/OU=Server - macbook-pro.local/CN=macbook-pro.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out macbook-pro.local.server-cert.pem -days 7300

openssl req -new -key vm-linux.local.client-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Client Cert/OU=Client - vm-linux.local/CN=vm-linux.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out vm-linux.local.client-cert.pem -days 7300

openssl req -new -key vm-linux.local.server-key.pem -subj "/C=BE/ST=Vlaams-Brabant/L=Galmaarden/O=Portage-ng Demo Server Cert/OU=Server - vm-linux.local/CN=vm-linux.local/emailAddress=pvdabeel@mac.com" | openssl x509 -req -CA cacert.pem -CAkey cakey.pem -CAcreateserial -out vm-linux.local.server-cert.pem -days 7300
