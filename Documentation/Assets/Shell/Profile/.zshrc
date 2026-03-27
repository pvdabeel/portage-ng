alias portage-ng-dev="swipl -O \
  --stack-limit=32G  \
  -f /path/to/prolog/portage-ng.pl \
  -p portage=/path/to/prolog \
  -Dverbose_autoload=false \
  -g main --"