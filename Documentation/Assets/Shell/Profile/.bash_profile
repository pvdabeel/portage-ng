alias portage-ng-dev="swipl -O \
  --stack-limit=256G --table-space=256G --shared-table-space=256G \
  -f /path/to/prolog/portage-ng.pl \
  -p portage=/path/to/prolog \
  -Dverbose_autoload=false \
  -g main --"

alias portage-ng-debug="swipl -O \
  --stack-limit=256G --table-space=256G --shared-table-space=256G \
  -f /path/to/prolog/portage-ng.pl \
  -p portage=/path/to/prolog \
  -Dverbose_autoload=false -Ddebug=true \
  -g main --"
