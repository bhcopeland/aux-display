#!/bin/sh
sleep 5
conky -c "${PWD}/conkyl.conf" &
conky -c "${PWD}/conkylm.conf" &
conky -c "${PWD}/conkyrm.conf" &
conky -c "${PWD}/conkyr.conf" &
